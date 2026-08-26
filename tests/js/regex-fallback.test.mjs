// Bug (2026-08-25, fix 7b3ff19): `new RegExp(process.env.DEPLOY_RE)` without a
// net meant one typo in a user's config crashed the whole dashboard with a
// stack trace at startup (and the EnvironmentFile mangling turned even VALID
// configs into exactly that). regexFromEnv must warn, fall back to the built-in
// default, and let the service start.
// Zero deps: node:test + built-in fetch; the server runs in a throwaway HOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('an invalid DEPLOY_RE must not take the dashboard down', async () => {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-js.'));
  const port = 20000 + Math.floor(Math.random() * 10000);
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], {
    env: { ...process.env, HOME: home, PORT: String(port), PR_REVIEW_WATCH: '0', DEPLOY_RE: '[unclosed' },
  });
  let out = '', err = '';
  child.stdout.on('data', d => out += d);
  child.stderr.on('data', d => err += d);
  try {
    // wait for the listen line (or early death)
    await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`server did not come up.\nstdout:${out}\nstderr:${err}`)), 8000);
      child.stdout.on('data', () => { if (out.includes(`:${port}`)) { clearTimeout(t); resolve(); } });
      child.on('exit', c => { clearTimeout(t); reject(new Error(`server exited early (${c}).\nstderr:${err}`)); });
    });
    const res = await fetch(`http://127.0.0.1:${port}/api/meta`);
    assert.equal(res.status, 200, 'the service answers despite the invalid regex');
    assert.match(err, /DEPLOY_RE is not a valid regex/, 'a clear warning names the offending key');
  } finally {
    child.kill();
    rmSync(home, { recursive: true, force: true });
  }
});
