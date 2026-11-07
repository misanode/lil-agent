import { clamp, damp, rnd } from '../core/util.js';

const E = (eyeOpen = [1, 1], eyeScale = [1, 1]) => ({ eyeOpen, eyeScale });

export const EXPRESSIONS = {
  neutral: E(),
  happy: E([1, 1], [1.05, 1.05]),
  sad: E([0.8, 0.8], [0.95, 0.95]),
  sleepy: E([0.28, 0.28]),
  asleep: E([0, 0]),
  curious: E([1, 0.72], [1.15, 0.92]),
  surprised: E([1, 1], [1.32, 1.32]),
  excited: E([1, 1], [1.2, 1.2]),
  angry: E([0.85, 0.85]),
  joy: E(),
  love: E([1, 1], [1.1, 1.1]),
  uwu: E(),
  crying: E([0.14, 0.14]),
  smug: E([0.42, 0.42]),
  deadpan: E([0.1, 0.1]),
  annoyed: E([0.45, 0.45]),
  nervous: E(),
  pouty: E([0.85, 0.85]),
};

const copy = (e) => ({ eyeOpen: [...e.eyeOpen], eyeScale: [...e.eyeScale] });

export class FaceDisplay {
  constructor() {
    this.expression = 'neutral';
    this.target = copy(EXPRESSIONS.neutral);
    this.current = copy(EXPRESSIONS.neutral);
    this.transitionRate = 9;
    this.look = [0, 0];
    this.lookTarget = [0, 0];
    this.autoLook = true;
    this.nextSaccade = rnd(1, 3);
    this.autoBlink = true;
    this.blinkPhase = -1;
    this.blinkFactor = 1;
    this.nextBlink = rnd(1.5, 4);
  }

  setExpression(name) {
    this.expression = name;
    this.target = copy(EXPRESSIONS[name] ?? EXPRESSIONS.neutral);
  }

  blink() {
    if (this.blinkPhase < 0) this.blinkPhase = 0;
  }

  lookAt(x, y) {
    this.lookTarget = [clamp(x, -1, 1), clamp(y, -1, 1)];
  }

  updateBlink(dt) {
    if (this.autoBlink && this.blinkPhase < 0) {
      this.nextBlink -= dt;
      if (this.nextBlink <= 0) {
        this.blink();
        this.nextBlink = Math.random() < 0.15 ? 0.22 : rnd(2, 5.5);
      }
    }
    if (this.blinkPhase < 0) return 1;
    this.blinkPhase += dt / 0.18;
    if (this.blinkPhase >= 1) {
      this.blinkPhase = -1;
      return 1;
    }
    return 1 - Math.sin(this.blinkPhase * Math.PI);
  }

  updateSaccades(dt) {
    if (!this.autoLook) return;
    this.nextSaccade -= dt;
    if (this.nextSaccade > 0) return;
    this.nextSaccade = rnd(0.8, 3.2);
    this.lookTarget = Math.random() < 0.3 ? [0, 0] : [rnd(-0.75, 0.75), rnd(-0.4, 0.35)];
  }

  update(dt) {
    const r = this.transitionRate;
    for (let i = 0; i < 2; i++) {
      this.current.eyeOpen[i] = damp(this.current.eyeOpen[i], this.target.eyeOpen[i], r, dt);
      this.current.eyeScale[i] = damp(this.current.eyeScale[i], this.target.eyeScale[i], r, dt);
    }
    this.updateSaccades(dt);
    this.look[0] = damp(this.look[0], this.lookTarget[0], 16, dt);
    this.look[1] = damp(this.look[1], this.lookTarget[1], 16, dt);
    this.blinkFactor = this.updateBlink(dt);
  }
}
