import * as THREE from 'three';
import { clamp } from '../core/util.js';
import { FaceDisplay } from './face.js';
import { Locomotion, Personality } from './locomotion.js';
import { Pose, POSE_KEYS } from './pose.js';
import { StateMachine, T } from './stateMachine.js';
import { STATES } from './states.js';
import { TypedKeys } from '../effects/typedKeys.js';
import { StatusText } from '../effects/statusText.js';

const tmp = new THREE.Vector3();

export class Pet {
  constructor(mob, scene, settings) {
    this.mob = mob;
    this.settings = settings;
    this.target = new Pose();
    this.current = new Pose();
    this.overlay = new Pose();
    this.final = new Pose();
    this.poseRate = 8;
    this.lookHint = null;
    this.attention = null;
    this.socialMode = false;
    this.allowAutoWake = true;
    this.placement = { scale: 0.55, floorY: -1.5, minX: -3, maxX: 3, halfWidth: 4, halfHeight: 2, maxLift: 0 };
    this.breathPhase = 0;
    this.lift = 0;
    this.restLift = 0;
    this.home = null;
    this.homeChanged = false;
    this.climb = 0;
    this.carryVX = null;
    this.loco = new Locomotion();
    this.brain = new Personality();
    this.keycaps = new TypedKeys(scene);
    this.keycaps.setAccent(settings.keyColor);
    this.statusText = new StatusText(scene);
    this.fsm = new StateMachine(this, STATES);
    this.fsm.go(T('boot'));
  }

  get face() { return this.mob.face; }
  get stateName() { return this.fsm.name ?? 'boot'; }

  trigger(name, params = {}, force = false) {
    const Next = STATES[name];
    if (!Next) return false;
    if (!force && this.fsm.state && this.fsm.info.priority > Next.info.priority) return false;
    this.fsm.go(T(name, params));
    return true;
  }

  swapMob(next) {
    const old = this.mob;
    const parent = old.root.parent;
    if (parent) {
      next.root.position.copy(old.root.position);
      next.root.quaternion.copy(old.root.quaternion);
      next.root.scale.copy(old.root.scale);
      parent.add(next.root);
    }
    parent?.remove(old.root);
    next.face.setExpression(old.face.expression);
    next.stateName = old.stateName;
    this.mob = next;
    old.dispose?.();
  }

  setHome() {
    this.home = { x: this.loco.x, lift: this.restLift };
    this.homeChanged = true;
  }

  setPlacement(p) {
    this.placement = p;
    this.loco.setBounds(p.minX, p.maxX);
  }

  typeChar(ch, code = -1) {
    this.keycaps.input(ch);
    this.mob.pressKey(code);
  }

  releaseKey(code) { this.mob.releaseKey(code); }

  letterOrigin() {
    const o = this.mob.letterOrigin();
    if (o) return o;
    this.mob.head.getWorldPosition(tmp);
    return [tmp.x, tmp.y + this.mob.emoteLift * this.placement.scale, tmp.z];
  }

  update(dt) {
    this.target.reset();
    this.overlay.reset();
    this.poseRate = 8;
    this.lookHint = null;

    this.fsm.update(dt);
    const info = this.fsm.info;
    this.brain.update(dt, this.stateName);

    const scale = this.placement.scale;
    const walkSpeed = this.settings.walkSpeed ?? 1;
    this.loco.maxSpeed = 0.9 * walkSpeed;
    this.loco.update(dt, scale);
    if (!info.freeLift) {
      this.restLift = clamp(this.restLift, 0, this.placement.maxLift);
      const maxV = 1.4 * walkSpeed * scale;
      const step = clamp((this.restLift - this.lift) * 3, -maxV, maxV) * dt;
      this.lift += step;
      this.climb += (step / Math.max(dt, 1e-3) / scale - this.climb) * (1 - Math.exp(-6 * dt));
    } else {
      this.climb *= Math.exp(-6 * dt);
    }
    const mob = this.mob;
    mob.climb = this.climb;
    mob.lean = this.loco.walkAmount * 0.28;
    mob.walkAmount = this.loco.walkAmount;
    mob.walkPhase = this.loco.phase;
    mob.facing = this.loco.facing;
    mob.stateName = this.stateName;

    this.current.dampToward(this.target, this.poseRate, dt);
    for (const k of POSE_KEYS) this.final[k] = this.current[k] + this.overlay[k];
    this.applyWalk();
    this.applyGaze(info);

    const sleeping = this.stateName === 'sleep';
    this.breathPhase += dt * (sleeping ? 1.1 : 1.7);
    const breath = Math.sin(this.breathPhase) * (sleeping ? 1.8 : 1);

    const root = mob.root;
    root.position.set(this.loco.x, this.placement.floorY + this.lift, 0);
    root.scale.setScalar(scale);
    root.quaternion.setFromAxisAngle(Y_AXIS, this.loco.facing);
    mob.applyPose(this.final, breath);

    this.face.autoBlink = info.blink;
    this.face.update(dt);
    mob.animate(dt);
    this.keycaps.setAccent(this.settings.keyColor);
    this.keycaps.update(dt, {
      laptop: mob.laptopBounds(), fallback: this.letterOrigin(), scale,
      bounds: { x: this.placement.halfWidth, y: this.placement.halfHeight },
    });
    this.statusText.update(dt, this);
  }

  applyWalk() {
    const w = this.loco.walkAmount;
    if (w < 0.001) return;
    const s = Math.sin(this.loco.phase);
    const c = Math.cos(this.loco.phase);
    const f = this.final;
    f.bodyY += Math.abs(s) * 0.02 * w;
    f.torsoRoll += s * 0.02 * w;
    f.headRoll -= s * 0.03 * w;
    f.headPitch += c * 0.02 * w;
    f.torsoPitch += 0.05 * w;
    f.armSwingL += 0.1 * w;
    f.armSwingR += 0.1 * w;
  }

  get towardCenter() {
    const p = this.placement;
    const half = (p.maxX - p.minX) / 2;
    if (half <= 0.01) return 0;
    const k = clamp((this.loco.x - (p.maxX + p.minX) / 2) / half, -1, 1);
    return -0.5 * k;
  }

  applyGaze(info) {
    let look = null;
    if (this.attention && info.attentive) {
      this.mob.head.getWorldPosition(tmp);
      const dx = this.attention[0] - tmp.x, dy = this.attention[1] - tmp.y, dz = this.attention[2] - tmp.z;
      const yaw = Math.atan2(dx, dz);
      const pitch = Math.atan2(dy, Math.hypot(dx, dz));
      look = [clamp((yaw - this.loco.facing) / 0.9, -1, 1), clamp(pitch / 0.5, -1, 1)];
      this.loco.idleFacing = info.turnBody ? clamp(yaw * 0.45, -0.6, 0.6) : this.towardCenter;
    } else {
      this.loco.idleFacing = this.towardCenter;
      look = this.lookHint;
    }
    this.face.autoLook = !look && info.autoLook;
    if (look) this.face.lookAt(look[0], look[1]);
    else if (!info.autoLook) this.face.lookAt(0, 0);
    this.final.headYaw += this.face.look[0] * 0.45;
    this.final.headPitch -= this.face.look[1] * 0.3;
  }
}

const Y_AXIS = new THREE.Vector3(0, 1, 0);
