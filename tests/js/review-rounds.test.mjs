// Bug (2026-08-27): the card's reviewRounds counted EVERY review event, including
// COMMENTED. A reviewer who leaves twelve inline notes in one pass produced twelve
// "rounds"; one real PR read 35 where three reviews had been submitted. That number
// exists to answer one question — is the cheap dev model causing rework — and it was
// answering it wrong, in the direction of "yes". Decisions were being made on it.
// Zero deps: node:test + built-in fetch; the server runs in a throwaway HOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// One pass by a thorough reviewer: many comment events, one decision. Plus an
// earlier decided round, so the honest answer is 2.
const REVIEWS = [
  { state: 'COMMENTED' }, { state: 'COMMENTED' }, { state: 'COMMENTED' },
  { state: 'CHANGES_REQUESTED' },
  { state: 'COMMENTED' }, { state: 'COMMENTED' },
  { state: 'APPROVED' },
];

test('reviewRounds counts decided reviews, not comment volume', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-rounds.'));
  const bin = join(home, 'bin');
  mkdirSync(bin);
  // a session the dashboard will enumerate: a real git worktree on a branch
  const wt = join(home, 'wt', 'demo', 'feat-a');
  mkdirSync(wt, { recursive: true });
  const git = (...a) => execFileSync('git', ['-C', wt, ...a], { stdio: 'ignore' });
  execFileSync('git', ['init', '-q', '-b', 'feat/feat-a', wt], { stdio: 'ignore' });
  git('config', 'user.email', 't@t'); git('config', 'user.name', 't');
  writeFileSync(join(wt, 'f.txt'), 'x');
  git('add', 'f.txt'); git('commit', '-qm', 'init');

  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  writeFileSync(join(bin, 'gh'), `#!/usr/bin/env bash
if [ "$1" = pr ] && [ "$2" = list ]; then
  cat <<'J'
[{"number":42,"url":"https://github.test/pr/42","title":"t","state":"OPEN","isDraft":false,
  "reviewDecision":"APPROVED","statusCheckRollup":[],
  "reviews":${JSON.stringify(REVIEWS)}}]
J
  exit 0
fi
echo '[]'
`);
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
    assert.ok(s.pr, 'its PR is attached');
    assert.equal(s.pr.reviewRounds, 2, 'two decisions among seven events');
    assert.notEqual(s.pr.reviewRounds, REVIEWS.length, 'not the raw event count');
  } finally {
    child.kill();
    rmSync(home, { recursive: true, force: true });
  }
});
