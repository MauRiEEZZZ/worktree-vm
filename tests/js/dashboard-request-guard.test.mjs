// The dashboard has no login and does not need one: it binds to loopback and is
// reached through the VM's port forward. A loopback binding does not keep the
// browser out, though. Verified against the unguarded server on 2026-10-15:
//
//   curl -X POST http://127.0.0.1:7300/api/sessions \
//        -H 'Content-Type: text/plain' -H 'Origin: https://example.invalid' \
//        --data '{"repo":"__nonexistent__","prompt":"probe"}'
//   {"error":"pick a repo"}   <- the body was parsed, the Origin ignored
//
// `readBody` JSON.parses whatever arrives regardless of Content-Type, and a
// text/plain form POST is a CORS "simple request", so the browser sends it
// cross-origin without a preflight. The attacker cannot read the reply and does
// not need to: POST /api/sessions starts an agent in a worktree with this
// machine's git and gh credentials, and `auto` in the same body turns off its
// approval prompts. The port forward runs whenever the VM runs, so the window
// is not limited to a tunnel the user opened.
//
// These assertions pin the three header checks that close it, and — just as
// important — that the endpoints the real UI uses still work, including the
// POSTs it sends with no body at all.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import http from 'node:http';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Raw http: fetch() refuses to set Host, and the rebinding case needs it.
function request(port, { method = 'GET', path = '/', headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path, headers }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

async function withServer(fn) {
  const home = mkdtempSync(join(tmpdir(), 'wt-test-guard.'));
  writeFileSync(join(home, '.bashrc'), 'wt-repos() { echo "demo example-org/demo-repo"; }\n');
  const port = 20000 + Math.floor(Math.random() * 10000);
  const child = spawn(process.execPath, [join(repo, 'dashboard', 'server.js')], {
    env: { ...process.env, HOME: home, PORT: String(port), PR_REVIEW_WATCH: '0', DIGEST: '0' },
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => (out += d));
  child.stderr.on('data', (d) => (err += d));
  try {
    await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`server did not come up.\nstdout:${out}\nstderr:${err}`)), 8000);
      child.stdout.on('data', () => { if (out.includes(`:${port}`)) { clearTimeout(t); resolve(); } });
      child.on('exit', (c) => { clearTimeout(t); reject(new Error(`server exited early (${c}).\nstderr:${err}`)); });
    });
    await fn(port);
  } finally {
    child.kill('SIGKILL');
    rmSync(home, { recursive: true, force: true });
  }
}

const JSON_BODY = JSON.stringify({ repo: '__nonexistent__', prompt: 'probe' });

test('the forged cross-site POST that worked before is refused', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/sessions',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'text/plain', origin: 'https://example.invalid', 'content-length': Buffer.byteLength(JSON_BODY) },
      body: JSON_BODY,
    });
    assert.equal(r.status, 403, `expected a refusal, got ${r.status}: ${r.body}`);
    assert.doesNotMatch(r.body, /pick a repo/, 'the request reached the application');
  });
});

test('a cross-site POST that declares JSON is refused too', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/sessions',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'application/json', origin: 'https://example.invalid', 'content-length': Buffer.byteLength(JSON_BODY) },
      body: JSON_BODY,
    });
    assert.equal(r.status, 403);
  });
});

test('a body that is not JSON is refused even without an Origin', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/sessions',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'text/plain', 'content-length': Buffer.byteLength(JSON_BODY) },
      body: JSON_BODY,
    });
    assert.equal(r.status, 415, `expected 415, got ${r.status}: ${r.body}`);
  });
});

test('a foreign Host is refused, which is what stops DNS rebinding', async () => {
  await withServer(async (port) => {
    const r = await request(port, { path: '/api/sessions', headers: { host: 'rebind.example.invalid' } });
    assert.equal(r.status, 403, `expected a refusal, got ${r.status}: ${r.body}`);
  });
});

test('the dashboard itself still works: same-origin POST reaches the application', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/sessions',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'application/json', origin: `http://127.0.0.1:${port}`, 'content-length': Buffer.byteLength(JSON_BODY) },
      body: JSON_BODY,
    });
    assert.equal(r.status, 400);
    assert.match(r.body, /pick a repo/, 'the guard swallowed a legitimate request');
  });
});

test('the CLI still works: no Origin, JSON body', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/sessions',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'application/json', 'content-length': Buffer.byteLength(JSON_BODY) },
      body: JSON_BODY,
    });
    assert.equal(r.status, 400);
    assert.match(r.body, /pick a repo/);
  });
});

// Several endpoints the UI uses are POSTs with no body and no Content-Type at
// all (the IDE controls, resume, the digest refresh). A guard that demands
// application/json unconditionally breaks every one of them.
test('a POST with no body is still allowed', async () => {
  await withServer(async (port) => {
    const r = await request(port, {
      method: 'POST', path: '/api/digest',
      headers: { host: `127.0.0.1:${port}`, origin: `http://127.0.0.1:${port}`, 'content-length': '0' },
    });
    assert.equal(r.status, 200, `expected the digest endpoint to answer, got ${r.status}: ${r.body}`);
  });
});

test('GET of the page itself is unaffected', async () => {
  await withServer(async (port) => {
    const r = await request(port, { path: '/', headers: { host: `127.0.0.1:${port}` } });
    assert.equal(r.status, 200);
    assert.match(r.body, /working trees/);
  });
});
