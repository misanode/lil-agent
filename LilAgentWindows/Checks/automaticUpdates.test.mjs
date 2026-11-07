import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { createAutomaticUpdates } from '../electron/automaticUpdates.js';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function harness(options = {}) {
  const updater = new EventEmitter();
  updater.on('error', () => {});
  const checks = [];
  const downloads = [];
  const installs = [];
  const seen = [];
  updater.checkForUpdates = () => {
    const request = deferred();
    checks.push(request);
    return request.promise;
  };
  updater.downloadUpdate = () => {
    const request = deferred();
    downloads.push(request);
    return request.promise;
  };
  updater.quitAndInstall = (...args) => installs.push(args);
  const controller = createAutomaticUpdates({ updater, onChange: (value) => seen.push(value), ...options });
  return { updater, controller, checks, downloads, installs, seen };
}

async function tick() { await new Promise(setImmediate); }

async function available(h, latest = '1.1.0') {
  const checking = h.controller.check();
  await tick();
  h.updater.emit('update-available', { version: latest });
  h.checks.at(-1).resolve({ isUpdateAvailable: true, updateInfo: { version: latest } });
  await checking;
}

test('uses manual stable updates and coalesces checks without downloading', async () => {
  const h = harness();
  assert.equal(h.updater.autoDownload, false);
  assert.equal(h.updater.autoInstallOnAppQuit, false);
  assert.equal(h.updater.allowPrerelease, false);
  assert.equal(h.updater.allowDowngrade, false);
  assert.equal(h.updater.disableWebInstaller, true);
  const first = h.controller.check();
  assert.equal(h.controller.check(), first);
  assert.equal(h.controller.state.status, 'checking');
  await tick();
  assert.equal(h.checks.length, 1);
  h.updater.emit('update-available', { version: '1.1.0' });
  h.checks[0].resolve({ isUpdateAvailable: true, updateInfo: { version: '1.1.0' } });
  assert.equal(await first, true);
  assert.deepEqual(h.controller.state, { status: 'available', latest: '1.1.0' });
  assert.equal(h.downloads.length, 0);
  assert.equal(h.installs.length, 0);
  h.controller.stop();
});

test('one click downloads once and installs with restart only after the verified event', async () => {
  const h = harness();
  await available(h);
  const first = h.controller.apply();
  assert.equal(h.controller.apply(), first);
  await tick();
  assert.equal(h.downloads.length, 1);
  h.updater.emit('download-progress', { percent: 100 });
  assert.equal(h.installs.length, 0);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  assert.deepEqual(h.installs, [[true, true]]);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  await h.controller.apply();
  assert.equal(h.installs.length, 1);
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await first, true);
  assert.deepEqual(h.controller.state, { status: 'installing', latest: '1.1.0' });
  h.controller.stop();
});

test('a completed download promise does not substitute for the verified event', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await applying, false);
  assert.equal(h.installs.length, 0);
  assert.equal(h.controller.state.status, 'downloading');
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  assert.deepEqual(h.installs, [[true, true]]);
  h.controller.stop();
});

test('progress is bounded, integral, monotonic, and emitted only when its integer changes', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  for (const percent of [-10, 0.1, 0.8, 1.1, 1.9, 1.2, 0, NaN, Infinity, 52.7, 100, 200]) h.updater.emit('download-progress', { percent });
  assert.deepEqual(h.seen.filter((s) => s.status === 'downloading').map((s) => s.percent), [0, 1, 52, 100]);
  h.downloads[0].resolve([]);
  await applying;
  h.controller.stop();
});

test('quiet check failures preserve the last result and manual failures show safe retry information', async () => {
  const h = harness();
  await available(h);
  const prior = h.controller.state;
  const quiet = h.controller.check({ quiet: true });
  await tick();
  const error = new Error('offline https://example.invalid/private?token=example-token');
  h.updater.emit('error', error);
  h.checks.at(-1).reject(error);
  assert.equal(await quiet, false);
  assert.deepEqual(h.controller.state, prior);
  const manual = h.controller.check();
  await tick();
  h.checks.at(-1).reject(error);
  assert.equal(await manual, false);
  assert.deepEqual(h.controller.state, {
    status: 'failed', operation: 'check', error: 'Couldn’t reach the update server. Check your connection and try again.',
  });
  assert.ok(!JSON.stringify(h.controller.state).includes('example-token'));
  h.controller.stop();
});

test('download failures retain the version and allow a single fresh retry', async () => {
  const h = harness();
  await available(h);
  const first = h.controller.apply();
  await tick();
  const error = new Error('sha512 checksum mismatch');
  h.updater.emit('error', error);
  h.downloads[0].reject(error);
  assert.equal(await first, false);
  assert.deepEqual(h.controller.state, {
    status: 'failed', operation: 'download', latest: '1.1.0',
    error: 'The update failed its integrity check. Please try again.',
  });
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  assert.equal(h.installs.length, 0);
  const retry = h.controller.apply();
  assert.equal(h.controller.apply(), retry);
  await tick();
  assert.equal(h.downloads.length, 2);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.downloads[1].resolve(['installer.exe']);
  assert.equal(await retry, true);
  assert.deepEqual(h.installs, [[true, true]]);
  h.controller.stop();
});

test('a verified downloaded update waits for user intent and retries failed installation', async () => {
  const h = harness();
  await available(h);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  assert.equal(h.controller.state.status, 'downloaded');
  assert.equal(h.installs.length, 0);
  h.updater.quitAndInstall = () => { throw new Error('EPERM installer access denied'); };
  assert.equal(await h.controller.apply(), false);
  assert.equal(h.controller.state.operation, 'install');
  h.updater.quitAndInstall = (...args) => h.installs.push(args);
  assert.equal(await h.controller.apply(), true);
  assert.deepEqual(h.installs, [[true, true]]);
  assert.equal(h.downloads.length, 0);
  h.controller.stop();
});

test('an asynchronous installer error becomes retryable without another download', async () => {
  const h = harness();
  await available(h);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  await h.controller.apply();
  assert.doesNotThrow(() => h.updater.emit('error', new Error('installer failed')));
  assert.equal(h.controller.state.operation, 'install');
  assert.equal(await h.controller.apply(), true);
  assert.equal(h.installs.length, 2);
  assert.equal(h.downloads.length, 0);
  h.controller.stop();
});

test('apply waits for an in-flight quiet check and coalesces requests', async () => {
  const h = harness();
  await available(h);
  const checking = h.controller.check({ quiet: true });
  await tick();
  const first = h.controller.apply();
  assert.equal(h.controller.apply(), first);
  assert.equal(h.downloads.length, 0);
  h.updater.emit('update-available', { version: '1.2.0' });
  h.checks.at(-1).resolve({ isUpdateAvailable: true, updateInfo: { version: '1.2.0' } });
  await checking;
  await tick();
  assert.equal(h.downloads.length, 1);
  assert.equal(h.controller.state.latest, '1.2.0');
  h.updater.emit('update-downloaded', { version: '1.2.0' });
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await first, true);
  h.controller.stop();
});

test('stopping removes owned listeners and ignores late download completion', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  const prior = h.controller.state;
  h.controller.stop();
  assert.equal(h.updater.listenerCount('update-available'), 0);
  assert.equal(h.updater.listenerCount('download-progress'), 0);
  assert.equal(h.updater.listenerCount('update-downloaded'), 0);
  assert.equal(h.updater.listenerCount('error'), 1);
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.updater.emit('download-progress', { percent: 100 });
  h.updater.emit('error', new Error('late failure'));
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await applying, false);
  assert.deepEqual(h.controller.state, prior);
  assert.equal(h.installs.length, 0);
  assert.equal(await h.controller.check(), false);
  assert.equal(await h.controller.apply(), false);
});

test('start performs quiet periodic checks once and stop clears the interval', async (t) => {
  const timers = [];
  const cleared = [];
  t.mock.method(globalThis, 'setInterval', (callback, delay) => { timers.push({ callback, delay }); return timers.length; });
  t.mock.method(globalThis, 'clearInterval', (id) => cleared.push(id));
  const h = harness({ intervalMs: 1234 });
  h.controller.start();
  h.controller.start();
  await tick();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 1234);
  assert.equal(h.controller.state.status, 'idle');
  h.checks[0].resolve({ isUpdateAvailable: false });
  await tick();
  assert.equal(h.controller.state.status, 'current');
  timers[0].callback();
  await tick();
  h.updater.emit('update-available', { version: '1.1.0' });
  h.checks[1].resolve({ isUpdateAvailable: true, updateInfo: { version: '1.1.0' } });
  await tick();
  assert.equal(h.downloads.length, 0);
  h.controller.stop();
  h.controller.stop();
  h.controller.start();
  assert.deepEqual(cleared, [1]);
  assert.equal(timers.length, 1);
});

test('synchronous updater errors and observer exceptions do not escape events or promises', async () => {
  const h = harness({ onChange: () => { throw new Error('observer failed'); } });
  h.updater.checkForUpdates = () => { throw new Error('network unavailable'); };
  assert.equal(await h.controller.check(), false);
  assert.equal(h.controller.state.status, 'failed');
  assert.doesNotThrow(() => h.updater.emit('update-available', { version: '1.1.0' }));
  h.updater.downloadUpdate = () => { throw new Error('disk full'); };
  assert.equal(await h.controller.apply(), false);
  assert.equal(h.controller.state.operation, 'download');
  assert.equal(h.installs.length, 0);
  h.controller.stop();
});

test('joining a quiet check manually reports progress and makes failures visible', async () => {
  const h = harness();
  const quiet = h.controller.check({ quiet: true });
  assert.equal(h.controller.state.status, 'idle');
  assert.equal(h.controller.check(), quiet);
  assert.equal(h.controller.state.status, 'checking');
  await tick();
  assert.equal(h.checks.length, 1);
  h.checks[0].reject(new Error('offline'));
  assert.equal(await quiet, false);
  assert.equal(h.controller.state.status, 'failed');
  assert.equal(h.controller.state.operation, 'check');
  h.controller.stop();
});

test('stopping during a check ignores its later rejection and all update events', async () => {
  const h = harness();
  const checking = h.controller.check();
  await tick();
  h.controller.stop();
  const prior = h.controller.state;
  const notifications = h.seen.length;
  h.updater.emit('update-available', { version: '1.1.0' });
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.checks[0].reject(new Error('network unavailable'));
  assert.equal(await checking, false);
  assert.equal(h.seen.length, notifications);
  assert.deepEqual(h.controller.state, prior);
  assert.equal(h.downloads.length, 0);
  assert.equal(h.installs.length, 0);
});

test('a verified event for another version cannot install the selected update', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  h.updater.emit('update-downloaded', { version: '1.0.1' });
  assert.equal(h.installs.length, 0);
  assert.equal(h.controller.state.status, 'downloading');
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await applying, true);
  assert.equal(h.installs.length, 1);
  h.controller.stop();
});

test('installation failure during download completion reports false and retries without redownloading', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  h.updater.quitAndInstall = () => { throw new Error('installation failed'); };
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.downloads[0].resolve(['installer.exe']);
  assert.equal(await applying, false);
  assert.equal(h.controller.state.operation, 'install');
  h.updater.quitAndInstall = (...args) => h.installs.push(args);
  assert.equal(await h.controller.apply(), true);
  assert.equal(h.downloads.length, 1);
  assert.deepEqual(h.installs, [[true, true]]);
  h.controller.stop();
});

test('a late download-promise rejection preserves an already verified installation', async () => {
  const h = harness();
  await available(h);
  const applying = h.controller.apply();
  await tick();
  h.updater.emit('update-downloaded', { version: '1.1.0' });
  h.downloads[0].reject(new Error('late download callback failure'));
  assert.equal(await applying, false);
  assert.deepEqual(h.controller.state, { status: 'installing', latest: '1.1.0' });
  assert.deepEqual(h.installs, [[true, true]]);
  h.controller.stop();
});
