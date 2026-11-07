import { clamp, rnd, sgn } from '../core/util.js';
import { T } from './stateMachine.js';

const WALK_FACING = 1.0;
const CYCLE_LENGTH = 0.8;

export class Locomotion {
  constructor() {
    this.x = 0; this.targetX = 0; this.speed = 0; this.maxSpeed = 0.9;
    this.phase = 0; this.walkAmount = 0; this.facing = 0; this.idleFacing = 0;
    this.minX = -3; this.maxX = 3; this.scale = 1;
  }

  setBounds(minX, maxX) {
    this.minX = minX;
    this.maxX = maxX;
    this.x = clamp(this.x, minX, maxX);
    this.targetX = clamp(this.targetX, minX, maxX);
  }

  walkTo(x) { this.targetX = clamp(x, this.minX, this.maxX); }
  stop() { this.targetX = this.x; }

  get arrived() { return Math.abs(this.targetX - this.x) < 0.04 * this.scale && Math.abs(this.speed) < 0.08 * this.scale; }

  update(dt, scale) {
    this.scale = scale;
    const vmax = this.maxSpeed * scale;
    const dx = this.targetX - this.x;
    const desired = Math.abs(dx) > 0.01 * scale ? sgn(dx) * Math.min(vmax, Math.abs(dx) * 2.5) : 0;
    this.speed += (desired - this.speed) * (1 - Math.exp(-5 * dt));
    const nextX = this.x + this.speed * dt;
    this.x = clamp(nextX, this.minX, this.maxX);
    if (this.x !== nextX) this.speed = 0;
    this.walkAmount = Math.min(1, Math.abs(this.speed) / (0.35 * vmax));
    this.phase += (Math.abs(this.speed) / (CYCLE_LENGTH * scale)) * Math.PI * 2 * dt;
    const facingTarget = Math.abs(this.speed) > 0.12 * vmax ? sgn(this.speed) * WALK_FACING : this.idleFacing;
    this.facing += (facingTarget - this.facing) * (1 - Math.exp(-6 * dt));
  }
}

const TIRED = 0.18;
const AWAKE_TIME = 30 * 60;

export class Personality {
  constructor() { this.energy = 1; }

  update(dt, state) {
    if (state === 'sleep') this.energy = Math.min(1, this.energy + dt / 35);
    else this.energy = Math.max(0, this.energy - dt * (1 - TIRED) / AWAKE_TIME);
  }

  idleExpression() { return this.energy < 0.3 ? 'sleepy' : 'neutral'; }

  weightedPick(options) {
    const total = options.reduce((s, [, w]) => s + w, 0);
    let r = Math.random() * total;
    for (const [name, w] of options) {
      r -= w;
      if (r <= 0) return name;
    }
    return options[0][0];
  }

  nextAction(c) {
    if (this.energy < TIRED) return T('sleepy');
    const options = c.socialMode
      ? [['idle', 3], ['curious', 1.2], ['happy', 0.8], ['wave', 0.5], ['dance', 0.6], ['excited', 0.4]]
      : [['walk', c.settings.autoWalk ? 4 : 0], ['idle', 2], ['curious', 1], ['happy', 0.5], ['dance', 0.4],
        ['excited', 0.3], ['sad', 0.2], ['wave', 0.25],
        ['coffee', 0.45], ['workout', 0.3], ['meditate', 0.3], ['idea', 0.35]];
    const name = this.weightedPick(options.filter(([n]) => n === 'walk' || n === 'idle' || allows(c.settings, n)));
    if (name !== 'walk') return T(name);

    const loco = c.loco;
    if (c.home) {
      const reach = 0.8 * c.placement.scale;
      const near = Math.min(loco.maxX, Math.max(loco.minX, c.home.x + rnd(-reach, reach)));
      return T('walk', { x: near, lift: c.home.lift });
    }
    const range = loco.maxX - loco.minX;
    let target = loco.x;
    for (let i = 0; i < 6 && Math.abs(target - loco.x) < range * 0.25; i++) target = rnd(loco.minX, loco.maxX);
    const params = { x: target };
    const maxLift = c.placement.maxLift;
    if (maxLift > 0) {
      const r = Math.random();
      if (r < 0.25) params.lift = 0;
      else if (r < 0.6) params.lift = rnd(0, maxLift);
      else params.lift = Math.min(maxLift, Math.max(0, c.restLift + rnd(-1.5, 1.5) * c.placement.scale));
    }
    return T('walk', params);
  }
}

export const allows = (settings, state) => !(settings.disabled ?? []).includes(state);
