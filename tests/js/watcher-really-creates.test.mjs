// Bug (2026-09-03 → 2026-09-16, thirteen days): the PR-review watcher threw
// `branchCheckedOut is not defined` on every single poll and created nothing. A
// rename left two call sites behind, and the one the watcher reaches is not
// obvious: the watcher's review prompt carries the PR URL, createSession parses a
// ref out of the prompt, a PR ref in the same repo takes the "work on its existing
// branch" path, and that path called the renamed function.
//
// The suite did not catch it because the only watcher test ran with
// PR_REVIEW_DRYRUN=1, which returns one line BEFORE createSession. The dry run
// proved the decision and never the action. So this test drives the watcher for
// real: no DRYRUN, and `wt-new` deliberately absent from PATH — createSession
// spawns it detached and ignores the result, so nothing is created on the machine
// while every line up to the spawn runs for real.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SHA = 'cccccccccccccccccccccccccccccccccccccccc';

function fakeHome() {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-watcher.'));
  const bin = join(home, 'bin');
  mkdirSync(bin);
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  // A gh that answers every call the watcher makes on its way to creating a session.
  writeFileSync(join(bin, 'gh'), `#!/usr/bin/env bash
if [ "$1" = search ]; then
  echo '[{"number":42,"url":"https://github.com/example-org/demo-repo/pull/42","title":"t","repository":{"nameWithOwner":"example-org/demo-repo"}}]'
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  case "$*" in
    *headRefName,headRefOid*) echo '{"headRefName":"feat/x","headRefOid":"${SHA}"}' ;;
    *headRefName*)            echo 'feat/x' ;;
    *)                        echo 'A pull request title' ;;
  esac
  exit 0
fi
echo '[]'
`);
  chmodSync(join(bin, 'gh'), 0o755);
  return { home, bin };
}

test('the watcher gets all the way to starting a session, not just to deciding to', async () => {
  const { home, bin } = fakeHome();
  const port = 20000 + Math.floor(Math.random() * 10000);
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], {
    env: {
      ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, PORT: String(port),
      PR_REVIEW_OWNER: 'example-org', PR_REVIEW_POLL_MS: '3600000', DIGEST: '0',
      // no PR_REVIEW_DRYRUN: the whole point is to run the path the dry run skips
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
    const ledger = join(home, '.wt-meta', 'review-seen.json');
    for (let i = 0; i < 60 && !existsSync(ledger); i++) await new Promise(r => setTimeout(r, 100));

    assert.doesNotMatch(out + err, /poll error/, `the poll must not throw:\n${out}${err}`);
    assert.match(out, /\[pr-review\] started demo--review-42/, 'it reports a started session');
    assert.ok(existsSync(ledger), 'and records it in the ledger');
    const entry = JSON.parse(readFileSync(ledger, 'utf8'))['example-org/demo-repo#42'];
    assert.equal(entry.headSha, SHA, 'pinned to the head it reviewed, so round two can be detected');
    assert.equal(entry.round, 1, 'as round one');
  } finally {
    child.kill();
    rmSync(home, { recursive: true, force: true });
  }
});
