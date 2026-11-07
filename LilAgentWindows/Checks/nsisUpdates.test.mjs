import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';
import fs from 'node:fs/promises';
import { createRequire, Module } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import test from 'node:test';
import { createAutomaticUpdates } from '../electron/automaticUpdates.js';

const require = createRequire(import.meta.url);
const { NsisUpdater } = require('electron-updater/out/NsisUpdater.js');
const { ElectronHttpExecutor } = require('electron-updater/out/electronHttpExecutor.js');
const FEED = 'https://updates.invalid/';
const INSTALLER = 'Lil-Agent-Windows-Setup.exe';
const FUTURE_VERSION = '1.0.2';
const tick = () => new Promise(setImmediate);

class FixtureHttpExecutor extends ElectronHttpExecutor {
  constructor(fixtures) {
    super(null);
    this.fixtures = fixtures;
    this.requests = [];
  }

  createRequest(options, callback) {
    assert.equal(options.hostname, 'updates.invalid');
    const pathname = new URL(options.path, FEED).pathname;
    assert.ok(this.fixtures.has(pathname), `Unexpected fixture request: ${pathname}`);
    this.requests.push(pathname);
    const payload = this.fixtures.get(pathname);
    const request = new EventEmitter();
    let aborted = false;
    let response;
    request.abort = () => { aborted = true; response?.destroy(); };
    request.end = () => {
      queueMicrotask(() => {
        if (aborted) return;
        const middle = Math.ceil(payload.length / 2);
        response = Readable.from([payload.subarray(0, middle), payload.subarray(middle)], { objectMode: false });
        response.statusCode = 200;
        response.statusMessage = 'OK';
        response.headers = {
          'content-length': String(payload.length),
          'content-type': pathname.endsWith('.yml') ? 'text/yaml' : 'application/octet-stream',
        };
        callback(response);
      });
      return request;
    };
    return request;
  }
}

async function harness(t, { tampered = false } = {}) {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'lil-agent-nsis-updates-'));
  const installer = Buffer.concat([Buffer.from('MZ fixture installer, never executable\n'), Buffer.alloc(64 * 1024, 0x61)]);
  const expectedHash = createHash('sha512').update(installer).digest('base64');
  const delivered = Buffer.from(installer);
  if (tampered) delivered[delivered.length - 1] ^= 0xff;
  const metadata = Buffer.from([
    `version: ${FUTURE_VERSION}`,
    'files:',
    `  - url: ${INSTALLER}`,
    `    sha512: ${expectedHash}`,
    `    size: ${installer.length}`,
    `path: ${INSTALLER}`,
    `sha512: ${expectedHash}`,
    'releaseDate: 2026-01-01T00:00:00.000Z',
    '',
  ].join('\n'));
  const configPath = path.join(temporary, 'app-update.yml');
  await fs.writeFile(configPath, JSON.stringify({
    provider: 'generic', url: FEED, updaterCacheDirName: 'fixture-updates',
  }));

  const electronPath = require.resolve('electron');
  const previousElectronModule = require.cache[electronPath];
  const nativeUpdater = new EventEmitter();
  const electronModule = new Module(electronPath);
  electronModule.filename = electronPath;
  electronModule.loaded = true;
  electronModule.exports = { autoUpdater: nativeUpdater };
  require.cache[electronPath] = electronModule;

  const events = [];
  const launches = [];
  const errors = [];
  const states = [];
  let quits = 0;
  const app = {
    version: '1.0.1', name: 'Lil Agent fixture', isPackaged: true,
    appUpdateConfigPath: configPath,
    userDataPath: path.join(temporary, 'user-data'),
    baseCachePath: path.join(temporary, 'cache'),
    whenReady: () => Promise.resolve(),
    relaunch() { assert.fail('Direct application relaunch is not expected'); },
    quit() { quits += 1; events.push('quit'); },
    onQuit() { assert.fail('Automatic install-on-quit must remain disabled'); },
  };
  const updater = new NsisUpdater(null, app);
  const transport = new FixtureHttpExecutor(new Map([
    ['/latest.yml', metadata], [`/${INSTALLER}`, delivered],
  ]));
  updater.logger = null;
  updater.httpExecutor = transport;
  updater._testOnlyOptions = { platform: 'win32', isUseDifferentialDownload: false };
  updater.setFeedURL({ provider: 'generic', url: FEED });
  updater.spawnLog = async (file, args) => {
    events.push('installer-launch');
    launches.push({ file, args });
    return true;
  };
  updater.spawnSyncLog = () => assert.fail('No synchronous process launch is allowed');
  const signatureVerifier = updater.verifyUpdateCodeSignature;
  updater.on('error', (error) => errors.push(error));
  updater.on('update-downloaded', () => events.push('verified-download'));
  nativeUpdater.on('before-quit-for-update', () => events.push('before-quit-for-update'));
  const controller = createAutomaticUpdates({ updater, onChange: (state) => states.push(state) });

  t.after(async () => {
    await tick();
    controller.stop();
    if (previousElectronModule) require.cache[electronPath] = previousElectronModule;
    else delete require.cache[electronPath];
    await fs.rm(temporary, { recursive: true, force: true });
  });

  return {
    controller, updater, transport, installer, expectedHash, launches, errors, events, states,
    signatureVerifier, quits: () => quits,
  };
}

test('real NSIS updater checks metadata, verifies downloaded bytes, then installs and restarts exactly once', async (t) => {
  const h = await harness(t);
  assert.equal(await h.controller.check(), true);
  assert.deepEqual(h.controller.state, { status: 'available', latest: FUTURE_VERSION });
  assert.deepEqual(h.transport.requests, ['/latest.yml']);
  assert.equal(h.launches.length, 0);
  assert.equal(h.quits(), 0);

  const applying = h.controller.apply();
  assert.equal(h.controller.apply(), applying);
  assert.equal(await applying, true);
  await tick();

  assert.deepEqual(h.transport.requests, ['/latest.yml', `/${INSTALLER}`]);
  assert.equal(h.errors.length, 0);
  assert.equal(h.launches.length, 1);
  assert.equal(path.basename(h.launches[0].file), INSTALLER);
  assert.deepEqual(h.launches[0].args, ['--updated', '/S', '--force-run']);
  assert.deepEqual(await fs.readFile(h.launches[0].file), h.installer);
  assert.equal(h.updater.downloadedUpdateHelper.downloadedFileInfo.sha512, h.expectedHash);
  assert.equal(h.updater.verifyUpdateCodeSignature, h.signatureVerifier);
  assert.deepEqual(h.events, ['verified-download', 'installer-launch', 'before-quit-for-update', 'quit']);
  assert.equal(h.quits(), 1);
  assert.deepEqual(h.controller.state, { status: 'installing', latest: FUTURE_VERSION });
  assert.ok(h.states.some((state) => state.status === 'downloading' && state.percent === 100));
  assert.ok(h.states.some((state) => state.status === 'downloaded'));
  assert.equal(await h.controller.apply(), false);
  await tick();
  assert.equal(h.launches.length, 1);
  assert.equal(h.quits(), 1);
});

test('real NSIS download rejects tampered bytes before verified event, installation, or quit', async (t) => {
  const h = await harness(t, { tampered: true });
  assert.equal(await h.controller.check(), true);
  assert.equal(await h.controller.apply(), false);
  await tick();

  assert.deepEqual(h.transport.requests, ['/latest.yml', `/${INSTALLER}`]);
  assert.ok(h.errors.some((error) => error.code === 'ERR_CHECKSUM_MISMATCH'));
  assert.deepEqual(h.controller.state, {
    status: 'failed', operation: 'download', latest: FUTURE_VERSION,
    error: 'The update failed its integrity check. Please try again.',
  });
  assert.equal(h.updater.verifyUpdateCodeSignature, h.signatureVerifier);
  assert.equal(h.updater.downloadedUpdateHelper.file, null);
  assert.equal(h.events.includes('verified-download'), false);
  assert.equal(h.launches.length, 0);
  assert.equal(h.quits(), 0);
});
