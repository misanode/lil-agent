import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { TypedLetters, PALETTES } from '../src/effects/typedLetters.js';

globalThis.document = {
  createElement: () => ({
    getContext: () => ({
      measureText: (text) => ({ width: text.length * 16 }),
      strokeText() {}, fillText() {},
    }),
  }),
};
globalThis.window = { devicePixelRatio: 1 };

function createLetters() {
  const letters = new TypedLetters(new THREE.Scene());
  letters.setResolution(1);
  return letters;
}

function update(letters, dt, scale = 1) {
  letters.update(dt, { origin: [0, 0, 0], scale, lineY: 1, clipCenter: 0, clipHalf: 2, clipDepth: 0 });
}

function disposals(texture) {
  let count = 0;
  texture.addEventListener('dispose', () => { count += 1; });
  return () => count;
}

test('unused glyphs are disposed when palette or resolution invalidates the cache', () => {
  const letters = createLetters();
  const first = letters.glyph('a');
  const firstDisposals = disposals(first.texture);
  letters.palette = PALETTES.codex;
  assert.equal(firstDisposals(), 1);
  const second = letters.glyph('a');
  const secondDisposals = disposals(second.texture);
  assert.notEqual(second.texture, first.texture);
  letters.setResolution(2);
  assert.equal(secondDisposals(), 1);
  letters.setResolution(2);
  letters.palette = PALETTES.clawd;
  assert.equal(firstDisposals(), 1);
  assert.equal(secondDisposals(), 1);
});

test('shared evicted textures survive sent and backspaced meshes until the final animation ends', () => {
  const letters = createLetters();
  letters.input('a');
  letters.input('a');
  const first = letters.line[0].node, second = letters.line[1].node;
  const texture = first.material.map;
  const textureDisposals = disposals(texture);
  const firstDisposals = disposals(first.material), secondDisposals = disposals(second.material);
  assert.equal(second.material.map, texture);
  letters.input('\b');
  letters.send();
  const before = [first, second].map((mesh) => [mesh.position.toArray(), mesh.scale.toArray(), mesh.material.opacity]);
  letters.palette = PALETTES.codex;
  letters.setResolution(2);
  assert.deepEqual([first, second].map((mesh) => [mesh.position.toArray(), mesh.scale.toArray(), mesh.material.opacity]), before);
  assert.equal(letters.sent[0].t, 0);
  assert.equal(letters.removed[0].t, 0);
  assert.equal(textureDisposals(), 0);
  update(letters, 0.1, 2);
  assert.equal(textureDisposals(), 0);
  assert.equal(first.material.map, texture);
  assert.equal(second.material.map, texture);
  update(letters, 0.1, 2);
  assert.equal(secondDisposals(), 1);
  assert.equal(firstDisposals(), 0);
  assert.equal(textureDisposals(), 0);
  update(letters, 0.71, 2);
  assert.equal(firstDisposals(), 1);
  assert.equal(textureDisposals(), 1);
  assert.equal(letters.sent.length, 0);
  assert.equal(letters.removed.length, 0);
});

test('an evicted live line retains its texture through the original idle pause and send duration', () => {
  const letters = createLetters();
  letters.input('a');
  const texture = letters.line[0].node.material.map;
  const count = disposals(texture);
  letters.palette = PALETTES.codex;
  update(letters, 1.49);
  assert.equal(letters.line.length, 1);
  assert.equal(count(), 0);
  update(letters, 0.02);
  assert.equal(letters.line.length, 0);
  assert.equal(letters.sent[0].nodes[0].material.map, texture);
  assert.equal(count(), 0);
  update(letters, 0.87);
  assert.equal(count(), 0);
  update(letters, 0.02);
  assert.equal(count(), 1);
});

test('cached textures remain reusable after their last mesh is released', () => {
  const letters = createLetters();
  letters.input('a');
  const texture = letters.line[0].node.material.map;
  const count = disposals(texture);
  letters.send();
  update(letters, 1);
  assert.equal(count(), 0);
  letters.input('a');
  assert.equal(letters.line[0].node.material.map, texture);
  letters.palette = PALETTES.codex;
  assert.equal(count(), 0);
  letters.send();
  update(letters, 1);
  assert.equal(count(), 1);
});

test('repeated palette and size changes release every retired warmed texture', () => {
  const letters = createLetters();
  const retired = [];
  for (let i = 0; i < 100; i++) {
    update(letters, 1 / 60, i % 2 ? 2 : 1);
    for (const glyph of letters.glyphs.values()) retired.push(disposals(glyph.texture));
    letters.palette = i % 2 ? PALETTES.clawd : PALETTES.codex;
    assert.equal(letters.group.children.length, 0);
  }
  assert.equal(retired.length, 300);
  assert.ok(retired.every((count) => count() === 1));
});
