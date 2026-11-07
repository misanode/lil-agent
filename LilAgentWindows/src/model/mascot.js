import * as THREE from 'three';
import { clamp, clamp01, damp, easeOutBack, easeOutCubic, rnd, smooth } from '../core/util.js';
import { FaceDisplay } from '../character/face.js';
import { blanketShader, dentShader, reactive } from './bedding.js';

const FIT_HEIGHT = 1.0;
const FIT_WIDTH = 1.6;
const HOVER = 0.1;
const ONE_SHOT = new Set(['wake', 'surprised', 'settle', 'drop', 'done', 'idea']);
const FADE_RATE = 10;
const TURN_NAMES = ['head', 'neck', 'trunk', 'torso', 'chest', 'spine', 'body'];
const EYE_TRAVEL_FRACTION = 0.04;
const EYES_NAME = /^eyes?([_.\s-]?(l|r|left|right))?$/i;
const CLAWD_TEXT_WIDTH = 1.03, CODEX_TEXT_WIDTH = 1.6;
const SIDE_PROP_GROUPS = [
  ['prop_command_', 'prop_command_window'], ['prop_error_', 'prop_error_alert'],
  ['prop_permission_', 'prop_permission_lock'], ['prop_planning_', 'prop_planning_list'],
  ['prop_question_', 'prop_question_bubble'], ['prop_thinking_', 'prop_thinking_bubble'],
  ['prop_searching_', 'prop_searching_glass'],
];

const HOVER_Y = 0.93, PRESS_Y = 0.78, HOVER_TILT = 27, PRESS_TILT = 38, ARM_X = 1.17, ARM_Z = 0.8;
const TAP_DOWN = 0.05, TAP_UP = 0.14, KEY_HOLD = 1.2;
const MAX_HOLD = 10;
const LIFT_EXTRA = 0.35, STRIKE_EXTRA = 0.45;
const TAP_DIP = 0.03, TAP_ROLL = 0.032, NOD_PITCH = 0.025, CURSOR_KICK = 0.05;
const AUTO_QUIET = 2.0;
const LIE_DOWN_S = 1.3;
const WAKE_SPEED = 0.5;
const SHAKE_AT = 2.05, SHAKE_S = 0.85, SHAKE_YAW = 0.34;
const MUG_REACH = 0.75, SIP_TILT = 0.13, SIP_LEAN = 0.035;
const LYING_HIPS = new THREE.Vector3(0.35, 0.94, 0);
const INCLINE = 0.45;
const HEAD_REST = 0.72, BODY_REST = 0.56;
const Z_START = new THREE.Vector3(0, 1.92, 0), Z_FROM = new THREE.Vector3(-0.6, 2.75, 0.2);
const BREATH_HZ = 0.22, BREATH_DEPTH = 0.03, BREATH_NOD = 0.02;
const MATTRESS_TOP = 0.62;
const BED_IN = 0.45, BED_OUT = 0.35, BLANKET_UP = 0.55, BLANKET_OFF = 0.22;
const TEAR_SINK = 0.03;

const X = new THREE.Vector3(1, 0, 0), Y = new THREE.Vector3(0, 1, 0), Z = new THREE.Vector3(0, 0, 1);
const q = (axis, angle) => new THREE.Quaternion().setFromAxisAngle(axis, angle);
const slerp = (a, b, t) => a.clone().slerp(b, t);
const quatXYZ = (x, y, z) => new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, 'XYZ'));
const lower = (o) => (o.name ?? '').toLowerCase();
function angleAxis(qt) {
  const w = clamp(qt.w, -1, 1);
  const angle = 2 * Math.acos(w);
  const s = Math.sqrt(1 - w * w);
  return { angle, axis: s < 1e-6 ? new THREE.Vector3(1, 0, 0) : new THREE.Vector3(qt.x / s, qt.y / s, qt.z / s) };
}

function convert(p, from, to) {
  from.updateWorldMatrix(true, false);
  to.updateWorldMatrix(true, false);
  return to.worldToLocal(from.localToWorld(p.clone()));
}

function relative(from, to) {
  from.updateWorldMatrix(true, false);
  to.updateWorldMatrix(true, false);
  return new THREE.Matrix4().copy(to.matrixWorld).invert().multiply(from.matrixWorld);
}

function find(root, test) {
  let found = null;
  root.traverse((o) => { if (!found && test(o)) found = o; });
  return found;
}

export class Mascot {
  constructor(gltf, bedGltf = null) {
    this.root = new THREE.Group();
    this.root.name = 'mascot';
    this.hips = new THREE.Group();
    this.hips.position.y = HOVER;
    this.torso = new THREE.Group();
    this.root.add(this.hips);
    this.hips.add(this.torso);
    this.face = new FaceDisplay();

    this.height = 1.1; this.halfWidth = 0.6; this.halfDepth = 0.3; this.emoteLift = 1.1; this.bodyHalfWidth = 0.5; this.bodyFront = 0.3;
    this.actions = new Map();
    this.weights = {};
    this.mixer = null;
    this.idleClip = null; this.moveClip = null; this.playing = null;
    this.stateName = 'idle';
    this.eyes = [];
    this.faces = new Map();
    this.cursor = null;
    this.typingPoses = [];
    this.props = [];
    this.sideProps = [];
    this.facing = 0;
    this.facingSide = 1;
    this.screen = null;
    this.turn = null;
    this.gazeYaw = 0;
    this.arms = [];
    this.nextArm = 0;
    this.lastKey = null;
    this.clock = 0;
    this.keyDriven = 0;
    this.lastTap = -Infinity;
    this.bodyRig = null; this.headRig = null; this.cursorRest = null;
    this.dip = 0; this.rock = 0; this.nod = 0; this.tick = 0;
    this.autoNext = 0; this.autoWord = 0; this.autoDeletes = 0; this.lastRealKey = -Infinity;
    this.actingState = ''; this.actingStart = 0;
    this.slowBlend = null;
    this.mugArm = null; this.mugBase = null; this.mug = null;
    this.mugAmount = 1;
    this.cap = null;
    this.permissionLock = null;
    this.legs = []; this.armRest = []; this.bodyScale = new THREE.Vector3(1, 1, 1);
    this.sleepZs = [];
    this.bed = null; this.bedRest = null; this.bedBox = null; this.bedHalfDepth = 0; this.blanket = null; this.bedRoot = null;
    this.dentMaterials = []; this.blanketMaterials = [];
    this.rigHips = null;
    this.bedAmount = 0; this.blanketAmount = 0;
    this.tears = [];
    this.own = 0;
    this.bobPhase = rnd(0, 10);
    this.lean = 0; this.climb = 0; this.walkAmount = 0; this.walkPhase = 0;

    const scene = gltf.scene;
    scene.updateMatrixWorld(true);
    const box = Mascot.measure(scene);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const unit = Math.min(FIT_HEIGHT / Math.max(size.y, 1e-6), FIT_WIDTH / Math.max(Math.max(size.x, size.z), 1e-6));

    const model = new THREE.Group();
    model.name = 'model';
    model.scale.setScalar(unit);
    model.position.set(-center.x * unit, -box.min.y * unit, -center.z * unit);
    model.add(scene);
    this.torso.add(model);
    this.model = model;

    const h = size.y * unit;
    this.height = h + HOVER;
    this.halfWidth = Math.max(0.25, (Math.max(size.x, size.z) * unit) / 2);
    this.halfDepth = size.z * unit / 2;
    this.emoteLift = h + 0.1;
    this.bodyHalfWidth = this.halfWidth * 0.8;
    this.root.updateMatrixWorld(true);
    const bodyMesh = find(scene, (o) => lower(o) === 'body' && o.isMesh);
    if (bodyMesh) {
      bodyMesh.geometry.computeBoundingBox();
      const bb = bodyMesh.geometry.boundingBox.clone().applyMatrix4(relative(bodyMesh, this.root));
      this.bodyHalfWidth = (bb.max.x - bb.min.x) / 2;
      this.bodyFront = bb.max.z;
    }

    Mascot.matchNativeMaterials(scene);
    Mascot.restyleClay(scene);
    scene.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = false; } });
    this.findEyes(scene);
    scene.traverse((o) => {
      const name = lower(o);
      if (!name.startsWith('face_')) return;
      const f = name.slice(5);
      if (f === 'cursor') this.cursor = o; else this.faces.set(f, o);
    });
    this.findProps(scene);
    for (const [prefix, anchorName] of SIDE_PROP_GROUPS) {
      const anchor = this.props.find((node) => lower(node) === anchorName);
      if (anchor) this.sideProps.push({ anchor, nodes: this.props.filter((node) => lower(node).startsWith(prefix)) });
    }
    for (const prop of this.props) {
      const mesh = find(prop, (o) => o.isMesh && /display|screen/i.test(o.name));
      if (mesh && !this.screen) {
        mesh.geometry.computeBoundingBox();
        this.screen = { mesh, prop, box: mesh.geometry.boundingBox.clone() };
      }
    }
    this.eyeTravel = size.y * EYE_TRAVEL_FRACTION;

    for (const [name, side] of [['arm_l', -1], ['arm_r', 1]]) {
      const node = find(scene, (o) => !o.isMesh && lower(o) === name);
      if (node) this.arms.push({ node, side, tapStart: -Infinity, holding: null, released: -Infinity, depth: 1, press: 0 });
    }

    const clips = gltf.animations ?? [];
    const clipNamed = (n) => clips.find((c) => c.name.toLowerCase() === n);
    const sample = (clip, node, path, t) => {
      const track = clip.tracks.find((k) => k.name === `${node.name}.${path}`);
      if (!track) return null;
      return Array.from(track.createInterpolant().evaluate(t));
    };

    const typing = this.hasScreenFace ? clipNamed('typing') : null;
    if (typing) {
      const a = 1 / 24, b = 4 / 24;
      for (const arm of this.arms) {
        const pose = (t) => {
          const p = sample(typing, arm.node, 'position', t);
          const r = sample(typing, arm.node, 'quaternion', t);
          return [p ? new THREE.Vector3(...p) : arm.node.position.clone(), r ? new THREE.Quaternion(...r) : arm.node.quaternion.clone()];
        };
        const handY = ([p, r]) => p.y + new THREE.Vector3(0, -1, 0).applyQuaternion(r).y;
        const pa = pose(a), pb = pose(b);
        const [hover, press] = handY(pa) < handY(pb) ? [pb, pa] : [pa, pb];
        const delta = angleAxis(hover[1].clone().invert().multiply(press[1]));
        const turned = (k) => hover[1].clone().multiply(q(delta.axis, delta.angle * k));
        this.typingPoses.push({ hover: [hover[0], turned(-LIFT_EXTRA)], press: [press[0], turned(1 + STRIKE_EXTRA)] });
      }
      if (this.typingPoses.length !== this.arms.length) this.typingPoses = [];
    }

    if (this.hasScreenFace) {
      scene.traverse((o) => {
        if (o.isMesh) return;
        const n = lower(o);
        if (n === 'body' && !this.bodyRig) {
          this.bodyRig = { node: o, pos: o.position.clone(), rot: o.quaternion.clone() };
          this.bodyScale = o.scale.clone();
        } else if (n === 'leg_l' || n === 'leg_r') this.legs.push({ node: o, rot: o.quaternion.clone() });
        else if (n === 'head' && !this.headRig) this.headRig = { node: o, rot: o.quaternion.clone() };
      });
      if (this.cursor) this.cursorRest = this.cursor.position.clone();
      this.armRest = this.arms.map((a) => a.node.quaternion.clone());
      if (bedGltf) this.setUpBed(bedGltf, model);
      const hipsNode = find(scene, (o) => !o.isMesh && lower(o) === 'hips');
      if (hipsNode) this.rigHips = { node: hipsNode, pos: hipsNode.position.clone(), rot: hipsNode.quaternion.clone() };
      for (const p of this.props) {
        const n = lower(p);
        if (n === 'prop_coffee_mug') this.mug = p;
        else if (n === 'prop_sleep_cap') this.cap = p;
        else if (n === 'prop_permission_lock') this.permissionLock = p;
        else if (n.startsWith('prop_sleep_z')) this.sleepZs.push(p);
      }
      const coffee = clipNamed('coffee');
      const i = this.arms.findIndex((a) => a.side > 0);
      if (coffee && i >= 0) {
        const r = sample(coffee, this.arms[i].node, 'quaternion', 1 / 24);
        if (r) {
          this.mugArm = i;
          this.mugBase = new THREE.Quaternion(...r);
        }
      }
    }

    for (const side of ['l', 'r']) {
      const stream = find(scene, (o) => lower(o) === `prop_sad_fountain${side}`);
      const puddle = find(scene, (o) => lower(o) === `prop_sad_puddle${side}`);
      const ripple = find(scene, (o) => lower(o) === `prop_sad_ripple${side}`);
      const tip = stream ? Mascot.lowestPoint(stream) : null;
      if (stream && tip) this.tears.push({ stream, tip, puddle, ripple });
    }

    for (const name of TURN_NAMES) {
      const node = find(scene, (o) => lower(o) === name);
      if (node && !node.isMesh) {
        this.turn = { node, rest: node.quaternion.clone() };
        break;
      }
    }

    this.animatedPose = [];
    scene.traverse((node) => {
      this.animatedPose.push({ node, position: node.position.clone(), quaternion: node.quaternion.clone(), scale: node.scale.clone() });
    });

    if (clips.length) {
      this.mixer = new THREE.AnimationMixer(scene);
      for (const clip of clips) {
        const key = clip.name.toLowerCase();
        if (this.actions.has(key)) continue;
        const action = this.mixer.clipAction(clip);
        if (ONE_SHOT.has(key)) {
          action.setLoop(THREE.LoopOnce, 1);
          action.clampWhenFinished = true;
        }
        action.weight = 0;
        this.actions.set(key, action);
      }
      if (this.hasScreenFace && this.actions.get('wake')) this.actions.get('wake').timeScale = WAKE_SPEED;
      const names = clips.map((c) => c.name.toLowerCase());
      this.idleClip = this.actions.has('idle') ? 'idle' : names.find((n) => /idle|stand|breath|rest/.test(n)) ?? names[0];
      this.moveClip = ['walk', 'run', 'fly', 'move', 'swim'].find((n) => this.actions.has(n))
        ?? names.find((n) => /walk|run|fly|move|swim|hop/.test(n)) ?? null;
    }
  }

  get hasScreenFace() { return this.faces.size > 0; }
  get head() { return this.torso; }
  get textHalfWidth() { return Math.min(this.halfWidth, this.bodyHalfWidth * (this.hasScreenFace ? CODEX_TEXT_WIDTH : CLAWD_TEXT_WIDTH)) * 1.2; }
  get edgeHalfWidth() {
    return this.bed?.visible && this.bedBox
      ? Math.max(this.halfWidth, Math.abs(this.bedBox.minX), Math.abs(this.bedBox.maxX)) : this.halfWidth;
  }
  get edgeHalfDepth() { return this.bed?.visible ? Math.max(this.halfDepth, this.bedHalfDepth) : this.halfDepth; }

  get hitBox() {
    let box = { minX: -this.halfWidth, maxX: this.halfWidth, top: this.height };
    if (this.bed && this.bed.visible && this.bedAmount > 0.3 && this.bedBox) {
      const b = this.bedBox;
      box = { minX: Math.min(box.minX, b.minX), maxX: Math.max(box.maxX, b.maxX), top: Math.max(box.top, b.top) };
    }
    return box;
  }

  setUpBed(bedGltf, model) {
    const holder = new THREE.Group();
    holder.name = 'bed';
    holder.scale.copy(model.scale);
    holder.position.copy(model.position);
    const u = model.scale.x, ox = model.position.x;
    this.bedBox = { minX: ox - 3.45 * u, maxX: ox + 1.9 * u, top: 3.2 * u };
    const bedScene = bedGltf.scene;
    const bedBounds = Mascot.measure(bedScene);
    this.bedHalfDepth = Math.max(Math.abs(model.position.z + bedBounds.min.z * u), Math.abs(model.position.z + bedBounds.max.z * u));
    holder.add(bedScene);
    holder.visible = false;
    this.torso.add(holder);
    this.bed = holder;
    this.bedRest = holder.scale.clone();
    this.bedRoot = bedScene;
    this.blanket = bedScene.getObjectByName('bed_blanket') ?? null;
    bedScene.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    bedScene.updateMatrixWorld(true);
    const react = (name, shader, floorY, puff, list) => {
      const top = bedScene.getObjectByName(name);
      top?.traverse((n) => {
        if (!n.isMesh) return;
        const offs = convert(new THREE.Vector3(), n, bedScene);
        const mats = Array.isArray(n.material) ? n.material : [n.material];
        const copies = mats.map((m) => {
          const c = reactive(m, shader, { offs, floorY, puff });
          list.push(c);
          return c;
        });
        n.material = Array.isArray(n.material) ? copies : copies[0];
      });
    };
    react('bed_mattress', dentShader, 0.4, 0.02, this.dentMaterials);
    react('bed_pillow', dentShader, 0.6, 0.14, this.dentMaterials);
    react('bed_blanket', blanketShader, 0, 0, this.blanketMaterials);
  }

  static lowestPoint(node) {
    let best = null;
    node.updateMatrixWorld(true);
    node.traverse((n) => {
      if (!n.isMesh) return;
      const m = relative(n, node);
      const pos = n.geometry.attributes.position;
      const v = new THREE.Vector3();
      for (let i = 0; i < pos.count; i++) {
        v.fromBufferAttribute(pos, i).applyMatrix4(m);
        if (!best || v.y < best.y) best = v.clone();
      }
    });
    return best;
  }

  static matchNativeMaterials(root) {
    root.traverse((o) => {
      if (!o.isMesh) return;
      for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
        if (!m?.isMeshPhysicalMaterial) continue;
        m.sheen = 0;
        m.specularIntensity = 1;
        m.specularColor?.setRGB(1, 1, 1);
      }
    });
  }

  static restyleClay(root) {
    root.traverse((o) => {
      if (!o.isMesh) return;
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      const out = mats.map((m) => {
        if (m.name !== 'Clay') return m;
        const p = new THREE.MeshPhysicalMaterial();
        THREE.MeshStandardMaterial.prototype.copy.call(p, m);
        p.color.setRGB(0.73, 0.165, 0.055);
        p.roughness = 0.62;
        p.metalness = 0;
        p.clearcoat = 0.08;
        p.clearcoatRoughness = 0.25;
        return p;
      });
      o.material = Array.isArray(o.material) ? out : out[0];
    });
  }

  static measure(root) {
    const box = new THREE.Box3();
    const visit = (o) => {
      if (lower(o).startsWith('prop')) return;
      if (o.isMesh) {
        o.geometry.computeBoundingBox();
        box.union(o.geometry.boundingBox.clone().applyMatrix4(relative(o, root)));
      }
      o.children.forEach(visit);
    };
    visit(root);
    if (box.isEmpty()) return new THREE.Box3(new THREE.Vector3(), new THREE.Vector3(1, 1, 1));
    return box;
  }

  findEyes(node) {
    if (EYES_NAME.test(node.name ?? '')) {
      this.eyes.push({ node, rest: node.scale.clone(), restPos: node.position.clone() });
      return;
    }
    node.children.forEach((c) => this.findEyes(c));
  }

  findProps(node) {
    if (lower(node).startsWith('prop')) {
      this.props.push(node);
      return;
    }
    node.children.forEach((c) => this.findProps(c));
  }


  targetWeights() {
    if (!this.idleClip) return null;
    const state = this.actions.has(this.stateName) ? this.stateName : this.idleClip;
    const targets = { [state]: 1 };
    if (this.moveClip && this.moveClip !== state && (state === this.idleClip || this.stateName === 'walk')) {
      const w = clamp01(this.walkAmount);
      targets[state] = 1 - w;
      targets[this.moveClip] = w;
    }
    return { state, targets };
  }

  updateClips(dt) {
    const tw = this.targetWeights();
    if (!this.mixer || !tw) return;
    const { state, targets } = tw;
    if (state !== this.playing) {
      this.actions.get(state)?.reset().play();
      this.playing = state;
      this.slowBlend = this.hasScreenFace && state === 'sleep' ? { to: state, start: this.clock, from: { ...this.weights } } : null;
    }
    const k = 1 - Math.exp(-FADE_RATE * dt);
    let ease = null;
    const sb = this.slowBlend;
    if (sb) {
      if (sb.to !== state || this.clock - sb.start >= LIE_DOWN_S) this.slowBlend = null;
      else ease = smooth(0, 1, (this.clock - sb.start) / LIE_DOWN_S);
    }
    for (const [name, action] of this.actions) {
      const target = targets[name] ?? 0;
      const prev = this.weights[name] ?? 0;
      let w = prev + (target - prev) * k;
      if (ease != null && this.slowBlend) {
        w = (this.slowBlend.from[name] ?? 0) * (1 - ease) + (name === this.slowBlend.to ? ease : 0);
        if (name !== this.slowBlend.to) action.paused = true;
      }
      if (target === 0 && w < 0.01) {
        if (action.isScheduled()) action.stop();
        delete this.weights[name];
        continue;
      }
      if (!action.isRunning() && !ONE_SHOT.has(name) && !action.paused) action.play();
      if (!action.isScheduled()) action.play();
      this.weights[name] = w;
    }
    const total = Object.values(this.weights).reduce((s, v) => s + v, 0);
    for (const [name, action] of this.actions) action.weight = total > 0 ? (this.weights[name] ?? 0) / total : 0;
    this.mixer.update(dt);
    for (const node of this.props) node.visible = node.scale.x > 0.5;
  }

  clipWeight(name) {
    const a = this.actions.get(name);
    return a && a.isScheduled() ? a.weight : 0;
  }


  screenFaceName() {
    const expression = this.face.expression;
    let name = FACE_FOR_STATE[this.stateName]
      ?? (expression === 'neutral' && PROMPT_STATES.has(this.stateName) ? 'prompt' : FACE_FOR_EXPRESSION[expression])
      ?? 'eyes';
    if (!this.faces.has(name)) name = this.faces.has('eyes') ? 'eyes' : [...this.faces.keys()].sort()[0];
    return name;
  }

  updateEyes() {
    if (!this.eyes.length) return;
    const f = this.face;
    let blinkFactor = f.blinkFactor;
    let eyeOpen = (f.current.eyeOpen[0] + f.current.eyeOpen[1]) / 2;
    if (this.hasScreenFace) {
      const name = this.screenFaceName();
      if (!OPEN_FACES.has(name)) {
        blinkFactor = 1;
        eyeOpen = 1;
      }
      for (const [key, node] of this.faces) node.visible = key === name;
      if (name === 'prompt') {
        blinkFactor = 1;
        const lit = this.stateName === 'typing' || this.clock % 1.06 < 0.53;
        if (this.cursor) this.cursor.visible = lit;
      } else if (this.cursor) this.cursor.visible = false;
    }
    const open = clamp(eyeOpen * blinkFactor, 0.06, 1.4);
    const size = (f.current.eyeScale[0] + f.current.eyeScale[1]) / 2;
    const dx = f.look[0] * this.eyeTravel;
    const dy = f.look[1] * this.eyeTravel * 0.6;
    for (const e of this.eyes) {
      e.node.scale.set(e.rest.x, e.rest.y * size * open, e.rest.z);
      e.node.position.x += dx;
      e.node.position.y += dy;
    }
  }

  restoreAnimatedPose() {
    for (const pose of this.animatedPose) {
      pose.node.position.copy(pose.position);
      pose.node.quaternion.copy(pose.quaternion);
      pose.node.scale.copy(pose.scale);
    }
  }

  captureAnimatedPose() {
    for (const pose of this.animatedPose) {
      pose.position.copy(pose.node.position);
      pose.quaternion.copy(pose.node.quaternion);
      pose.scale.copy(pose.node.scale);
    }
  }


  applyPose(p, breath) {
    const sit = clamp01(p.sit);
    const free = 1 - this.own;
    const tilt = 1 - 0.75 * this.own;
    const bob = Math.sin(this.bobPhase) * 0.035 * (1 - sit);
    this.hips.position.y = (HOVER * (1 - sit) + p.bodyY + bob - p.crouch * 0.5) * free;

    const squash = 1 - p.crouch * 1.5 * free;
    const b = breath * free;
    this.torso.scale.set(1 / Math.sqrt(squash) + b * 0.004, squash + b * 0.01, 1 / Math.sqrt(squash));

    const wiggle = (p.armRaiseR - p.armRaiseL) * 0.12 + (p.armSwingR - p.armSwingL) * 0.05;
    const gaze = p.headYaw * 0.6;
    const routed = this.turn ? this.own : 0;
    this.gazeYaw = gaze * routed;
    this.torso.quaternion.copy(quatXYZ(
      ((p.torsoPitch * 0.5 + p.headPitch * 0.4) * (1 - 0.6 * sit) + this.lean * 0.6 - this.climb * 0.15) * tilt,
      p.torsoYaw + gaze * (1 - routed),
      (p.torsoRoll + p.headRoll * 0.7 + wiggle) * tilt,
    ));
  }

  pressKey(code = -1) {
    if (!this.arms.length) return;
    const repeatKey = code >= 0 && this.lastKey?.code === code;
    let i;
    const held = this.arms.findIndex((a) => a.holding === code && code >= 0);
    if (held >= 0) i = held;
    else if (repeatKey && this.lastKey) i = this.lastKey.arm;
    else i = this.nextArm;
    this.tap(i, code >= 0 ? code : null);
    if (!repeatKey) this.nextArm = (i + 1) % this.arms.length;
    this.lastKey = { code, arm: i };
    this.lastRealKey = this.clock;
  }

  tap(i, code) {
    const a = this.arms[i];
    a.tapStart = this.clock;
    a.holding = code;
    a.released = code != null ? Infinity : this.clock;
    a.depth = rnd(0.8, 1);
    this.lastTap = this.clock;
  }

  autoType() {
    if (!this.hasScreenFace || this.stateName !== 'typing' || !this.arms.length) {
      this.autoNext = this.clock + rnd(0.2, 0.45);
      return;
    }
    if (this.arms.some((a) => a.holding != null) || this.clock - this.lastRealKey < AUTO_QUIET) {
      this.autoNext = Math.max(this.autoNext, this.clock + rnd(0.3, 0.6));
      return;
    }
    if (this.clock < this.autoNext) return;
    if (this.autoDeletes > 0) {
      this.autoDeletes -= 1;
      this.tap(this.lastKey?.arm ?? 0, null);
      this.autoNext = this.clock + (this.autoDeletes > 0 ? rnd(0.1, 0.13) : rnd(0.25, 0.4));
      return;
    }
    const n = this.arms.length;
    const i = Math.random() < 0.72 ? this.nextArm : (this.nextArm + n - 1) % n;
    this.tap(i, null);
    this.nextArm = (i + 1) % n;
    this.lastKey = { code: -1, arm: i };
    if (this.autoWord > 0) {
      this.autoWord -= 1;
      this.autoNext = this.clock + rnd(0.07, 0.15);
      return;
    }
    this.autoWord = 2 + Math.floor(Math.random() * 6);
    const roll = Math.random();
    if (roll < 0.07) {
      this.autoDeletes = 2 + Math.floor(Math.random() * 3);
      this.autoNext = this.clock + rnd(0.3, 0.5);
    } else if (roll < 0.2) this.autoNext = this.clock + rnd(0.5, 1.0);
    else this.autoNext = this.clock + rnd(0.14, 0.26);
  }

  releaseKey(code) {
    for (const a of this.arms) {
      if (a.holding === code) {
        a.holding = null;
        a.released = this.clock;
      }
    }
    this.lastTap = this.clock;
  }

  applyKeyTaps(dt) {
    for (const a of this.arms) {
      if (a.holding != null && this.clock - a.tapStart > MAX_HOLD) {
        a.holding = null;
        a.released = this.clock;
      }
    }
    const holding = this.arms.some((a) => a.holding != null);
    const wanted = this.stateName === 'typing' && (holding || this.clock - this.lastTap < KEY_HOLD) ? 1 : 0;
    this.keyDriven += (wanted - this.keyDriven) * (1 - Math.exp(-14 * dt));
    if (this.keyDriven <= 0.001) return;
    const w = this.keyDriven;
    this.arms.forEach((arm, i) => {
      const t = this.clock - arm.tapStart;
      let press = 0;
      if (t >= 0) {
        const liftStart = Math.max(arm.released, arm.tapStart + TAP_DOWN);
        if (this.clock < arm.tapStart + TAP_DOWN) press = smooth(0, 1, t / TAP_DOWN);
        else if (this.clock < liftStart) press = 1;
        else press = 1 - smooth(0, 1, (this.clock - liftStart) / TAP_UP);
      }
      if (this.typingPoses.length) press *= arm.depth;
      arm.press = press;
      let keyPos, keyRot;
      if (i < this.typingPoses.length) {
        const { hover, press: down } = this.typingPoses[i];
        keyPos = hover[0].clone().lerp(down[0], press);
        keyRot = slerp(hover[1], down[1], press);
      } else {
        const y = HOVER_Y + (PRESS_Y - HOVER_Y) * press;
        const tilt = ((HOVER_TILT + (PRESS_TILT - HOVER_TILT) * press) * Math.PI) / 180;
        keyPos = new THREE.Vector3(arm.side * ARM_X, y, ARM_Z);
        keyRot = q(X, tilt);
      }
      arm.node.position.lerp(keyPos, w);
      arm.node.quaternion.slerp(keyRot, w);
    });
  }

  animate(dt) {
    this.clock += dt;
    this.bobPhase += dt * 3;
    this.own += ((this.actions.has(this.stateName) ? 1 : 0) - this.own) * (1 - Math.exp(-8 * dt));
    this.restoreAnimatedPose();
    this.updateClips(dt);
    this.captureAnimatedPose();
    this.autoType();
    this.applyKeyTaps(dt);
    if (this.turn) this.turn.node.quaternion.multiply(q(Y, this.gazeYaw));
    this.reactToKeys(dt);
    if (this.hasScreenFace) this.act(dt);
    this.placeSideProps();
    this.pourTears();
    this.updateEyes();
  }

  placeSideProps() {
    if (Math.abs(this.facing) > 0.12) this.facingSide = Math.sign(this.facing);
    for (const { anchor, nodes } of this.sideProps) {
      const thought = lower(anchor) === 'prop_thinking_bubble';
      const inset = thought && this.hasScreenFace ? 0.45 : 0;
      const lowerBy = thought && this.hasScreenFace ? 0.55 : 0;
      const offset = this.facingSide * Math.max(0, Math.abs(anchor.position.x) - inset) - anchor.position.x;
      for (const node of nodes) {
        node.position.x += offset;
        node.position.y -= lowerBy;
      }
      if (thought) anchor.scale.x *= this.facingSide;
    }
  }

  sidePropBounds(cameraDistance) {
    this.root.updateWorldMatrix(true, true);
    const bounds = [];
    const point = new THREE.Vector3();
    for (const { nodes } of this.sideProps) {
      const box = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity };
      const visit = (node) => {
        if (!node.visible) return;
        if (node.isMesh) {
          if (!node.geometry.boundingBox) node.geometry.computeBoundingBox();
          const local = node.geometry.boundingBox;
          for (let i = 0; i < 8; i++) {
            point.set(i & 1 ? local.max.x : local.min.x, i & 2 ? local.max.y : local.min.y, i & 4 ? local.max.z : local.min.z).applyMatrix4(node.matrixWorld);
            const projection = cameraDistance / Math.max(0.001, cameraDistance - point.z);
            box.minX = Math.min(box.minX, point.x * projection);
            box.maxX = Math.max(box.maxX, point.x * projection);
            box.minY = Math.min(box.minY, point.y * projection);
            box.maxY = Math.max(box.maxY, point.y * projection);
          }
        }
        node.children.forEach(visit);
      };
      nodes.forEach(visit);
      if (Number.isFinite(box.minX)) bounds.push(box);
    }
    return bounds;
  }

  pourTears() {
    for (const t of this.tears) {
      if (!t.stream.visible) continue;
      const floorSpace = t.puddle?.parent ?? t.stream.parent;
      if (!floorSpace) continue;
      const floorY = (t.puddle?.position.y ?? 0) - TEAR_SINK;
      const eye = convert(new THREE.Vector3(), t.stream, floorSpace);
      const tip = convert(t.tip, t.stream, floorSpace);
      const drop = eye.y - tip.y;
      if (drop > 0.05) t.stream.scale.y *= Math.min(Math.max((eye.y - floorY) / drop, 0.6), 1.8);
      const landed = convert(t.tip, t.stream, floorSpace);
      for (const pool of [t.puddle, t.ripple]) {
        if (!pool) continue;
        pool.position.x = landed.x;
        pool.position.z = landed.z;
      }
    }
  }

  act(dt) {
    if (this.stateName !== this.actingState) {
      this.actingState = this.stateName;
      this.actingStart = this.clock;
    }
    const t = this.clock - this.actingStart;
    const head = this.headRig?.node;

    if (this.permissionLock) this.permissionLock.position.x -= 0.8 * this.clipWeight('permission');

    const coffee = this.clipWeight('coffee');
    if (this.mug) {
      if (this.stateName === 'coffee') {
        const s = Math.max(0.0001, this.mugAmount);
        this.mug.scale.multiplyScalar(s);
        this.mug.visible = s >= 0.02;
      } else if (coffee > 0) this.mug.visible = false;
    }
    if (coffee > 0.001 && this.mugArm != null && this.mugBase) {
      const arm = this.arms[this.mugArm].node;
      const cur = arm.quaternion.clone();
      arm.quaternion.copy(slerp(cur, slerp(this.mugBase, cur, MUG_REACH), coffee));
      const sip = clamp01(angleAxis(this.mugBase.clone().invert().multiply(cur)).angle / 0.68) * coffee;
      head?.quaternion.multiply(q(X, -SIP_TILT * sip));
      this.bodyRig?.node.quaternion.multiply(q(X, -SIP_LEAN * sip));
    }

    if (this.cap) this.cap.visible = false;

    const asleep = this.clipWeight('sleep');
    const rising = this.stateName === 'wake' ? this.clipWeight('wake') * (1 - smooth(0.05, 0.7, t)) : 0;
    const curl = Math.min(1, asleep + rising);
    if (curl > 0.001) {
      this.arms.forEach((arm, i) => { if (i < this.armRest.length) arm.node.quaternion.slerp(this.armRest[i], curl); });
      for (const leg of this.legs) leg.node.quaternion.slerp(leg.rot, curl);
      if (this.bodyRig) this.bodyRig.node.quaternion.slerp(this.bodyRig.rot, curl);
      if (head && this.headRig) head.quaternion.slerp(this.headRig.rot, curl);
      const breath = Math.sin(this.clock * 2 * Math.PI * BREATH_HZ) * curl * asleep;
      if (this.bodyRig) this.bodyRig.node.scale.z *= 1 + BREATH_DEPTH * breath;
      head?.quaternion.multiply(q(X, BREATH_NOD * breath));
    }

    if (this.bed) {
      const wanted = this.stateName === 'sleep' || (this.stateName === 'sleepy' && t > 4.3)
        || (this.stateName === 'wake' && t < 0.35 && this.bedAmount > 0);
      this.bedAmount = wanted ? Math.min(1, this.bedAmount + dt / BED_IN) : Math.max(0, this.bedAmount - dt / BED_OUT);
      this.bed.visible = this.bedAmount > 0;
      const grow = wanted ? easeOutBack(this.bedAmount) : smooth(0, 1, this.bedAmount);
      this.bed.scale.copy(this.bedRest).multiplyScalar(Math.max(0.001, grow));
      if (this.rigHips) {
        const n = this.rigHips.node;
        n.position.y += grow * (MATTRESS_TOP - 0.1);
        const tip = smooth(0, 0.6, curl), roll = smooth(0.4, 1, curl);
        const lying = q(Z, -INCLINE * roll).multiply(q(X, (-Math.PI / 2) * roll)).multiply(q(Z, (Math.PI / 2) * tip));
        n.quaternion.copy(lying.multiply(slerp(n.quaternion, this.rigHips.rot, curl)));
        const target = LYING_HIPS.clone().multiply(new THREE.Vector3(1, grow, 1));
        n.position.lerp(target, curl);
        if (grow > 0.9) {
          const e = this.bedEllipsoids();
          const need = Math.max(HEAD_REST - (e.head[0].y - e.head[1].y), BODY_REST - (e.body[0].y - e.body[1].y),
            BODY_REST - 0.08 - (e.legs[0].y - e.legs[1].y), 0);
          n.position.y += need;
        }
        const inv = n.quaternion.clone().invert();
        for (const z of this.sleepZs) {
          const up = Z_FROM.clone().add(z.position.clone().sub(Z_START));
          const local = up.sub(n.position).applyQuaternion(inv);
          z.position.lerp(local, curl);
          z.quaternion.slerp(inv.clone().multiply(z.quaternion), curl);
        }
      }
      if (this.blanket) {
        const tucked = this.stateName === 'sleep' && t > LIE_DOWN_S * 0.8;
        this.blanketAmount = tucked ? Math.min(1, this.blanketAmount + dt / BLANKET_UP) : Math.max(0, this.blanketAmount - dt / BLANKET_OFF);
        this.blanket.visible = this.blanketAmount > 0;
      }
      this.shapeBedding(smooth(0.85, 1, this.bedAmount) * (this.bed.visible ? 1 : 0));
    }

    if (this.stateName === 'wake' && head && t > SHAKE_AT && t < SHAKE_AT + SHAKE_S) {
      const k = (t - SHAKE_AT) / SHAKE_S;
      const yaw = SHAKE_YAW * Math.sin(k * Math.PI * 4) * (1 - k) * smooth(0, 0.12, k);
      head.quaternion.multiply(q(Y, yaw));
    }
  }

  reactToKeys(dt) {
    if (!this.bodyRig) return;
    const hit = Math.max(0, ...this.arms.map((a) => a.press));
    const side = this.arms.reduce((s, a) => s + a.side * a.press, 0);
    this.dip = damp(this.dip, hit, 30, dt);
    this.rock = damp(this.rock, side, 22, dt);
    this.nod = damp(this.nod, this.dip, 11, dt);
    this.tick = damp(this.tick, hit, 45, dt);
    if (this.keyDriven <= 0.001) return;
    const w = this.keyDriven;
    const body = this.bodyRig.node;
    body.position.y -= TAP_DIP * this.dip * w;
    body.quaternion.multiply(q(Z, -TAP_ROLL * this.rock * w));
    this.headRig?.node.quaternion.multiply(q(X, NOD_PITCH * this.nod * w));
    if (this.cursor && this.cursorRest) this.cursor.position.copy(this.cursorRest).add(new THREE.Vector3(CURSOR_KICK * this.tick * w, 0, 0));
  }

  bedEllipsoids() {
    const root = this.bedRoot;
    const ellipsoid = (node, c, r) => {
      if (!node || !root) return [new THREE.Vector3(0, 50, 0), new THREE.Vector3(0.01, 0.01, 0.01)];
      const m = relative(node, root);
      const cc = c.clone().applyMatrix4(m);
      const e = m.elements;
      const half = new THREE.Vector3();
      for (let i = 0; i < 3; i++) {
        let sum = 0;
        for (let j = 0; j < 3; j++) { const v = e[j * 4 + i] * [r.x, r.y, r.z][j]; sum += v * v; }
        half.setComponent(i, Math.sqrt(sum));
      }
      return [cc, half];
    };
    return {
      head: ellipsoid(this.headRig?.node, new THREE.Vector3(0, 1.27, -0.02), new THREE.Vector3(1.45, 1.22, 0.86)),
      body: ellipsoid(this.bodyRig?.node, new THREE.Vector3(0, 0.24, 0.02), new THREE.Vector3(1.18, 0.64, 0.5)),
      legs: ellipsoid(this.bodyRig?.node.parent, new THREE.Vector3(0, -0.3, 0), new THREE.Vector3(0.62, 0.32, 0.32)),
    };
  }

  shapeBedding(on) {
    if (!this.bedRoot || (!this.dentMaterials.length && !this.blanketMaterials.length)) return;
    const { head, body, legs } = this.bedEllipsoids();
    const reveal = easeOutCubic(this.blanketAmount);
    for (const m of [...this.dentMaterials, ...this.blanketMaterials]) {
      const u = m.userData.bed;
      u.hC.value.copy(head[0]); u.hR.value.copy(head[1]);
      u.bC.value.copy(body[0]); u.bR.value.copy(body[1]);
      u.lC.value.copy(legs[0]); u.lR.value.copy(legs[1]);
      u.uOn.value = on;
      u.reveal.value = reveal;
    }
  }

  letterOrigin() {
    if (!this.screen || !this.screen.prop.visible) return null;
    const b = this.screen.box.clone().applyMatrix4((this.screen.mesh.updateWorldMatrix(true, false), this.screen.mesh.matrixWorld));
    return [(b.min.x + b.max.x) / 2, b.max.y, (b.min.z + b.max.z) / 2];
  }

  dispose() {
    this.mixer?.stopAllAction();
    this.root.traverse((o) => {
      if (o.isMesh) {
        o.geometry?.dispose();
        (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => m?.dispose());
      }
    });
  }
}

const FACE_FOR_STATE = {
  typing: 'prompt', command: 'prompt', thinking: 'closed', meditate: 'closed', dizzy: 'dizzy',
  compacting: 'squint', workout: 'squint', sleep: 'asleep',
};
const OPEN_FACES = new Set(['eyes', 'wide', 'love']);
const PROMPT_STATES = new Set(['idle', 'walk', 'waiting', 'subagents', 'planning', 'boot']);
const FACE_FOR_EXPRESSION = {
  neutral: 'eyes', happy: 'happy', joy: 'happy', uwu: 'happy', excited: 'happy', love: 'love',
  sad: 'sad', crying: 'sad', sleepy: 'closed', asleep: 'asleep', deadpan: 'closed', smug: 'wink',
  curious: 'eyes', surprised: 'wide', nervous: 'wide', angry: 'squint', annoyed: 'squint', pouty: 'squint',
};
