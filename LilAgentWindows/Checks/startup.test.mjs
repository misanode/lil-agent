import assert from 'node:assert/strict';
import test from 'node:test';
import { createStartup, splashBounds, SPLASH } from '../electron/startup.js';

function harness(options = {}) {
  const log = [];
  const startup = createStartup({ ...options, onFinish: () => log.push('finish'), onFail: (m) => log.push(`fail:${m}`) });
  return { startup, log };
}

test('waits for the entrance when the app is ready first', () => {
  const { startup, log } = harness();
  startup.appReady();
  assert.deepEqual(log, []);
  assert.equal(startup.phase, 'starting');
  startup.entranceDone();
  assert.deepEqual(log, ['finish']);
  assert.equal(startup.phase, 'finished');
});

test('waits for readiness when the entrance finishes first', () => {
  const { startup, log } = harness();
  startup.entranceDone();
  assert.deepEqual(log, []);
  startup.appReady();
  assert.deepEqual(log, ['finish']);
});

test('finishes only once', () => {
  const { startup, log } = harness({ entered: true });
  startup.appReady();
  startup.appReady();
  startup.entranceDone();
  assert.deepEqual(log, ['finish']);
});

test('a failure stops startup and ignores later readiness', () => {
  const { startup, log } = harness();
  startup.entranceDone();
  startup.fail('model missing');
  startup.fail('again');
  startup.appReady();
  assert.deepEqual(log, ['fail:model missing']);
  assert.equal(startup.phase, 'failed');
});

test('failures after a finished startup are ignored', () => {
  const { startup, log } = harness({ entered: true });
  startup.appReady();
  startup.fail('late');
  assert.deepEqual(log, ['finish']);
});

test('quitting during startup cancels it', () => {
  const { startup, log } = harness();
  startup.cancel();
  startup.entranceDone();
  startup.appReady();
  startup.fail('after quit');
  assert.deepEqual(log, []);
  assert.equal(startup.phase, 'cancelled');
});

test('the splash keeps its proportions, centres, and fits small work areas', () => {
  const extra = SPLASH.gap + SPLASH.spinner + SPLASH.edge;
  const big = splashBounds({ x: 0, y: 25, width: 1512, height: 920 });
  assert.equal(big.width, SPLASH.cardWidth);
  assert.equal(big.height, Math.round(SPLASH.cardWidth * SPLASH.aspect) + extra);
  assert.equal(big.x, Math.round((1512 - big.width) / 2));
  assert.equal(big.y, Math.round(25 + (920 - big.height) / 2));
  const small = splashBounds({ x: 100, y: 0, width: 300, height: 240 });
  assert.ok(small.width <= 240 && small.height <= 240 * 0.8 + 1);
});
