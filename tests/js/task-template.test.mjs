// dashboard.task_template must reach the session's actual opening prompt.
// Why a test: the value crosses four layers on its way there (YAML -> generate-env
// -> systemd EnvironmentFile -> node), and the parser takes single-line scalars
// only, so the \n-to-newline step and the placeholder substitution are the two
// places where a house rule silently degrades back to the built-in default —
// which looks like "the workflow was ignored", not like a config bug.
// The same run covers the bug that made all of this moot: the auto-instruction
// branch was guarded by `!task && ref`, which cannot be true — `task` starts as
// the prompt and a bare URL IS the prompt. A pasted URL therefore became the
// session's whole opening prompt, instruction and all house rules dropped.
// Zero deps: node:test + built-in fetch; the server runs in a throwaway HOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// A HOME with just enough of the VM in it: wt-repos (read over `bash -ic`) and a
// gh that answers the title lookup. wt-new is deliberately absent — createSession
// spawns it detached and ignores the result, so its failure is invisible and
// nothing is created on the real machine.
function fakeHome() {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-tpl.'));
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "portal wortell/vidara.portal"; }\n');
  const bin = join(home, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'gh'), '#!/usr/bin/env bash\necho "Contacts show a rejection reason"\n');
  chmodSync(join(bin, 'gh'), 0o755);
  return { home, bin };
}

async function createWithTemplate(template) {
  const { home, bin } = fakeHome();
  const port = 20000 + Math.floor(Math.random() * 10000);
  const env = { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, PORT: String(port), PR_REVIEW_WATCH: '0' };
  if (template !== null) env.TASK_TEMPLATE = template;
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], { env });
  let out = '', err = '';
  child.stdout.on('data', d => out += d);
  child.stderr.on('data', d => err += d);
  try {
    await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`server did not come up.\nstdout:${out}\nstderr:${err}`)), 8000);
      child.stdout.on('data', () => { if (out.includes(`:${port}`)) { clearTimeout(t); resolve(); } });
      child.on('exit', c => { clearTimeout(t); reject(new Error(`server exited early (${c}).\nstderr:${err}`)); });
    });
    const res = await fetch(`http://127.0.0.1:${port}/api/sessions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      // a BARE url — no prompt of its own, which is the path that uses the template
      body: JSON.stringify({ repo: 'portal', prompt: 'https://github.com/wortell/vidara.portal/issues/2452' }),
    });
    assert.equal(res.status, 202, `session accepted (body: ${await res.text().catch(() => '?')})`);
    // the prompt the session will actually open with is persisted in its metadata
    const metaDir = join(home, '.wt-sessions');
    const file = readdirSync(metaDir).find(f => f.endsWith('.json'));
    assert.ok(file, 'session metadata was written');
    return JSON.parse(readFileSync(join(metaDir, file), 'utf8'));
  } finally {
    child.kill();
    rmSync(home, { recursive: true, force: true });
  }
}

test('the configured template replaces the default instruction, with placeholders resolved', async () => {
  const meta = await createWithTemplate(
    'Do not plan this yourself.\\nRead the plan at {meta_dir}/{sid}.plan.md — {repo}, branch {branch}, {kind} {number}.',
  );
  const lines = meta.task.split('\n');
  assert.match(lines[0], /issue #2452 in wortell\/vidara\.portal/, 'the factual context line survives');
  assert.equal(lines[2], 'Do not plan this yourself.', 'a literal \\n became a real newline');
  assert.match(lines[3], /\.wt-meta\/portal--2452-contacts-show-a-rejection-reason\.plan\.md/, '{meta_dir} and {sid} resolved');
  assert.match(lines[3], /wortell\/vidara\.portal, branch feat\/2452-contacts-show-a-rejection-reason, issue 2452\./, 'the rest resolved');
  assert.doesNotMatch(meta.task, /Plan, implement, run the relevant tests/, 'the built-in default is gone');
  assert.doesNotMatch(meta.task, /\{\w+\}/, 'no placeholder is left unsubstituted');
});

test('no template configured keeps the built-in instruction', async () => {
  const meta = await createWithTemplate(null);
  assert.match(meta.task, /Plan, implement, run the relevant tests, keep commits scoped\./);
});

test('an unknown placeholder stays visible instead of becoming empty', async () => {
  const meta = await createWithTemplate('Read {plan_path} for {repo}.');
  assert.match(meta.task, /Read \{plan_path\} for wortell\/vidara\.portal\./);
});
