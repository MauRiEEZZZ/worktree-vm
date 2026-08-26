#!/usr/bin/env node
// wt dev-sessions dashboard — runs inside the dev VM.
// Zero external deps: Node built-in http + child_process only.
// Multi-repo: web UI + JSON API over the wt-* helpers, gh and tmux.
// Configuration comes from the environment (see ~/.config/wt/dashboard.env,
// generated from ~/.config/wt/config.yaml by lib/config/generate-env.sh).
'use strict';
const http = require('http');
const { execFile, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 7300;
const HOME = process.env.HOME;
const WT_TREES = path.join(HOME, 'wt');                 // ~/wt/<repo>/<name>
const META_DIR = process.env.WT_SESSIONS_DIR || path.join(HOME, '.wt-sessions');  // session metadata, keyed by sid
const ARCHIVE_DIR = path.join(META_DIR, 'archive');     // tombstones of deleted sessions (for restore)
const CLAUDE_PROJECTS = path.join(HOME, '.claude', 'projects');  // surviving conversation history per worktree path
const WT_META  = path.join(HOME, '.wt-meta');           // wt-* markers (e.g. <sid>.agent)
const AGENTS = ['claude', 'codex'];                     // selectable AI agents per session
const STATIC = path.join(__dirname, 'public');
// SSH alias/host of this VM as reachable from the user's workstation; used in the
// copy-attach / port-forward one-liners. Empty = the one-liners omit the ssh hop.
const SSH_HOST = process.env.WT_SSH_HOST || '';
// Model aliases offered in the "new session" model dropdown (Claude only).
const MODEL_CHOICES = (process.env.WT_MODEL_CHOICES || '').split(',').map(s => s.trim()).filter(Boolean);
// Instruction appended to the task when a BARE issue/PR URL is submitted with no
// prompt of its own (config dashboard.task_template). The factual lines above it —
// which issue, which repo, which branch — are always generated; this is the part
// that says how the work should be done, which is a house rule, not a fact. Empty
// = the built-in default. Placeholders: {repo} {repo_key} {name} {sid} {branch}
// {kind} {number} {url} {title} {meta_dir}.
const TASK_TEMPLATE = process.env.TASK_TEMPLATE || '';
const TASK_DEFAULT = 'Plan, implement, run the relevant tests, keep commits scoped. Ask if scope is unclear.';
function renderTemplate(tpl, vars) {
  // The config parser handles single-line scalars only (no block scalars), so a
  // multi-step house rule has to travel as one line: a literal \n in the value
  // becomes a real newline here.
  // Unknown placeholders are left as-is on purpose: a typo stays visible in the
  // session's own prompt instead of silently becoming an empty string.
  return tpl.replace(/\\n/g, '\n').replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
}
// Main-clone path overrides (config clone_paths), mirroring the bash _wt_clonepath.
let CLONE_PATHS = {};
try { CLONE_PATHS = JSON.parse(process.env.WT_CLONE_PATHS || '{}'); } catch {}
// PR-review watcher: periodically ask GitHub for PRs where review is requested from
// the authenticated user and auto-start a review dev-session for each (in the
// matching repo). Needs PR_REVIEW_OWNER; without it the watcher stays off.
const PR_REVIEW_WATCH = process.env.PR_REVIEW_WATCH !== '0';          // on by default; PR_REVIEW_WATCH=0 disables
const PR_REVIEW_DRYRUN = process.env.PR_REVIEW_DRYRUN === '1';        // log what it would create, don't spawn
const PR_REVIEW_POLL_MS = Number(process.env.PR_REVIEW_POLL_MS) || 300000;  // own background cadence (default 5 min)
const PR_REVIEW_OWNER = process.env.PR_REVIEW_OWNER || '';            // org/user to scope the search to; empty = watcher off
// Model for WATCHER review sessions — its OWN key (github.review_model), not
// agents.review_model: the watcher reviews someone else's PR, the owner reads
// the report and decides, so a missed nuance costs no lead time (unlike the
// pre-PR self-review gate). '' = account default.
const PR_REVIEW_MODEL = process.env.PR_REVIEW_MODEL || '';
const REVIEW_SEEN = path.join(WT_META, 'review-seen.json');          // ledger (NOT in META_DIR, which is scanned as sessions): <owner/repo>#<n> already handled
// Attention-digest: a cheap LLM pass over idle sessions -> ranked "who needs you, why, next".
const DIGEST = process.env.DIGEST !== '0';                           // feature on by default (on-demand)
const DIGEST_MODEL = process.env.DIGEST_MODEL || 'haiku';            // cheap by design (shared model budget)
const DIGEST_POLL_MS = Number(process.env.DIGEST_POLL_MS) || 0;      // 0 = on-demand only (no auto timer); set e.g. 600000 for 10-min auto
let lastDigest = { at: null, items: [], running: false };            // cached last result
// User-supplied regexes must never take the service down: the dashboard is a
// tool, not a validator. On an invalid value: log which key, fall back to the
// built-in default, keep running.
function regexFromEnv(name, fallback) {
  const v = process.env[name];
  if (!v) return fallback;
  try { return new RegExp(v, 'i'); }
  catch (e) {
    console.error(`[config] ${name} is not a valid regex (${e.message}); value: ${v} — falling back to the built-in default`);
    return fallback;
  }
}
// Deploy/preview-URL detection in PR comments (config dashboard.deploy_url_regex).
// Empty = feature off (no deploy badge, no extra gh calls); invalid = feature off too.
const DEPLOY_RE = regexFromEnv('DEPLOY_RE', null);

fs.mkdirSync(META_DIR, { recursive: true });

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    execFile(cmd, args, { maxBuffer: 16 * 1024 * 1024, timeout: 30000, ...opts },
      (err, stdout, stderr) => resolve({ err, out: (stdout || '').toString(), errOut: (stderr || '').toString() }));
  });
}
function bashi(command) { return run('bash', ['-ic', command]); } // loads the wt-* helpers from ~/.bashrc
function gh(args) { return run('gh', args); }
function slugify(s) {
  return (s || '').toLowerCase().normalize('NFKD').replace(/[^\w\s-]/g, '')
    .trim().replace(/[\s_]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'session';
}
function readMeta(sid) { try { return JSON.parse(fs.readFileSync(path.join(META_DIR, sid + '.json'), 'utf8')); } catch { return null; } }
function writeMeta(sid, obj) { fs.writeFileSync(path.join(META_DIR, sid + '.json'), JSON.stringify(obj, null, 2)); }
// Agent for a session: wt-new writes ~/.wt-meta/<sid>.agent (the source of truth); fall
// back to the create-time meta (while still starting) then to the default agent.
const AGENT_DEFAULT = AGENTS.includes(process.env.WT_AGENT_DEFAULT) ? process.env.WT_AGENT_DEFAULT : 'claude';
function readAgent(sid) {
  try { const a = fs.readFileSync(path.join(WT_META, sid + '.agent'), 'utf8').trim(); if (a) return a; } catch {}
  const m = readMeta(sid); return (m && m.agent) || AGENT_DEFAULT;
}
// Model override for a session ('' = account default); marker is the source of truth.
function readModel(sid) {
  try { const v = fs.readFileSync(path.join(WT_META, sid + '.model'), 'utf8').trim(); if (v) return v; } catch {}
  const m = readMeta(sid); return (m && m.model) || '';
}
// Per-session priority (p1|p2|p3, default p2) for the triage view; marker is the source of truth.
const PRIORITIES = ['p1', 'p2', 'p3'];
function readPriority(sid) {
  try { const v = fs.readFileSync(path.join(WT_META, sid + '.priority'), 'utf8').trim(); if (PRIORITIES.includes(v)) return v; } catch {}
  const m = readMeta(sid); return (m && PRIORITIES.includes(m.priority)) ? m.priority : 'p2';
}
function writePriority(sid, p) { if (!PRIORITIES.includes(p)) return false; try { fs.mkdirSync(WT_META, { recursive: true }); fs.writeFileSync(path.join(WT_META, sid + '.priority'), p + '\n'); return true; } catch { return false; } }
// MANUAL park: a user statement "this session's context is worth keeping, but it
// is not work-in-progress" (e.g. a finished review session kept around for
// follow-up comments). Same marker pattern as priority; the marker's existence
// is the state, so it survives a rebuild via the persisted ~/.wt-meta.
// Parking does NOTHING else BY DESIGN: the session keeps running, the worktree
// stays, nothing is stopped or removed — it is purely a UI grouping. Do not
// "improve" this by also killing the tmux session.
function readParked(sid) { return fs.existsSync(path.join(WT_META, sid + '.parked')); }
function writeParked(sid, on) {
  try {
    fs.mkdirSync(WT_META, { recursive: true });
    if (on) fs.writeFileSync(path.join(WT_META, sid + '.parked'), String(Date.now()) + '\n');
    else fs.rmSync(path.join(WT_META, sid + '.parked'), { force: true });
    return true;
  } catch { return false; }
}
// Idle-since tracking: stamp when a session first goes idle, clear when it works again.
function idleSince(sid, isIdle) {
  const f = path.join(WT_META, sid + '.idle_since');
  if (isIdle) {
    try { return Number(fs.readFileSync(f, 'utf8').trim()) || null; } catch {}
    const now = Date.now(); try { fs.mkdirSync(WT_META, { recursive: true }); fs.writeFileSync(f, String(now)); } catch {} return now;
  }
  try { fs.unlinkSync(f); } catch {}
  return null;
}
// Classify a session from its captured tmux pane. Returns { working, recap }.
// ONLY the hard evidence survives here: a spinner or a queued/running command
// on the ❯ prompt means "working"; everything else running is simply "not
// working" (waiting). Earlier versions also guessed "needs you" / "done" by
// phrase-matching one line of pane text — that was rarely the truth and was
// removed deliberately; the LLM attention digest (which actually READS the
// pane) is the replacement for that guess. recap stays: the last meaningful
// line, shown on the card and fed to the digest.
function paneState(pane) {
  const lines = (pane || '').split('\n').map(l => l.replace(/\s+$/, ''));
  const nonEmpty = lines.filter(l => l.trim());
  // spinner / active markers anywhere near the end
  const tail = nonEmpty.slice(-8).join('\n');
  const working = /(✻|✳|✶|Crunched for|esc to interrupt|\btokens\b.*\besc\b)/i.test(tail);
  // the input line is the one starting with ❯ ; text after it = a queued/running command
  const promptLine = [...lines].reverse().find(l => /^\s*❯/.test(l)) || '';
  const promptHasCmd = promptLine.replace(/^\s*❯\s?/, '').trim().length > 0;
  // recap = the ※ recap: line, else the last assistant line above the prompt
  let recap = '';
  const recapLine = [...nonEmpty].reverse().find(l => /※\s*recap:/i.test(l));
  if (recapLine) recap = recapLine.replace(/.*※\s*recap:\s*/i, '').trim();
  else {
    const pIdx = lines.lastIndexOf(promptLine);
    const above = (pIdx > 0 ? lines.slice(0, pIdx) : lines).filter(l => l.trim() && !/[─━]{6,}/.test(l) && !/^[─│┌┐└┘╭╮╰╯\s]*$/.test(l) && !/auto mode on|to save|to cycle|show tasks|\/rc\b/.test(l) && !/^\s*[✻✳✶]|Crunched for|esc to interrupt/.test(l));
    recap = (above[above.length - 1] || '').replace(/^[※•\s]+/, '').trim();
  }
  recap = recap.slice(0, 200);
  return { working: working || promptHasCmd, recap };
}
function sidOf(key, name) { return `${key}--${name}`; }
function splitSid(sid) { const i = sid.indexOf('--'); return i < 0 ? null : { key: sid.slice(0, i), name: sid.slice(i + 2) }; }

// --- repo registry (single source of truth = `wt-repos`) -------------------
// Cached, but invalidated when the config file's mtime changes — a config edit
// must show up in /api/repos without a service restart. (The bash side already
// regenerates its derived env on the same mtime signal, so the wt-repos call
// re-reads fresh values.)
const CONFIG_FILE = process.env.WT_CONFIG_FILE || path.join(HOME, '.config', 'wt', 'config.yaml');
let reposCache = null, reposCacheStamp = null;
function configStamp() { try { return fs.statSync(CONFIG_FILE).mtimeMs; } catch { return 0; } }
async function getRepos() {
  const stamp = configStamp();
  if (reposCache && stamp === reposCacheStamp) return reposCache;
  const { out } = await bashi('wt-repos');
  const map = {};
  out.trim().split('\n').forEach(l => { const m = l.trim().match(/^(\S+)\s+(\S+)$/); if (m) map[m[1]] = m[2]; });
  // don't cache an empty result (e.g. a transient wt-repos failure) — retry next call
  if (Object.keys(map).length) { reposCache = map; reposCacheStamp = stamp; }
  return map;
}

// --- session enumeration ---------------------------------------------------
function listSessionDirs() {
  const out = [];
  if (fs.existsSync(WT_TREES)) {
    for (const key of fs.readdirSync(WT_TREES)) {
      const kd = path.join(WT_TREES, key);
      if (!fs.statSync(kd).isDirectory()) continue;
      for (const name of fs.readdirSync(kd)) {
        const d = path.join(kd, name);
        if (!fs.existsSync(path.join(d, '.git'))) continue;
        out.push({ key, name, dir: d, sid: sidOf(key, name) });
      }
    }
  }
  return out;
}
async function tmuxSessions() {
  const { out, err } = await bashi("tmux list-sessions -F '#{session_name}\t#{session_created}\t#{session_attached}' 2>/dev/null");
  if (err) return {};
  const map = {};
  for (const line of out.trim().split('\n').filter(Boolean)) {
    const [name, created, attached] = line.split('\t'); map[name] = { created: Number(created) * 1000, attached: attached === '1' };
  }
  return map;
}
async function currentBranch(dir) {   // the worktree's ACTUAL checked-out branch
  const { out, err } = await run('git', ['-C', dir, 'branch', '--show-current']);
  return err ? null : out.trim();
}
// tmux target for the session's current PANE. Note the trailing ':' — it is not
// cosmetic. `-t '=<session>'` is a valid *session* target but NOT a pane target:
// capture-pane/send-keys answer "can't find pane" (or silently return nothing),
// which is how this once left every dashboard card without its pane text. The
// ':' selects the session's current window/pane while '=' still pins the session
// name exactly, so `foo` never resolves to `foo-review`.
const paneTarget = sid => JSON.stringify(`=${sid}:`);
async function activity(sid) {
  const { out } = await bashi(`tmux capture-pane -t ${paneTarget(sid)} -p 2>/dev/null`);
  return out.split('\n').map(l => l.replace(/\s+$/, '')).filter(l => l.trim()).slice(-14).join('\n');
}
async function paneOf(sid) {   // raw pane (last ~40 lines, unfiltered) for working/recap detection
  const { out } = await bashi(`tmux capture-pane -t ${paneTarget(sid)} -p 2>/dev/null`);
  return out.split('\n').slice(-40).join('\n');
}
async function prFor(repoFull, branch) {
  const { out, err } = await gh(['pr', 'list', '--repo', repoFull, '--head', branch, '--state', 'all',
    '--json', 'number,url,title,state,isDraft,statusCheckRollup,reviewDecision,reviews', '--limit', '1']);
  if (err) return null;
  let arr; try { arr = JSON.parse(out); } catch { return null; }
  const pr = arr && arr[0]; if (!pr) return null;
  const states = (pr.statusCheckRollup || []).map(c => c.conclusion || c.state).filter(Boolean);
  let checks = 'none';
  if (states.length) {
    if (states.some(s => /FAIL|ERROR|CANCEL/i.test(s))) checks = 'failing';
    else if (states.some(s => /PENDING|IN_PROGRESS|EXPECTED|QUEUED/i.test(s))) checks = 'pending';
    else checks = 'passing';
  }
  // reviewRounds: submitted reviews on the PR — the measurable for the cheap
  // dev tier hypothesis. Staying at 1-2 rounds means the savings are real;
  // 3+ means the dev tier is too tight for this codebase and should go back
  // up. One field from data we fetch anyway; no separate stats machinery.
  return { number: pr.number, url: pr.url, title: pr.title, state: pr.state, draft: pr.isDraft, checks,
    reviewDecision: pr.reviewDecision || '', reviewRounds: (pr.reviews || []).length };
}
// DERIVED state, deliberately not a marker: a session is "waiting on review"
// when its OPEN, non-draft PR has reviewDecision REVIEW_REQUIRED — the ball is
// with a reviewer, so the session is not work-in-progress. CHANGES_REQUESTED is
// intentionally NOT included: that means the ball is back with the author, i.e.
// there IS work to do, so the session stays in the WIP view (and APPROVED means
// it is yours to merge — also actionable). Because this is derived from the PR,
// the card moves between groups automatically when the PR status changes.
function isWaitingReview(pr) {
  return !!(pr && pr.state === 'OPEN' && !pr.draft && pr.reviewDecision === 'REVIEW_REQUIRED');
}
async function deployUrl(repoFull, prNumber) {
  if (!DEPLOY_RE) return null;   // feature off without a configured regex
  const { out, err } = await gh(['pr', 'view', String(prNumber), '--repo', repoFull, '--json', 'comments,body']);
  if (err) return null;
  let data; try { data = JSON.parse(out); } catch { return null; }
  for (const b of [data.body || '', ...(data.comments || []).map(c => c.body || '')]) {
    const m = b.match(DEPLOY_RE); if (m) return m[0];
  }
  return null;
}
function ideInfo(sid, tmux) {   // IDE backend state for this session (from tmux ide-<sid> + its log)
  const s = 'ide-' + sid;
  if (!tmux[s]) return { running: false };
  let link = null, port = null;
  try {
    const m = fs.readFileSync('/tmp/' + s + '.log', 'utf8').match(/tcp:\/\/127\.0\.0\.1:\d+#\S+/);
    if (m) { link = m[0]; port = (link.match(/:(\d+)#/) || [])[1]; }
  } catch {}
  const fwdHost = SSH_HOST || '<vm-host>';
  return { running: true, starting: !link, link, port, forward: port ? `ssh -N -L ${port}:127.0.0.1:${port} ${fwdHost}` : null };
}
async function buildSessions() {
  const [repos, tmux] = await Promise.all([getRepos(), tmuxSessions()]);
  const dirs = listSessionDirs();
  const seen = new Set(dirs.map(d => d.sid));
  for (const f of fs.readdirSync(META_DIR)) {            // metadata-only = still being created
    if (!f.endsWith('.json')) continue;
    const sid = f.replace(/\.json$/, '');
    if (seen.has(sid)) continue;
    const m = readMeta(sid) || {};
    const parts = splitSid(sid);
    dirs.push({ key: m.repo || (parts ? parts.key : sid), name: m.name || (parts ? parts.name : sid), dir: null, sid });
  }
  return Promise.all(dirs.map(async (s) => {
    const running = !!tmux[s.sid];
    const status = running ? 'running' : (s.dir ? 'stopped' : 'starting');
    const repoFull = repos[s.key] || null;
    const meta = readMeta(s.sid) || {};
    // Use the worktree's REAL branch (sessions may rename it / not follow feat/<name>).
    const branch = (s.dir ? await currentBranch(s.dir) : null) || meta.branch || `feat/${s.name}`;
    const [act, pane, pr] = await Promise.all([
      running ? activity(s.sid) : Promise.resolve(''),
      running ? paneOf(s.sid) : Promise.resolve(''),
      (s.dir && repoFull) ? prFor(repoFull, branch) : Promise.resolve(null),
    ]);
    const deploy = (pr && repoFull) ? await deployUrl(repoFull, pr.number) : null;
    // working/recap only meaningful for a running session. The field is a plain
    // boolean and deliberately RENAMED (no `attention` alias): the old tri-state
    // guess is gone, only the factual signal remains, and the dashboard UI is
    // this API's only consumer (it ships together with the server), so an alias
    // would just be the half-renamed field to avoid.
    const att = running ? paneState(pane) : { working: false, recap: '' };
    const waitingSince = running ? idleSince(s.sid, !att.working) : null;
    const parked = readParked(s.sid);
    return {
      id: s.sid, repo: s.key, repoFull, name: s.name, branch, status,
      agent: readAgent(s.sid), model: readModel(s.sid), priority: readPriority(s.sid),
      // Precedence: MANUAL parking always wins over the derived waiting-on-review
      // state — parking is an explicit user statement, the PR state is inference.
      // waitingReview is pre-resolved here so every consumer (UI grouping and
      // the digest) applies the same rule.
      parked, waitingReview: !parked && isWaitingReview(pr),
      working: att.working, recap: att.recap,
      waitingMs: (waitingSince && !att.working) ? (Date.now() - waitingSince) : null,
      attached: !!(tmux[s.sid] && tmux[s.sid].attached),
      created: tmux[s.sid] ? tmux[s.sid].created : (meta.createdAt || null),
      task: meta.task || null,
      issue: meta.sourceUrl ? { url: meta.sourceUrl, repo: meta.sourceRepo, number: meta.sourceNumber, kind: meta.sourceKind || 'issue' } : null,
      activity: act, pr, deploy, ide: ideInfo(s.sid, tmux),
    };
  })).then(list => list.sort((a, b) => (b.created || 0) - (a.created || 0)));
}

// --- create / delete -------------------------------------------------------
function parseGitHubRef(text) {
  const m = (text || '').match(/https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/(issues|pull)\/(\d+)/i);
  if (!m) return null;
  return { url: m[0], repo: `${m[1]}/${m[2]}`, kind: m[3] === 'pull' ? 'pr' : 'issue', number: Number(m[4]) };
}
async function refTitle(ref) {
  const { out } = await gh([ref.kind === 'pr' ? 'pr' : 'issue', 'view', String(ref.number), '--repo', ref.repo, '--json', 'title', '-q', '.title']);
  return (out || '').trim();
}
async function createSession(body) {
  const repos = await getRepos();
  const key = body.repo;                                  // REQUIRED — the work repo is explicit,
  if (!key || !repos[key]) return { error: 'pick a repo' }; // never inferred from the URL
  const agent = AGENTS.includes(body.agent) ? body.agent : AGENT_DEFAULT;
  const auto = !!body.auto, denyPost = !!body.denyPost;   // unattended run + block posting to GitHub
  const model = (typeof body.model === 'string' && /^[a-z0-9._-]+$/i.test(body.model)) ? body.model : '';  // optional model override
  const priority = PRIORITIES.includes(body.priority) ? body.priority : '';   // optional starting priority
  const fromRef = body.fromRef || '';                     // new feat/<name> branch off <ref> (skips PR-branch checkout)
  const promptText = (body.prompt || '').trim();
  let task = promptText;
  let name = body.name && slugify(body.name);
  const ref = parseGitHubRef(promptText);                 // URL is reference/context + naming only
  let title = '';
  if (ref) { title = await refTitle(ref); if (!name) name = `${ref.number}-${slugify(title)}`; }
  if (!name && task) name = slugify(task.split('\n')[0].split(/\s+/).slice(0, 6).join(' '));
  if (!name) return { error: 'enter a task or URL' };
  // If it's a PR in THIS repo, work on its existing branch (don't create a new feat/<name>).
  let existingBranch = '';
  if (!fromRef && ref && ref.kind === 'pr' && ref.repo.toLowerCase() === repos[key].toLowerCase()) {
    const { out } = await gh(['pr', 'view', String(ref.number), '--repo', ref.repo, '--json', 'headRefName', '-q', '.headRefName']);
    existingBranch = (out || '').trim();
    // Git allows a branch in only one worktree; if it's already checked out, wt-new --branch
    // would fail silently and leave a broken metadata-only session. Fail clearly instead.
    if (existingBranch && await branchCheckedOut(key, existingBranch)) {
      return { error: `branch ${existingBranch} is already checked out in another session — use that session, or create a separate branch with --from ${existingBranch}` };
    }
  }
  // A prompt that is nothing BUT the URL carries no instruction of its own, so the
  // house rule below is what the session must open with. This used to read
  // `!task && ref`, which is unreachable: `task` starts as the prompt and a bare
  // URL *is* the prompt — so a pasted URL became the session's entire opening
  // prompt, with no instruction at all, and task_template never applied.
  if (ref && (!task || task === ref.url)) {               // bare URL -> auto instruction
    const noun = ref.kind === 'pr' ? `pull request #${ref.number}` : `issue #${ref.number}`;
    const branchLine = existingBranch
      ? `You are on the PR's existing branch (${existingBranch}) in ${repos[key]} — continue that work.`
      : `Work in THIS repo (${repos[key]}); you are on a fresh worktree, branch feat/${name}, from the default branch.`;
    const instruction = renderTemplate(TASK_TEMPLATE || TASK_DEFAULT, {
      repo: repos[key], repo_key: key, name, sid: sidOf(key, name),
      branch: existingBranch || `feat/${name}`, kind: ref.kind, number: ref.number,
      url: ref.url, title, meta_dir: WT_META,
    });
    task = [
      `Context: GitHub ${noun} in ${ref.repo} — "${title}". Read it: gh ${ref.kind === 'pr' ? 'pr' : 'issue'} view ${ref.number} --repo ${ref.repo} --comments`,
      branchLine,
      instruction,
    ].join('\n');
  }
  const sid = sidOf(key, name);
  if (fs.existsSync(path.join(WT_TREES, key, name))) return { error: 'session already exists' };
  writeMeta(sid, {
    repo: key, name, agent, auto, denyPost, priority: priority || 'p2', sourceUrl: ref ? ref.url : null, sourceRepo: ref ? ref.repo : null,
    sourceNumber: ref ? ref.number : null, sourceKind: ref ? ref.kind : null,
    branch: existingBranch || `feat/${name}`, task, createdAt: Date.now(),
  });
  const b64 = Buffer.from(task || '', 'utf8').toString('base64');
  let cmd = `wt-new ${key} ${JSON.stringify(name)} --agent ${agent}`;
  if (auto) cmd += ' --auto';
  if (denyPost) cmd += ' --deny-post';
  if (model) cmd += ` --model ${model}`;
  if (priority) cmd += ` --priority ${priority}`;
  if (fromRef) cmd += ` --from ${JSON.stringify(fromRef)}`;
  if (existingBranch) cmd += ` --branch ${JSON.stringify(existingBranch)}`;
  if (task) cmd += ` --task-b64 ${b64}`;
  spawn('bash', ['-ic', cmd], { detached: true, stdio: 'ignore' }).unref();
  return { id: sid, repo: key, name, agent, status: 'starting', branch: existingBranch || `feat/${name}` };
}

// --- PR-review watcher -----------------------------------------------------
// Periodically ask GitHub for open PRs where review is requested from the authenticated
// user (scoped to PR_REVIEW_OWNER); for each PR in a known repo, auto-start a review
// dev-session (on the PR's branch) with a "review + ask before posting" prompt.
// A persistent ledger (review-seen.json) makes it idempotent — one session per PR, and it
// won't recreate a session you deleted.
function readSeen() { try { return JSON.parse(fs.readFileSync(REVIEW_SEEN, 'utf8')); } catch { return {}; } }
function writeSeen(o) { try { fs.mkdirSync(WT_META, { recursive: true }); fs.writeFileSync(REVIEW_SEEN, JSON.stringify(o, null, 2)); } catch {} }
// main-clone path for a repo key (mirrors the bash _wt_clonepath: config override wins)
function clonePathFor(key) {
  if (CLONE_PATHS[key]) return CLONE_PATHS[key];
  return path.join(HOME, 'repos', key);
}
// PRs that ALREADY have a dev-session (from session metadata: sourceRepo#sourceNumber) — so
// we never spawn a duplicate review session for a PR you're already working on.
function existingSessionPrs() {
  const set = new Set();
  try {
    for (const f of fs.readdirSync(META_DIR)) {
      if (!f.endsWith('.json')) continue;
      const m = readMeta(f.replace(/\.json$/, ''));
      if (m && m.sourceRepo && m.sourceNumber) set.add(`${String(m.sourceRepo).toLowerCase()}#${m.sourceNumber}`);
    }
  } catch {}
  return set;
}
// A git branch can be checked out in only one worktree; if the PR's head branch is already
// out, a review worktree can't be created — skip (a session for it effectively exists).
async function branchCheckedOut(key, branch) {
  if (!branch) return false;
  const { out } = await run('git', ['-C', clonePathFor(key), 'worktree', 'list', '--porcelain']);
  return out.split('\n').some(l => l.trim() === `branch refs/heads/${branch}`);
}
function reviewPrompt(pr, repoFull) {
  return [
    `You have been asked to review GitHub pull request #${pr.number} in ${repoFull}: "${pr.title}".`,
    pr.url,
    `You are on the PR branch in this worktree. Do a thorough, independent review:`,
    `- Read the PR: gh pr view ${pr.number} --repo ${repoFull} --comments  and  gh pr diff ${pr.number} --repo ${repoFull}`,
    `- Judge correctness, tests, scope and the repo's conventions.`,
    `Also get an INDEPENDENT second opinion from Codex via the codex MCP server (the mcp__codex__* tools): have Codex review the same PR/diff. If the MCP tool fails, fall back to 'codex exec "<review task>"' via bash.`,
    `Compare your findings with Codex's (where do you agree/disagree) and produce ONE consolidated list of findings, each with an exact file:line.`,
    `ANCHOR the review as a PENDING pull-request review with INLINE, line-anchored comments (not as a loose issue comment):`,
    `- Build JSON and run: gh api repos/${repoFull}/pulls/${pr.number}/reviews --input <file> . OMIT "event" -> that creates a PENDING review (a draft; only you see it until you submit it in the GitHub UI).`,
    `- Shape: {"commit_id":"<head sha from gh pr view --json headRefOid>","body":"<short summary + Codex second opinion>","comments":[{"path":"<path>","line":<line in the new version>,"side":"RIGHT","body":"<finding>"}, ...]}. Anchor each comment on the line it applies to; lines must exist in the PR diff/file.`,
    `- Do NOT submit/publish the review (no 'event', no gh pr review --approve/--request-changes). I will review and submit the pending review myself.`,
    `Afterwards, report here briefly how many inline comments you placed as pending; if a finding cannot be tied to a line, put it in the review body instead of inline.`,
  ].join('\n');
}
async function pollReviewRequests() {
  try {
    const repos = await getRepos();
    const byFull = {};                                   // owner/x -> registry key
    for (const k of Object.keys(repos)) byFull[repos[k].toLowerCase()] = k;
    const { out, err } = await gh(['search', 'prs', '--owner', PR_REVIEW_OWNER, '--review-requested=@me',
      '--state', 'open', '--json', 'number,title,url,repository', '--limit', '50']);
    if (err) { console.error('[pr-review] gh search failed:', (err && err.message) || err); return; }
    let prs; try { prs = JSON.parse(out); } catch { return; }
    const seen = readSeen();
    const existing = existingSessionPrs();            // PRs already worked on (by metadata)
    for (const pr of prs) {
      const full = ((pr.repository && pr.repository.nameWithOwner) || '').toLowerCase();
      const ledgerKey = `${full}#${pr.number}`;
      const key = byFull[full];
      if (!key) { console.log(`[pr-review] skip ${ledgerKey} (repo not in wt registry)`); continue; }
      if (seen[ledgerKey]) continue;                     // already handled in a previous poll
      // Dedup: don't duplicate a PR you already have a session for.
      if (existing.has(ledgerKey)) {
        seen[ledgerKey] = { skipped: 'session-exists', at: Date.now() }; writeSeen(seen);
        console.log(`[pr-review] skip ${ledgerKey} (session already exists)`); continue;
      }
      // Branch guard: a PR branch already checked out can't get a second worktree.
      const { out: hr } = await gh(['pr', 'view', String(pr.number), '--repo', pr.repository.nameWithOwner, '--json', 'headRefName', '-q', '.headRefName']);
      const headRef = (hr || '').trim();
      if (await branchCheckedOut(key, headRef)) {
        seen[ledgerKey] = { skipped: 'branch-checked-out', at: Date.now() }; writeSeen(seen);
        console.log(`[pr-review] skip ${ledgerKey} (branch ${headRef} already checked out)`); continue;
      }
      // One review session per PR (on the PR branch, --auto --deny-post + Remote
      // Control). It gets a second opinion from Codex via the codex MCP server (added user-
      // scoped, uses the same `codex login` auth) — see reviewPrompt — so it's one session with
      // two AI opinions, consolidated, and it asks before anything is posted.
      const name = `review-${pr.number}`;
      if (fs.existsSync(path.join(WT_TREES, key, name))) { seen[ledgerKey] = { sid: sidOf(key, name), at: Date.now() }; writeSeen(seen); continue; }
      if (PR_REVIEW_DRYRUN) { console.log(`[pr-review] DRYRUN would start ${sidOf(key, name)} for ${ledgerKey} — "${pr.title}"`); continue; }
      // model: the watcher's own key; 'default' = explicitly the account default,
      // so an empty key never lets a watcher review inherit the dev default_model.
      const r = await createSession({ repo: key, agent: 'claude', name, auto: true, denyPost: true, model: PR_REVIEW_MODEL || 'default', prompt: reviewPrompt(pr, repos[key]) });
      if (r && !r.error) { seen[ledgerKey] = { sid: r.id, at: Date.now() }; writeSeen(seen); console.log(`[pr-review] started ${r.id} for ${ledgerKey}`); }
      else { seen[ledgerKey] = { error: r && r.error, at: Date.now() }; writeSeen(seen); console.error(`[pr-review] create failed for ${ledgerKey}:`, r && r.error); }
    }
  } catch (e) { console.error('[pr-review] poll error:', (e && e.message) || e); }
}

// --- attention digest ------------------------------------------------------
// Cheap LLM pass over the running-but-not-working sessions: rank them and say,
// per session, WHY it needs the user and the suggested NEXT step. This digest
// IS the replacement for the removed needs-you/done phrase-matching: an LLM
// that actually reads the pane instead of a regex looking for a question mark.
// Cost-controlled: a cheap model, non-working-only, on-demand by default
// (DIGEST_POLL_MS=0). Result cached in lastDigest and served at GET /api/digest.
async function runDigest() {
  if (!DIGEST || lastDigest.running) return lastDigest;
  lastDigest.running = true;
  try {
    const sessions = await buildSessions();
    // Input: every RUNNING session that is not working right now — except
    // parked and waiting-on-review ones, which are deliberately excluded: both
    // are "not my problem right now" states, so the digest must not keep
    // demanding attention for them — exactly the clutter parking exists to remove.
    const idle = sessions.filter(s => s.status === 'running' && !s.working
      && !s.parked && !s.waitingReview);
    if (!idle.length) { lastDigest = { at: Date.now(), items: [], running: false }; return lastDigest; }
    const payload = idle.map(s => ({ sid: s.id, name: s.name, repo: s.repo, priority: s.priority, recap: s.recap, tail: (s.activity || '').split('\n').slice(-8).join('\n') }));
    const prompt = [
      'You are a triage assistant for parallel dev sessions. Below are sessions that are not working right now (possibly waiting for the user), as JSON.',
      'Per session, determine whether it really needs the user and why, and give the concrete next step. Rank from most to least urgent (weigh priority p1>p2>p3).',
      'Answer with ONLY a JSON array, no extra text: [{"sid","state":"needs_user|blocked|done|unclear","why":"<1 sentence>","next":"<1 sentence>"}].',
      'Sessions:', JSON.stringify(payload),
    ].join('\n');
    const b64 = Buffer.from(prompt, 'utf8').toString('base64');
    const model = DIGEST_MODEL ? `--model ${DIGEST_MODEL}` : '';
    // run headless; feed the prompt via base64 to avoid any quoting issues
    const { out, err } = await run('bash', ['-lc', `echo ${b64} | base64 -d | claude -p ${model} 2>/dev/null`], { timeout: 120000 });
    let items = [];
    const m = (out || '').match(/\[[\s\S]*\]/);
    if (m) { try { items = JSON.parse(m[0]); } catch {} }
    // join back name/priority for rendering
    const byId = Object.fromEntries(idle.map(s => [s.id, s]));
    items = (Array.isArray(items) ? items : []).map(it => ({ ...it, name: byId[it.sid] ? byId[it.sid].name : it.sid, priority: byId[it.sid] ? byId[it.sid].priority : 'p2' }));
    if (!items.length && err) console.error('[digest] no items;', (err && err.message) || err);
    lastDigest = { at: Date.now(), items, running: false, model: DIGEST_MODEL };
    console.log(`[digest] ${items.length} item(s) over ${idle.length} idle session(s)`);
    return lastDigest;
  } catch (e) { console.error('[digest] error:', (e && e.message) || e); lastDigest.running = false; return lastDigest; }
}

async function removeSession(sid, force) {
  const parts = splitSid(sid);
  if (!parts) return { error: 'invalid session id' };
  const cmd = `wt-rm ${parts.key} ${JSON.stringify(parts.name)}${force ? ' -f' : ''}`;
  const { err, errOut } = await bashi(cmd);
  // strip the interactive-bash-without-tty noise so only the real git message shows
  const clean = (errOut || '').split('\n')
    .filter(l => !/terminal process group|no job control/i.test(l)).join('\n').trim();
  if (err && !force) {
    // surface WHICH files block the safe delete, so the force-confirm isn't a blind prompt
    const { out } = await run('git', ['-C', path.join(WT_TREES, parts.key, parts.name), 'status', '--porcelain']);
    const dirty = out.split('\n').map(l => l.trim()).filter(Boolean).slice(0, 20);
    return { error: clean || 'remove failed', hint: 'unmerged/dirty — use force to discard', dirty };
  }
  // only now (successful/forced remove): TOMBSTONE the metadata instead of deleting it, so the
  // session can be restored later (the Claude history in ~/.claude survives too). Retains
  // branch/agent/model/priority/task/source for a high-fidelity restore.
  // NOTE: wt-rm tombstones too, so the metadata is usually already archived by the time we
  // get here — guard on the source still existing so we don't clobber wt-rm's (full-fidelity)
  // tombstone with a re-read.
  try {
    const src = path.join(META_DIR, sid + '.json');
    if (fs.existsSync(src)) {
      const meta = readMeta(sid) || {};
      meta.deletedAt = Date.now();
      fs.mkdirSync(ARCHIVE_DIR, { recursive: true });
      fs.writeFileSync(path.join(ARCHIVE_DIR, sid + '.json'), JSON.stringify(meta, null, 2));
      fs.unlinkSync(src);
    }
  } catch {}
  return { ok: true };
}

// --- restore deleted sessions ---------------------------------------------
// The Claude conversation history survives at ~/.claude/projects/<encoded worktree path> even
// after a delete. Recover a session by listing those (+ tombstones) and recreating the worktree
// at the SAME path, then `claude --continue` (wt-restore).
function historyDirFor(key, name) {                       // encoded ~/.claude/projects dir for a worktree path
  const enc = path.join(WT_TREES, key, name).replace(/[/.]/g, '-');   // '/' and '.' -> '-'
  const full = path.join(CLAUDE_PROJECTS, enc);
  return fs.existsSync(full) ? full : null;
}
function decodeWtProject(dirName, repoKeys) {             // encoded dir -> {repo,name,sid}
  const m = dirName.match(/-wt-(.+)$/); if (!m) return null;
  const rest = m[1];                                     // <repo>-<name>, repo may contain '-'
  const key = repoKeys.filter(k => rest === k || rest.startsWith(k + '-')).sort((a, b) => b.length - a.length)[0];
  if (!key) return null;
  const name = rest === key ? '' : rest.slice(key.length + 1);
  return name ? { repo: key, name, sid: `${key}--${name}` } : null;
}
function snippetFor(dir) {                                // recognizable context line from the latest jsonl
  try {
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl'))
      .map(f => ({ f, m: fs.statSync(path.join(dir, f)).mtimeMs })).sort((a, b) => b.m - a.m);
    if (!files.length) return { snippet: '', lastActive: null };
    const lines = fs.readFileSync(path.join(dir, files[0].f), 'utf8').split('\n').filter(Boolean);
    let summary = '', firstUser = '';
    for (const l of lines) { try { const j = JSON.parse(l);
      if (j.type === 'summary' && j.summary) summary = j.summary;
      else if (!firstUser && j.type === 'user' && j.message) { const c = j.message.content; const t = typeof c === 'string' ? c : (Array.isArray(c) ? c.map(x => x.text || '').join(' ') : ''); if (t.trim() && !t.trim().startsWith('<')) firstUser = t.trim(); }
    } catch {} }
    return { snippet: (summary || firstUser || '').replace(/\s+/g, ' ').slice(0, 140), lastActive: Math.round(files[0].m) };
  } catch { return { snippet: '', lastActive: null }; }
}
async function listRecoverable() {
  const repos = await getRepos(); const repoKeys = Object.keys(repos); const out = {};
  // tombstones (full fidelity: branch/agent/model retained)
  try { for (const f of fs.readdirSync(ARCHIVE_DIR)) {
    if (!f.endsWith('.json')) continue;
    const sid = f.replace(/\.json$/, ''); const parts = splitSid(sid); if (!parts) continue;
    if (fs.existsSync(path.join(WT_TREES, parts.key, parts.name))) continue;   // already live
    let m = {}; try { m = JSON.parse(fs.readFileSync(path.join(ARCHIVE_DIR, f), 'utf8')); } catch {}
    const hd = historyDirFor(parts.key, parts.name); const sn = hd ? snippetFor(hd) : { snippet: '', lastActive: null };
    out[sid] = { sid, repo: parts.key, name: parts.name, branch: m.branch || '', agent: m.agent || AGENT_DEFAULT, model: m.model || '',
      snippet: sn.snippet || (m.task ? String(m.task).split('\n')[0].slice(0, 140) : ''),
      lastActive: sn.lastActive || m.deletedAt || m.createdAt || null, hasHistory: !!hd, hasTombstone: true };
  } } catch {}
  // orphaned Claude histories without a tombstone (best-effort branch inference)
  try { for (const d of fs.readdirSync(CLAUDE_PROJECTS)) {
    if (!d.includes('-wt-')) continue;
    const dn = decodeWtProject(d, repoKeys); if (!dn || out[dn.sid]) continue;
    if (fs.existsSync(path.join(WT_TREES, dn.repo, dn.name))) continue;         // already live
    const sn = snippetFor(path.join(CLAUDE_PROJECTS, d));
    let branch = `feat/${dn.name}`; const rm = dn.name.match(/^review-(\d+)$/);
    if (rm && repos[dn.repo]) { try { const { out: hr } = await gh(['pr', 'view', rm[1], '--repo', repos[dn.repo], '--json', 'headRefName', '-q', '.headRefName']); if ((hr || '').trim()) branch = hr.trim(); } catch {} }
    out[dn.sid] = { sid: dn.sid, repo: dn.repo, name: dn.name, branch, agent: 'claude', model: '',
      snippet: sn.snippet, lastActive: sn.lastActive, hasHistory: true, hasTombstone: false };
  } } catch {}
  return Object.values(out).sort((a, b) => (b.lastActive || 0) - (a.lastActive || 0));
}
async function restoreSession(sid) {
  const parts = splitSid(sid); if (!parts) return { error: 'invalid session id' };
  const { key, name } = parts;
  if (fs.existsSync(path.join(WT_TREES, key, name))) return { error: 'session already exists (worktree present)' };
  let m = null; try { m = JSON.parse(fs.readFileSync(path.join(ARCHIVE_DIR, sid + '.json'), 'utf8')); } catch {}
  const isReview = /^review-\d+$/.test(name);
  const agent = (m && m.agent) || AGENT_DEFAULT;
  const model = (m && m.model) || '';
  const auto = m ? !!m.auto : isReview;                    // reviews default to auto + deny-post
  const denyPost = m ? !!m.denyPost : isReview;
  let branch = (m && m.branch) || '';
  if (!branch) {
    const rm = name.match(/^review-(\d+)$/); const repos = await getRepos();
    if (rm && repos[key]) { try { const { out: hr } = await gh(['pr', 'view', rm[1], '--repo', repos[key], '--json', 'headRefName', '-q', '.headRefName']); branch = (hr || '').trim(); } catch {} }
    if (!branch) branch = `feat/${name}`;
  }
  if (await branchCheckedOut(key, branch)) return { error: `branch ${branch} is already checked out in another session` };
  let cmd = `wt-restore ${key} ${JSON.stringify(name)} --branch ${JSON.stringify(branch)} --agent ${agent}`;
  if (model) cmd += ` --model ${model}`;
  if (auto) cmd += ' --auto';
  if (denyPost) cmd += ' --deny-post';
  spawn('bash', ['-ic', cmd], { detached: true, stdio: 'ignore' }).unref();
  // move the tombstone back to active metadata (so it shows in the session list again)
  if (m) { try { delete m.deletedAt; m.restoredAt = Date.now(); fs.writeFileSync(path.join(META_DIR, sid + '.json'), JSON.stringify(m, null, 2)); fs.unlinkSync(path.join(ARCHIVE_DIR, sid + '.json')); } catch {} }
  else { try { writeMeta(sid, { repo: key, name, agent, model, auto, denyPost, priority: 'p2', branch, createdAt: Date.now(), restoredAt: Date.now() }); } catch {} }
  return { id: sid, repo: key, name, status: 'starting', branch };
}

// --- http ------------------------------------------------------------------
function send(res, code, data, type) {
  if (type) { res.writeHead(code, { 'Content-Type': type }); return res.end(data); }
  // no-store: the dashboard polls this; never serve a cached (stale) session list.
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data));
}
function readBody(req) {
  return new Promise((resolve) => { let b = ''; req.on('data', c => b += c); req.on('end', () => { try { resolve(JSON.parse(b || '{}')); } catch { resolve({}); } }); });
}
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    const p = url.pathname;
    if (req.method === 'GET' && (p === '/' || p === '/index.html'))
      return send(res, 200, fs.readFileSync(path.join(STATIC, 'index.html')), 'text/html; charset=utf-8');
    if (req.method === 'GET' && p === '/favicon.svg')
      return send(res, 200, fs.readFileSync(path.join(STATIC, 'favicon.svg')), 'image/svg+xml');
    if (req.method === 'GET' && p === '/api/repos') {
      const repos = await getRepos();
      return send(res, 200, Object.keys(repos).sort().map(k => ({ key: k, full: repos[k] })));
    }
    if (req.method === 'GET' && p === '/api/agents') return send(res, 200, AGENTS);
    if (req.method === 'GET' && p === '/api/meta')
      return send(res, 200, { sshHost: SSH_HOST, models: MODEL_CHOICES, agentDefault: AGENT_DEFAULT });
    if (req.method === 'GET' && p === '/api/recoverable') return send(res, 200, await listRecoverable());
    if (req.method === 'POST' && p === '/api/sessions/restore') { const r = await restoreSession((await readBody(req)).sid); return send(res, r.error ? 400 : 202, r); }
    if (req.method === 'GET' && p === '/api/digest') return send(res, 200, { enabled: DIGEST, model: DIGEST_MODEL, ...lastDigest });
    if (req.method === 'POST' && p === '/api/digest') { const d = await runDigest(); return send(res, 200, { enabled: DIGEST, ...d }); }
    if (req.method === 'GET' && p === '/api/sessions') return send(res, 200, await buildSessions());
    if (req.method === 'POST' && p === '/api/sessions') { const r = await createSession(await readBody(req)); return send(res, r.error ? 400 : 202, r); }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/resume$/.test(p)) {
      const sid = decodeURIComponent(p.split('/')[3]);
      const parts = splitSid(sid);
      if (!parts) return send(res, 400, { error: 'invalid session id' });
      spawn('bash', ['-ic', `wt-resume ${parts.key} ${JSON.stringify(parts.name)}`], { detached: true, stdio: 'ignore' }).unref();
      return send(res, 202, { id: sid, status: 'starting' });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/priority$/.test(p)) {
      const sid = decodeURIComponent(p.split('/')[3]);
      const body = await readBody(req);
      if (!writePriority(sid, body.priority)) return send(res, 400, { error: 'priority must be p1, p2 or p3' });
      return send(res, 200, { id: sid, priority: body.priority });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/parked$/.test(p)) {
      // park/unpark = pure UI grouping (see writeParked); one click either way
      const sid = decodeURIComponent(p.split('/')[3]);
      const body = await readBody(req);
      if (!writeParked(sid, !!body.parked)) return send(res, 500, { error: 'could not update the parked marker' });
      return send(res, 200, { id: sid, parked: !!body.parked });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/model$/.test(p)) {
      // change the session's model via wt-model: sets the marker and relaunches
      // (claude --continue keeps the conversation; a live process cannot switch
      // models without a relaunch). 'default' / '' clears the override.
      const sid = decodeURIComponent(p.split('/')[3]);
      const parts = splitSid(sid);
      if (!parts) return send(res, 400, { error: 'invalid session id' });
      const body = await readBody(req);
      const model = (typeof body.model === 'string' && /^[a-z0-9._-]*$/i.test(body.model)) ? (body.model || 'default') : null;
      if (model === null) return send(res, 400, { error: 'invalid model alias' });
      spawn('bash', ['-ic', `wt-model ${parts.key} ${JSON.stringify(parts.name)} ${JSON.stringify(model)}`], { detached: true, stdio: 'ignore' }).unref();
      return send(res, 202, { id: sid, model: model === 'default' ? '' : model, status: 'relaunching' });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/review$/.test(p)) {
      // start an independent Claude+Codex review of this session's work (wt-review); report-only
      const sid = decodeURIComponent(p.split('/')[3]);
      const parts = splitSid(sid);
      if (!parts) return send(res, 400, { error: 'invalid session id' });
      const body = await readBody(req);
      const scope = ['committed', 'working', 'all'].includes(body.scope) ? body.scope : 'working';
      if (fs.existsSync(path.join(WT_TREES, parts.key, parts.name + '-review')))
        return send(res, 409, { error: 'a review session is already running; clean it up first' });
      spawn('bash', ['-ic', `wt-review ${parts.key} ${JSON.stringify(parts.name)} --scope ${scope}`], { detached: true, stdio: 'ignore' }).unref();
      return send(res, 202, { id: sid, reviewOf: sid, scope, status: 'starting' });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/ide$/.test(p)) {
      const sid = decodeURIComponent(p.split('/')[3]);
      const parts = splitSid(sid);
      if (!parts) return send(res, 400, { error: 'invalid session id' });
      // one at a time: refuse if any IDE backend already runs (in this or another session)
      const tmux = await tmuxSessions();
      const other = Object.keys(tmux).find(n => n.startsWith('ide-') && n !== 'ide-' + sid);
      if (other) return send(res, 409, { error: `Another IDE backend is running (${other.replace(/^ide-/, '')}); stop that one first` });
      // non-blocking: start the backend detached; the connect link appears in the poll (s.ide) ~30-90s later
      spawn('bash', ['-ic', `wt-ide ${parts.key} ${JSON.stringify(parts.name)}`], { detached: true, stdio: 'ignore' }).unref();
      return send(res, 202, { id: sid, status: 'starting' });
    }
    if (req.method === 'POST' && /^\/api\/sessions\/[^/]+\/ide\/stop$/.test(p)) {
      const sid = decodeURIComponent(p.split('/')[3]);
      await bashi(`tmux kill-session -t ${JSON.stringify('=ide-' + sid)}`);
      return send(res, 200, { ok: true });
    }
    if (req.method === 'DELETE' && p.startsWith('/api/sessions/')) {
      const sid = decodeURIComponent(p.slice('/api/sessions/'.length));
      const r = await removeSession(sid, url.searchParams.get('force') === '1');
      return send(res, r.error ? 409 : 200, r);
    }
    send(res, 404, { error: 'not found' });
  } catch (e) { send(res, 500, { error: String(e && e.message || e) }); }
});
server.listen(PORT, '127.0.0.1', () => console.log(`wt-dashboard on http://127.0.0.1:${PORT}`));
if (PR_REVIEW_WATCH && PR_REVIEW_OWNER) {
  console.log(`wt-dashboard PR-review watcher: every ${Math.round(PR_REVIEW_POLL_MS / 1000)}s, owner ${PR_REVIEW_OWNER}${PR_REVIEW_DRYRUN ? ' (DRYRUN)' : ''}`);
  pollReviewRequests();
  setInterval(pollReviewRequests, PR_REVIEW_POLL_MS);
} else if (PR_REVIEW_WATCH) {
  console.log('wt-dashboard PR-review watcher: off (set github.review_owner in the config to enable)');
}
if (DIGEST && DIGEST_POLL_MS > 0) {
  console.log(`wt-dashboard attention-digest: every ${Math.round(DIGEST_POLL_MS / 1000)}s, model ${DIGEST_MODEL}`);
  setInterval(runDigest, DIGEST_POLL_MS);
}
