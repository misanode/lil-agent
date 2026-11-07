import assert from 'node:assert/strict';
import test from 'node:test';
import { compareVersions, createUpdateChecker, evaluateRelease } from '../electron/updates.js';

const repo = 'owner/app';
const page = `https://github.com/${repo}/releases/tag/v1.1.0`;
const response = (status, body) => async () => ({ status, json: async () => body });

test('compares versions numerically', () => {
  assert.equal(compareVersions('1.0', '1.0.0'), 0);
  assert.equal(compareVersions('1.0.1', '1.0'), 1);
  assert.equal(compareVersions('1.10.0', '1.9.9'), 1);
  assert.equal(compareVersions('0.9', '1.0.0'), -1);
  assert.equal(compareVersions('2.0.0-beta', '2.0.0'), 0);
});

test('offers only newer releases from the project itself', () => {
  assert.deepEqual(evaluateRelease({ statusCode: 200, body: { tag_name: 'v1.1.0', html_url: page }, current: '1.0.0', repo }),
    { status: 'available', latest: '1.1.0', page });
  assert.deepEqual(evaluateRelease({ statusCode: 200, body: { tag_name: 'v1.0.0' }, current: '1.0.0', repo }), { status: 'current' });
  assert.deepEqual(evaluateRelease({ statusCode: 404, body: null, current: '1.0.0', repo }), { status: 'current' });
  assert.deepEqual(evaluateRelease({ statusCode: 500, body: null, current: '1.0.0', repo }), { status: 'failed' });
  assert.equal(evaluateRelease({ statusCode: 200, body: { tag_name: 'v2', html_url: 'https://evil.example/x' }, current: '1.0.0', repo }).page,
    `https://github.com/${repo}/releases/latest`);
});

test('a manual check reports progress and the result', async () => {
  const seen = [];
  const u = createUpdateChecker({ current: '1.0.0', repo, userAgent: 'test', fetch: response(200, { tag_name: 'v1.1.0', html_url: page }), onChange: (s) => seen.push(s.status) });
  await u.check();
  assert.deepEqual(seen, ['checking', 'available']);
  assert.equal(u.state.latest, '1.1.0');
});

test('a quiet check that fails keeps the last known result', async () => {
  let ok = true;
  const fetch = async () => { if (!ok) throw new Error('offline'); return { status: 200, json: async () => ({ tag_name: 'v1.2.0', html_url: page }) }; };
  const u = createUpdateChecker({ current: '1.0.0', repo, userAgent: 'test', fetch });
  await u.check({ quiet: true });
  ok = false;
  await u.check({ quiet: true });
  assert.equal(u.state.status, 'available');
  await u.check();
  assert.equal(u.state.status, 'failed');
});
