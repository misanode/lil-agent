import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { Mascot } from '../src/model/mascot.js';
import { Pose } from '../src/character/pose.js';
import { STATES } from '../src/character/states.js';
import { statusTextExtent, statusTextLayout, avoidStatusProps } from '../src/effects/statusTextLayout.js';

globalThis.ProgressEvent ??= class {
  constructor(type, properties = {}) { this.type = type; Object.assign(this, properties); }
};

async function load(name) {
  const bytes = await fs.readFile(new URL(`../public/models/${name}.glb`, import.meta.url));
  return new GLTFLoader().parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '');
}

for (const character of ['codex', 'clawd']) {
  test(`${character}: authored poses survive procedural layers, held keys, and loop boundaries`, async () => {
    for (const state of ['idle', 'drop', 'dizzy', 'carried', 'typing', 'wake', 'coffee', 'sleep']) {
      const gltf = await load(character);
      const reference = gltf.scene.clone(true);
      const mixer = new THREE.AnimationMixer(reference);
      const clip = gltf.animations.find((clip) => clip.name === state);
      const action = mixer.clipAction(clip);
      if (['drop', 'wake'].includes(state)) {
        action.setLoop(THREE.LoopOnce, 1);
        action.clampWhenFinished = true;
      }
      if (character === 'codex' && state === 'wake') action.timeScale = 0.5;
      action.play();
      const mob = new Mascot(gltf, character === 'codex' ? await load('bed') : null);
      mob.stateName = state;
      const pairs = mob.animatedPose.map(({ node }) => [node, reference.getObjectByName(node.name)]);
      const capture = mob.captureAnimatedPose.bind(mob);
      let frame = 0;
      mob.captureAnimatedPose = () => {
        capture();
        if (frame === 0 && state === 'sleep' && character === 'codex') return;
        for (const [actual, expected] of pairs) {
          for (const property of ['position', 'quaternion', 'scale']) {
            const values = actual[property].toArray(), wanted = expected[property].toArray();
            const error = Math.max(...values.map((value, i) => Math.abs(value - wanted[i])));
            assert.ok(error < 1e-5, `${character}/${state}/${actual.name}.${property}, frame ${frame}: ${error}`);
          }
        }
      };
      for (; frame < 420; frame++) {
        const dt = [1 / 60, 1 / 120, 1 / 30, 1 / 60][frame % 4];
        mixer.update(dt);
        mob.gazeYaw = Math.sin(frame / 15) * 0.3;
        mob.face.look = [0.3, -0.2];
        mob.animate(dt);
      }
      if (state === 'drop') {
        assert.equal(mob.actions.get('drop').paused, true);
        assert.equal(mob.actions.get('drop').time, clip.duration);
      }
      mob.dispose();
    }
  });
}

function dropContext() {
  return {
    placement: { scale: 1, halfHeight: 10, floorY: -10, minX: -100, maxX: 100 },
    lift: 8, restLift: 8,
    loco: { x: 0, targetX: 0, stop() {} },
    face: { setExpression() {} }, settings: {}, target: new Pose(), overlay: new Pose(),
  };
}

test('captions clear the actual animated side props at small, medium, and large pet sizes', async () => {
  for (const character of ['codex', 'clawd']) {
    const mob = new Mascot(await load(character));
    for (const state of ['permission', 'error', 'command', 'question', 'thinking', 'planning', 'searching']) {
      mob.stateName = state;
      for (let frame = 0; frame < 90; frame++) mob.animate(1 / 60);
      for (const scale of [0.64, 1.68, 3.2]) for (const side of [-1, 1]) {
        mob.root.scale.setScalar(scale);
        mob.facing = side * 0.6;
        mob.root.rotation.y = mob.facing;
        mob.root.position.set(0, -4.1, 0);
        mob.animate(1 / 60);
        const obstacles = mob.sidePropBounds(18);
        assert.ok(obstacles.length > 0);
        const extent = statusTextExtent(0, mob.facing, scale, mob.edgeHalfWidth, mob.edgeHalfDepth, 18);
        const heightFactor = ['permission', 'error'].includes(state) ? 0.2 : state === 'command' ? 0.4 : 0.5;
        const dimensions = { width: 2, height: scale < 1 ? 0.5 : 0.85, halfWidth: 7.2, halfHeight: 4.5 };
        const base = statusTextLayout({ ...dimensions, x: 0, y: -4.1 + mob.height * scale * heightFactor, extent, side });
        const attachBelow = ['command', 'permission', 'error'].includes(state);
        const result = avoidStatusProps(base, { ...dimensions, obstacles, attachBelow });
        assert.ok(result.scale > 0, `${character}/${state}/${scale}: caption disappeared`);
        const w = dimensions.width * result.scale, h = dimensions.height * result.scale;
        if (attachBelow && result.scale === base.scale && result.x === base.x) {
          const below = obstacles.filter(b => result.x + w / 2 + 0.025 > b.minX && result.x - w / 2 - 0.025 < b.maxX);
          if (below.length) assert.ok(Math.abs(Math.min(...below.map(b => b.minY)) - (result.y + h / 2) - 0.025) < 1e-5, `${character}/${state}: caption too far below prop`);
        }
        assert.ok(Math.abs(result.x) + w / 2 <= 7.12 + 1e-6);
        assert.ok(Math.abs(result.y) + h / 2 <= 4.42 + 1e-6);
        for (const b of obstacles) {
          const overlaps = result.x + w / 2 > b.minX && result.x - w / 2 < b.maxX && result.y + h / 2 > b.minY && result.y - h / 2 < b.maxY;
          assert.ok(!overlaps, `${character}/${state}/${scale}: caption overlaps prop`);
        }
      }
    }
    mob.dispose();
  }
});

test('side props follow facing without mirroring their artwork or separating their parts', async () => {
  const states = ['command', 'error', 'permission', 'planning', 'question', 'thinking', 'searching'];
  for (const character of ['codex', 'clawd']) {
    const mob = new Mascot(await load(character));
    const poses = new Map(mob.animatedPose.map((pose) => [pose.node, pose]));
    for (const state of states) {
      mob.stateName = state;
      const group = mob.sideProps.find(({ anchor }) => anchor.name.startsWith(`prop_${state}_`));
      assert.ok(group, `${character}/${state} missing prop`);
      for (const facing of [0.6, -0.6, -0.02, 0.6]) {
        mob.facing = facing;
        mob.root.rotation.y = facing;
        const expectedSide = facing === -0.02 ? -1 : Math.sign(facing);
        for (let frame = 0; frame < 120; frame++) {
          mob.animate(1 / 60);
          assert.equal(mob.facingSide, expectedSide);
          assert.equal(Math.sign(group.anchor.position.x), expectedSide);
          const referenceX = poses.get(group.anchor).position.x;
          const distance = Math.abs(referenceX - (character === 'codex' && state === 'permission' ? 0.8 * mob.clipWeight('permission') : 0)) - (character === 'codex' && state === 'thinking' ? 0.45 : 0);
          assert.ok(Math.abs(Math.abs(group.anchor.position.x) - distance) < 1e-5, `${character}/${state} drifted`);
          for (const node of group.nodes) {
            const original = poses.get(node);
            assert.ok(node.quaternion.equals(original.quaternion), `${character}/${state} rotated artwork`);
            const scale = original.scale.clone();
            if (state === 'thinking' && node === group.anchor) scale.x *= expectedSide;
            assert.ok(node.scale.equals(scale), `${character}/${state} wrong artwork or tail direction`);
            if (state === 'thinking' && character === 'codex') assert.ok(Math.abs(node.position.y - original.position.y + 0.55) < 1e-5, 'Thought bubble should sit lower with its dots');
            if (state !== 'permission') assert.ok(Math.abs((node.position.x - group.anchor.position.x) - (original.position.x - referenceX)) < 1e-5, `${character}/${state} separated parts`);
          }
        }
      }
    }
    mob.dispose();
  }
});

test('procedural poses stay out of clip blending across throw, idle, and sleep transitions', async () => {
  for (const character of ['codex', 'clawd']) {
    const mob = new Mascot(await load(character), character === 'codex' ? await load('bed') : null);
    const reference = new Mascot(await load(character));
    const capture = mob.captureAnimatedPose.bind(mob);
    mob.captureAnimatedPose = () => {
      capture();
      for (let i = 0; i < mob.animatedPose.length; i++) {
        const actual = mob.animatedPose[i].node, expected = reference.animatedPose[i].node;
        for (const property of ['position', 'quaternion', 'scale']) {
          const values = actual[property].toArray(), wanted = expected[property].toArray();
          assert.ok(values.every((value, j) => Math.abs(value - wanted[j]) < 1e-5), `${character}/${mob.stateName}/${actual.name}.${property}`);
        }
      }
    };
    for (const state of ['carried', 'drop', 'dizzy', 'idle', 'coffee', 'sleep', 'wake', 'idle']) {
      mob.stateName = reference.stateName = state;
      for (let frame = 0; frame < 180; frame++) {
        const dt = 1 / 60;
        reference.clock += dt;
        reference.updateClips(dt);
        mob.gazeYaw = Math.sin(frame / 15) * 0.3;
        mob.face.look = [0.4, -0.3];
        mob.animate(dt);
      }
    }
    mob.dispose();
    reference.dispose();
  }
});

test('throw wobble fades out continuously at recovery', () => {
  const sample = (offset) => {
    const context = dropContext(), state = new STATES.drop();
    state.enter(context, { vx: 8, vy: 3 });
    state.update(context, 0, state.daze + offset, {});
    return [context.overlay.torsoRoll, context.overlay.torsoPitch];
  };
  const before = sample(-1e-6), after = sample(1e-6);
  assert.ok(Math.hypot(...before.map((value, i) => value - after[i])) < 1e-4);
});

test('landing head shake fades in and ends before the dizzy transition', () => {
  const context = dropContext(), state = new STATES.drop();
  state.enter(context, { vx: 8, vy: -8 });
  state.landed = 1;
  state.impact = 1;
  for (const t of [0.5 - 1e-6, 0.5 + 1e-6, 1.4 - 1e-6, 1.4]) {
    context.target.reset(); context.overlay.reset();
    state.update(context, 0, 1 + t, {});
    assert.ok(Math.abs(context.overlay.headRoll) < 1e-4, `shake should ease to zero at ${t}`);
  }
});
