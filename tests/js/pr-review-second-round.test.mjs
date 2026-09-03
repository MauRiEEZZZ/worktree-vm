// Bug (2026-09-03): the PR-review watcher was a one-shot. Its ledger was keyed on the
// PR alone, so once a review session had been started for owner/repo#N, that PR was
// skipped forever. The workflow it serves is a loop — you review, the author pushes
// fixes and re-requests review, and the PR comes back in the very same
// `--review-requested=@me` search — but round two never started. Two PRs sat waiting.
// The ledger must be keyed on the head SHA the last round reviewed.
// Zero deps: node:test + built-in fetch; the server runs in a throwaway HOME with a
// gh stub and PR_REVIEW_DRYRUN, so nothing is ever spawned.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// One poll of the watcher, with the PR at head `sha`. HOME is reused between calls
// so the ledger under ~/.wt-meta carries over, exactly as it does on the VM.
async function poll(home, sha) {
  const bin = join(home, 'bin');
  writeFileSync(join(bin, 'gh'), `#!/usr/bin/env bash
if [ "$1" = search ]; then
  echo '[{"number":42,"url":"https://github.test/pr/42","title":"t","repository":{"nameWithOwner":"example-org/demo-repo"}}]'
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  echo '{"headRefName":"feat/x","headRefOid":"${sha}"}'
  exit 0
fi
echo '[]'
`);
  chmodSync(join(bin, 'gh'), 0o755);
  const port = 20000 + Math.floor(Math.random() * 10000);
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], {
    env: {
      ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, PORT: String(port),
      PR_REVIEW_OWNER: 'example-org', PR_REVIEW_DRYRUN: '1', PR_REVIEW_POLL_MS: '3600000', DIGEST: '0',
    },
  });
  let out = '', err = '';
  child.stdout.on('data', d => out += d);
  child.stderr.on('data', d => err += d);
  try {
    await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`server did not come up.\nstdout:${out}\nstderr:${err}`)), 8000);
      child.stdout.on('data', () => { if (out.includes(`:${port}`)) { clearTimeout(t); resolve(); } });
      child.on('exit', c => { clearTimeout(t); reject(new Error(`server exited early (${c}).\nstderr:${err}`)); });
    });
    // the first poll runs at startup; give it a moment to finish its gh calls
    for (let i = 0; i < 40 && !/\[pr-review\]/.test(out); i++) await new Promise(r => setTimeout(r, 100));
  } finally {
    child.kill();
  }
  return out;
}

const A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

// What a REAL start writes. A dry run deliberately records nothing, so the test
// puts the watcher in the state a real round one would have left behind.
function recordRound(home, sid, headSha, round) {
  mkdirSync(join(home, '.wt-meta'), { recursive: true });
  writeFileSync(join(home, '.wt-meta', 'review-seen.json'),
    JSON.stringify({ 'example-org/demo-repo#42': { sid, headSha, round, at: Date.now() } }, null, 2));
}

test('a PR whose head moved gets a second review round', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-round2.'));
  mkdirSync(join(home, 'bin'));
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  try {
    const first = await poll(home, A);
    assert.match(first, /DRYRUN would start demo--review-42 /, 'round one is started');
    recordRound(home, 'demo--review-42', A, 1);

    // same head, review still requested: the SAME request, not a new one
    const again = await poll(home, A);
    assert.doesNotMatch(again, /DRYRUN would start/, 'an unchanged PR is not reviewed twice');

    // the author pushed fixes and re-requested review
    const second = await poll(home, B);
    assert.match(second, /DRYRUN would start demo--review-42-r2 /, 'round two starts under its own name');
    assert.match(second, /round 2, since aaaaaaaa/, 'and knows which commit it is reviewing from');
    assert.match(second, /moved aaaaaaaa -> bbbbbbbb, round 2/, 'and says why it started');
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});

test('a gh hiccup that hides the head SHA never re-reviews on a guess', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-round2b.'));
  mkdirSync(join(home, 'bin'));
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  try {
    recordRound(home, 'demo--review-42', A, 1);
    const out = await poll(home, '');
    assert.doesNotMatch(out, /DRYRUN would start/, 'an unknown head is treated as "already handled", not as "moved"');
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});

test('when the branch is still checked out, the round is handed to the session that holds it', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-round2c.'));
  mkdirSync(join(home, 'bin'));
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');

  // a clone whose PR branch is checked out in ~/wt/demo/review-42 — exactly the state
  // round one leaves behind when nobody has cleaned the session up yet
  const clone = join(home, 'repos', 'demo');
  mkdirSync(clone, { recursive: true });
  const git = (...a) => execFileSync('git', ['-C', clone, ...a], { stdio: 'ignore' });
  execFileSync('git', ['init', '-q', '-b', 'main', clone], { stdio: 'ignore' });
  git('config', 'user.email', 't@t'); git('config', 'user.name', 't');
  writeFileSync(join(clone, 'f.txt'), 'x');
  git('add', 'f.txt'); git('commit', '-qm', 'init');
  mkdirSync(join(home, 'wt', 'demo'), { recursive: true });
  git('worktree', 'add', '-q', '-b', 'feat/x', join(home, 'wt', 'demo', 'review-42'));

  try {
    recordRound(home, 'demo--review-42', A, 1);
    const out = await poll(home, B);
    assert.doesNotMatch(out, /DRYRUN would start/, 'no second worktree is attempted for a branch already out');
    assert.match(out, /handed to demo--review-42 \(round 2\)/, 'the log names who got it');
    const marker = readFileSync(join(home, '.wt-meta', 'demo--review-42.handoff'), 'utf8');
    assert.match(marker, /example-org\/demo-repo#42 has new commits since aaaaaaaa — review round 2/,
      'and that session is flagged on the dashboard instead of the news being lost in a log');
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});
