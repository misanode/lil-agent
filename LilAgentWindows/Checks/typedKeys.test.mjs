import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';

globalThis.document = {
  baseURI: 'file:///app/index.html',
  createElement: () => ({ getContext: () => ({}) }),
};
globalThis.Image = class { set src(_) {} };

const { TypedKeys, parseHex, DEFAULT_KEY_COLOR } = await import('../src/effects/typedKeys.js');

const LIFE = 1.06;
const frame = (keys, dt, scale = 1, laptop = { lo: [-0.4, 0, 0], hi: [0.4, 0.5, 0.2] }) =>
  keys.update(dt, { laptop, fallback: [0, 1, 0], scale, bounds: { x: 8, y: 4 } });

function disposals(texture) {
  let count = 0;
  texture.addEventListener('dispose', () => { count += 1; });
  return () => count;
}

test('each printable key launches exactly one keycap; space, enter and backspace launch none', () => {
  const keys = new TypedKeys(new THREE.Scene());
  for (const ch of ['a', 'Z', '@', '7', 'é', ' ', '\r', '\u007f', '\t', '']) keys.input(ch);
  assert.equal(keys.caps.length, 5);
  assert.equal(keys.group.children.length, 5);
});

test('letters share one texture regardless of case, other characters get their own', () => {
  const keys = new TypedKeys(new THREE.Scene());
  ['a', 'A', '{', '1'].forEach((ch) => keys.input(ch));
  const maps = keys.caps.map((c) => c.mesh.material.map);
  assert.equal(maps[0], maps[1]);
  assert.notEqual(maps[1], maps[2]);
  assert.notEqual(maps[2], maps[3]);
});

test('keycaps fly out of the laptop, scale with the pet and are removed after their lifetime', () => {
  for (const scale of [1, 2]) {
    const keys = new TypedKeys(new THREE.Scene());
    keys.input('a');
    frame(keys, 0, scale);
    const mesh = keys.caps[0].mesh;
    const start = mesh.position.clone();
    assert.ok(Math.abs(start.x) <= 0.4 && start.y >= 0 && start.y <= 0.5, 'starts on the laptop');
    frame(keys, 0.5, scale);
    assert.ok(mesh.position.distanceTo(start) > 0.5 * scale, 'travels away from the laptop');
    assert.ok(Math.abs(mesh.scale.x - 0.24 * scale) < 0.02 * scale, 'sized relative to the pet');
    frame(keys, LIFE, scale);
    assert.equal(keys.caps.length, 0);
    assert.equal(keys.group.children.length, 0);
  }
});

test('keys typed quickly appear one after another', () => {
  const keys = new TypedKeys(new THREE.Scene());
  keys.input('a');
  keys.input('b');
  frame(keys, 0.01);
  assert.equal(keys.caps[0].mesh.visible, true);
  assert.equal(keys.caps[1].mesh.visible, false);
  frame(keys, 0.05);
  assert.equal(keys.caps[1].mesh.visible, true);
});

test('the number of keycaps in the air is capped', () => {
  const keys = new TypedKeys(new THREE.Scene());
  for (let i = 0; i < 60; i++) keys.input('x');
  assert.equal(keys.caps.length, 24);
  assert.equal(keys.group.children.length, 24);
});

test('changing the accent keeps textures of keys in the air until they finish', () => {
  const keys = new TypedKeys(new THREE.Scene());
  keys.input('a');
  const old = keys.caps[0].mesh.material.map;
  const idle = keys.texture('b');
  const oldDisposals = disposals(old), idleDisposals = disposals(idle);
  keys.setAccent('#4062E0');
  assert.equal(idleDisposals(), 1);
  assert.equal(oldDisposals(), 0);
  keys.input('a');
  assert.notEqual(keys.caps[1].mesh.material.map, old);
  frame(keys, LIFE);
  assert.equal(oldDisposals(), 1);
  keys.setAccent('#4062E0');
  assert.equal(keys.textures.size, 1);
});

test('hex colours parse and bad values fall back to the default accent', () => {
  assert.deepEqual(parseHex('#7E6345'), [126, 99, 69]);
  assert.deepEqual(parseHex('4062e0'), [64, 98, 224]);
  assert.equal(parseHex('blue'), null);
  const keys = new TypedKeys(new THREE.Scene());
  keys.setAccent('nope');
  assert.deepEqual(keys.accent, parseHex(DEFAULT_KEY_COLOR));
});
