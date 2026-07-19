'use strict';

const { test, after } = require('node:test');
const assert = require('node:assert');
const server = require('../src/server');

function request(path) {
  return new Promise((resolve, reject) => {
    const req = require('http').request(
      { host: '127.0.0.1', port: server.address().port, path, method: 'GET' },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => resolve({ status: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.end();
  });
}

// Bind to an ephemeral port for the test run.
server.listen(0);

test('GET / returns Hello world', async () => {
  const res = await request('/');
  assert.strictEqual(res.status, 200);
  assert.match(res.body, /Hello world/);
});

test('GET /health returns 200 and status ok', async () => {
  const res = await request('/health');
  assert.strictEqual(res.status, 200);
  assert.match(res.body, /"status":"ok"/);
});

test('unknown route returns 404', async () => {
  const res = await request('/nope');
  assert.strictEqual(res.status, 404);
});

after(() => server.close());
