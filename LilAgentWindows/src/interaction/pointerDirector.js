import { clamp, now } from '../core/util.js';
import { allows } from '../character/locomotion.js';

const SLEEPING = new Set(['sleep', 'sleepy']);
const AIRBORNE_STATES = new Set(['carried', 'drop']);
const DRAG_THRESHOLD_PX = 6;
const PET_WINDOW = 3;
const GAZE_DEPTH = 4;
const VELOCITY_WINDOW = 0.08;
const MAX_THROW = 14;
const THROW_SPEED = 3.5;
const WHEEL_ZOOM = 0.0015;

export class PointerDirector {
  constructor(pet, screen) {
    this.pet = pet;
    this.screen = screen;
    this.pointer = null;
    this.over = false;
    this.cursor = null;
    this.airborne = false;
    this.menuOpen = false;
    this.press = null;
    this.drag = null;
    this.pets = [];
    this.size = () => 210;
    this.onResize = null;
    this.onOverChange = null;
    this.onAirborneChange = null;
  }

  get dragging() { return this.drag != null; }

  world(px, py) { return { x: this.screen.toWorldX(px), h: this.screen.heightAboveFloor(py, this.pet.placement.floorY) }; }

  hits(w) {
    const s = this.pet.placement.scale, b = this.pet.mob.hitBox, dx = w.x - this.pet.loco.x;
    return dx > b.minX * s && dx < b.maxX * s && w.h > this.pet.lift && w.h < this.pet.lift + b.top * s;
  }

  move(px, py) {
    this.pointer = { x: px, y: py };
    const w = this.world(px, py);
    if (this.press && !this.drag && Math.hypot(px - this.press.x, py - this.press.y) > DRAG_THRESHOLD_PX) this.startDrag(w);
    const d = this.drag;
    if (d) {
      const t = now();
      d.x = w.x - d.offsetX;
      d.h = w.h - d.offsetH;
      d.history.push({ x: d.x, h: d.h, t });
      while (d.history.length > 2 && t - d.history[0].t > VELOCITY_WINDOW) d.history.shift();
    }
  }

  leave() { if (!this.drag) this.pointer = null; }

  releaseVelocity(d) {
    const t = now();
    const recent = d.history.filter((p) => t - p.t <= VELOCITY_WINDOW);
    const first = recent[0], last = recent[recent.length - 1];
    if (!first || !last || last.t - first.t < 0.016 || t - last.t > 0.09) return { vx: 0, vy: 0 };
    const dt = last.t - first.t;
    const cap = MAX_THROW * this.pet.placement.scale;
    return { vx: clamp((last.x - first.x) / dt, -cap, cap), vy: clamp((last.h - first.h) / dt, -cap, cap) };
  }

  wheel(delta) {
    if (!this.onResize || this.drag || this.menuOpen || !this.over) return;
    this.onResize(this.size() * Math.exp(-clamp(delta, -120, 120) * WHEEL_ZOOM));
  }

  down(px, py) {
    if (this.menuOpen || !this.over) return;
    this.press = { x: px, y: py };
  }

  startDrag(w) {
    this.drag = { offsetX: w.x - this.pet.loco.x, offsetH: w.h - this.pet.lift, x: this.pet.loco.x, h: this.pet.lift, history: [] };
    this.pet.carryVX = 0;
    this.pet.trigger('carried', {}, true);
  }

  up() {
    const d = this.drag;
    if (d) {
      const v = this.releaseVelocity(d);
      const speed = Math.hypot(v.vx, v.vy) / this.pet.placement.scale;
      if (speed < THROW_SPEED) this.pet.trigger('settle', { then: 'idle' }, true);
      else this.pet.trigger('drop', { then: 'idle', vx: v.vx, vy: v.vy }, true);
      this.pet.carryVX = null;
      this.drag = null;
    } else if (this.press) {
      this.petIt();
    }
    this.press = null;
  }

  petIt() {
    const t = now();
    this.pets = this.pets.filter((p) => t - p < PET_WINDOW);
    this.pets.push(t);
    const count = this.pets.length;
    const pet = this.pet, s = pet.stateName;
    if (SLEEPING.has(s)) pet.trigger('surprised', { then: 'wake' }, true);
    else if (count >= 9 && s !== 'dizzy' && allows(pet.settings, 'dizzy')) pet.trigger('dizzy', { then: 'grumpy' }, true);
    else if (count >= 5 && s !== 'annoyed' && s !== 'dizzy' && allows(pet.settings, 'annoyed')) pet.trigger('annoyed', { then: 'idle' }, true);
    else if (s === 'annoyed' || s === 'dizzy') return;
    else pet.trigger('pet', { then: 'idle', count }, true);
  }

  update(dt) {
    const pet = this.pet;
    const w = this.pointer ? this.world(this.pointer.x, this.pointer.y) : null;
    const isOver = this.drag != null || this.menuOpen || (w ? this.hits(w) : false);
    if (isOver !== this.over) {
      this.over = isOver;
      this.onOverChange?.(isOver);
    }
    const isAirborne = this.drag != null || AIRBORNE_STATES.has(pet.stateName) || pet.lift > 0.03 || pet.restLift > 0.03;
    if (isAirborne !== this.airborne) {
      this.airborne = isAirborne;
      this.onAirborneChange?.(isAirborne);
    }

    const d = this.drag;
    if (d) {
      const p = pet.placement;
      const x = clamp(d.x, p.minX, p.maxX);
      pet.loco.x = x;
      pet.loco.targetX = x;
      pet.loco.speed = 0;
      pet.lift = Math.max(0, d.h);
      let vx = 0;
      const a = d.history[0], b = d.history[d.history.length - 1];
      if (a && b && b.t > a.t) vx = (b.x - a.x) / (b.t - a.t);
      pet.carryVX = (pet.carryVX ?? 0) + (vx - (pet.carryVX ?? 0)) * (1 - Math.exp(-8 * dt));
      pet.attention = null;
      return;
    }

    const c = this.cursor ? this.world(this.cursor.x, this.cursor.y) : w;
    if (pet.settings.lookAtCursor !== false && pet.stateName !== 'drop' && c) pet.attention = [c.x, pet.placement.floorY + c.h, GAZE_DEPTH];
    else pet.attention = null;
  }
}
