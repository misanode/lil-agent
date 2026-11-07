import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import { createPanelPresentation } from '../electron/panelPresentation.js';

function harness() {
  const calls = [];
  let state = 'initial';
  const window = new EventEmitter();
  window.destroyed = false;
  window.visible = false;
  window.isDestroyed = () => window.destroyed;
  window.show = () => { window.visible = true; calls.push('show'); };
  window.focus = () => calls.push('window-focus');
  window.webContents = { focus: () => calls.push('page-focus') };
  window.close = () => { window.destroyed = true; window.emit('closed'); };
  const presentation = createPanelPresentation({
    window,
    prepare: (target, anchor) => {
      assert.equal(target, window);
      calls.push({ prepare: anchor, state });
    },
    activate: () => calls.push('activate'),
    afterShow: () => calls.push('after-show'),
  });
  return { window, presentation, calls, state: (next) => { state = next; } };
}

for (const first of ['paint', 'render']) {
  test(`first open waits for both readiness signals when ${first} is first`, async () => {
    const h = harness();
    const anchor = { x: 20, y: 40 };
    const result = h.presentation.show(anchor);
    assert.equal(h.window.visible, false);
    if (first === 'paint') h.window.emit('ready-to-show');
    else h.presentation.rendered();
    assert.deepEqual(h.calls, []);
    if (first === 'paint') h.presentation.rendered();
    else h.window.emit('ready-to-show');
    assert.equal(await result, true);
    assert.deepEqual(h.calls, [
      { prepare: anchor, state: 'initial' },
      'show', 'activate', 'window-focus', 'page-focus', 'after-show',
    ]);
    h.presentation.rendered();
    h.window.emit('ready-to-show');
    assert.equal(h.calls.filter((call) => call === 'show').length, 1);
  });
}

test('repeated opening requests share one reveal with the latest anchor and state', async () => {
  const h = harness();
  const first = h.presentation.show({ x: 10 });
  const latestAnchor = { x: 90 };
  const second = h.presentation.show(latestAnchor);
  assert.equal(second, first);
  h.state('latest');
  h.presentation.rendered();
  h.window.emit('ready-to-show');
  assert.equal(await first, true);
  assert.equal(await second, true);
  assert.deepEqual(h.calls[0], { prepare: latestAnchor, state: 'latest' });
  assert.equal(h.calls.filter((call) => call === 'show').length, 1);
});

test('closing before readiness settles requests and discards late notifications', async () => {
  const h = harness();
  const result = h.presentation.show(null);
  assert.equal(h.window.listenerCount('ready-to-show'), 1);
  h.window.close();
  assert.equal(await result, false);
  assert.equal(h.window.listenerCount('ready-to-show'), 0);
  h.presentation.rendered();
  h.window.emit('ready-to-show');
  assert.equal(await h.presentation.show({ x: 10 }), false);
  assert.deepEqual(h.calls, []);
});

test('a hidden ready panel reopens immediately with fresh state and both focus targets', async () => {
  const h = harness();
  h.window.emit('ready-to-show');
  h.presentation.rendered();
  assert.deepEqual(h.calls, []);
  assert.equal(await h.presentation.show(null), true);
  h.window.visible = false;
  h.calls.length = 0;
  h.state('updated while hidden');
  const anchor = { x: 75, y: 120 };
  const result = h.presentation.show(anchor);
  assert.equal(h.window.visible, true);
  assert.deepEqual(h.calls, [
    { prepare: anchor, state: 'updated while hidden' },
    'show', 'activate', 'window-focus', 'page-focus', 'after-show',
  ]);
  assert.equal(await result, true);
});

test('the actual panel renders delayed state and completes both frames before its first reveal', async () => {
  class Element {
    constructor(tag) {
      this.tag = tag;
      this.children = [];
      this.style = {};
      this.className = '';
      this.scrollTop = 0;
    }
    addEventListener() {}
    setAttribute() {}
    append(...children) { this.children.push(...children); }
    replaceChildren(...children) { this.children = children; }
    querySelector(selector) {
      for (const child of this.children) {
        if (child.className.split(' ').includes(selector.slice(1))) return child;
        const nested = child.querySelector(selector);
        if (nested) return nested;
      }
      return null;
    }
  }
  const h = harness();
  const root = new Element('root');
  const frames = [];
  let resolveState;
  let readyCalls = 0;
  const source = readFileSync(new URL('../src/settings/panel.js', import.meta.url), 'utf8')
    .replace('import.meta.glob', 'iconGlob');
  const api = {
    get: () => new Promise((resolve) => { resolveState = resolve; }),
    onState() {},
    onTab() {},
    ready() { readyCalls++; h.presentation.rendered(); },
  };
  const document = {
    getElementById: () => root,
    createElement: (tag) => new Element(tag),
    createTextNode: (text) => Object.assign(new Element('#text'), { text }),
    addEventListener() {},
  };
  const result = h.presentation.show(null);
  h.window.emit('ready-to-show');
  vm.runInNewContext(source, {
    window: { panel: api }, document, Node: Element, iconGlob: () => ({}),
    requestAnimationFrame: (callback) => frames.push(callback),
  });
  assert.equal(root.children.length, 0);
  assert.equal(frames.length, 0);
  assert.equal(h.window.visible, false);
  resolveState({
    appName: 'Lil Agent', version: '1.0.0', update: { status: 'idle' },
    values: { keepOnTop: true, showStatusText: true, openAtLogin: false },
  });
  await new Promise(setImmediate);
  assert.equal(root.children.length, 3);
  assert.equal(root.children[1].tag, 'nav');
  assert.equal(root.children[1].children.length, 5);
  assert.ok(root.querySelector('.page'));
  assert.equal(readyCalls, 0);
  assert.equal(h.window.visible, false);
  assert.equal(frames.length, 1);
  frames.shift()(0);
  assert.equal(readyCalls, 0);
  assert.equal(h.window.visible, false);
  assert.equal(frames.length, 1);
  frames.shift()(16);
  assert.equal(readyCalls, 1);
  assert.equal(await result, true);
  assert.equal(h.window.visible, true);
  assert.equal(h.calls.filter((call) => call === 'show').length, 1);
});
