// Bug (2026-09-03): a session blocked on an outward step it may not take itself had
// nowhere to say so. It said it in its own tmux pane; two PRs then sat for 3 and 16
// hours. The marker must reach the API, and whoever does the step must be able to
// clear it. Zero deps: node:test + built-in fetch; the server runs in a throwaway HOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('a handed-over session says so through the API, and can be cleared', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-handoff.'));
  const bin = join(home, 'bin');
  mkdirSync(bin);
  const wt = join(home, 'wt', 'demo', 'feat-a');
  mkdirSync(wt, { recursive: true });
  const git = (...a) => execFileSync('git', ['-C', wt, ...a], { stdio: 'ignore' });
  execFileSync('git', ['init', '-q', '-b', 'feat/feat-a', wt], { stdio: 'ignore' });
  git('config', 'user.email', 't@t'); git('config', 'user.name', 't');
  writeFileSync(join(wt, 'f.txt'), 'x');
  git('add', 'f.txt'); git('commit', '-qm', 'init');

  const marker = join(home, '.wt-meta', 'demo--feat-a.handoff');
  mkdirSync(join(home, '.wt-meta'), { recursive: true });
  writeFileSync(marker, 'ready for wt-push + draft PR: Show the rejection reason\n');

  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  writeFileSync(join(bin, 'gh'), "#!/usr/bin/env bash\necho '[]'\n");
  chmodSync(join(bin, 'gh'), 0o755);

  const port = 20000 + Math.floor(Math.random() * 10000);
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], {
    env: { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, PORT: String(port), PR_REVIEW_WATCH: '0', DIGEST: '0' },
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
    const sessions = await (await fetch(`http://127.0.0.1:${port}/api/sessions`)).json();
    const s = sessions.find(x => x.name === 'feat-a');
    assert.ok(s, `the session is listed (got ${JSON.stringify(sessions)})`);
    assert.equal(s.handoff, 'ready for wt-push + draft PR: Show the rejection reason',
      'the line the session wrote reaches the dashboard');

    const del = await fetch(`http://127.0.0.1:${port}/api/sessions/${encodeURIComponent(s.id)}/handoff`, { method: 'DELETE' });
    assert.equal(del.status, 200, 'the outward step can be marked done');
    assert.equal(existsSync(marker), false, 'and the marker is really gone');

    const after = await (await fetch(`http://127.0.0.1:${port}/api/sessions`)).json();
    assert.equal(after.find(x => x.name === 'feat-a').handoff, null, 'the session drops out of the handed-over group');
  } finally {
    child.kill();
    rmSync(home, { recursive: true, force: true });
  }
});
