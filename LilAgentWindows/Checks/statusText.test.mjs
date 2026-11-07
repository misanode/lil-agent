import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import { STATES } from '../src/character/states.js';
import { StatusText } from '../src/effects/statusText.js';
import { STATUS_PHRASES, statusTextExtent, statusTextLayout } from '../src/effects/statusTextLayout.js';

test('every mood, reaction, and interaction has a phrase', () => {
  assert.deepEqual(Object.keys(STATUS_PHRASES).sort(), Object.keys(STATES).sort());
  assert.equal(STATUS_PHRASES.done, STATUS_PHRASES.donehold);
});

test('text follows facing, stays outside the mascot, and fits at screen edges', () => {
  for (const halfWidth of [1.6, 4, 7.2, 19.2]) {
    for (const extent of [0.2, 0.6, 1.2]) {
      for (const x of [0, -halfWidth + extent + 0.08, halfWidth - extent - 0.08]) {
        for (const side of [-1, 1]) {
          for (const y of [-20, 0, 20]) {
            const result = statusTextLayout({ x, y, extent, width: 2.6, height: 0.9, halfWidth, halfHeight: 2, side });
            if (result.scale <= 0) continue;
            const w = 2.6 * result.scale, h = 0.9 * result.scale;
            assert.ok(result.x - w / 2 >= -halfWidth + 0.08 - 1e-8);
            assert.ok(result.x + w / 2 <= halfWidth - 0.08 + 1e-8);
            assert.ok(result.y - h / 2 >= -2 + 0.08 - 1e-8);
            assert.ok(result.y + h / 2 <= 2 - 0.08 + 1e-8);
            assert.ok(Math.abs(result.x - x) - w / 2 >= extent + 0.12 - 1e-8);
            if (x === 0) assert.equal(result.side, side);
          }
        }
      }
    }
  }
  for (const facing of [-1, 0, 1]) {
    const extent = statusTextExtent(5, facing, 1.68, 0.6, 0.4, 10);
    const c = Math.cos(facing), s = Math.sin(facing);
    for (const x of [-0.6, 0.6]) for (const z of [-0.4, 0.4]) {
      const projected = (5 + (c * x + s * z) * 1.68) * 10 / (10 - (-s * x + c * z) * 1.68);
      assert.ok(Math.abs(projected - 5) <= extent + 1e-8);
    }
  }
});

test('text lasts through the animation, refreshes on state changes, and respects the toggle', () => {
  let draws = 0;
  const context = { measureText: text => ({ width: text.length * 20 }), strokeText() { draws++; }, fillText() {} };
  globalThis.document = { createElement: () => ({ getContext: () => context }) };
  globalThis.window = { devicePixelRatio: 2 };
  const scene = new THREE.Scene(), text = new StatusText(scene);
  const pet = {
    settings: { showStatusText: true }, stateName: 'dance',
    placement: { scale: 1.68, halfWidth: 7.2, halfHeight: 3 },
    loco: { x: 0, facing: 0.4 }, letters: { cameraDistance: 10 },
    mob: { root: new THREE.Object3D(), height: 1.1, edgeHalfWidth: 0.6, edgeHalfDepth: 0.4, hasScreenFace: true },
  };
  text.update(0.2, pet);
  assert.equal(text.text, 'This is my song!');
  const firstDraws = draws, firstTexture = text.material.map;
  for (let i = 0; i < 600; i++) text.update(1 / 60, pet);
  assert.equal(text.mesh.visible, true);
  assert.equal(text.material.opacity, 1);
  assert.equal(draws, firstDraws);
  assert.equal(text.material.map, firstTexture);
  assert.ok(text.mesh.position.x > 0);
  pet.loco.facing = -0.4;
  text.update(1 / 60, pet);
  assert.ok(text.mesh.position.x < 0);
  pet.stateName = 'dizzy';
  text.update(1 / 60, pet);
  assert.equal(text.text, 'Everything’s spinning…');
  pet.settings.showStatusText = false;
  text.update(1 / 60, pet);
  assert.equal(text.mesh.visible, false);
  pet.stateName = 'idle';
  pet.settings.showStatusText = true;
  text.update(0.2, pet);
  assert.equal(text.mesh.visible, true);
  assert.equal(text.text, 'Just hanging out.');
  pet.mob.hasScreenFace = false;
  const codexTexture = text.material.map;
  text.update(0.2, pet);
  assert.notEqual(text.material.map, codexTexture);
});
