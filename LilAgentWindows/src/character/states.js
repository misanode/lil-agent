import { clamp01, dip, env, hop, pick, rnd, sgn, smooth } from '../core/util.js';
import { armRaise, armSwing, elbow, wrist } from './pose.js';
import { allows } from './locomotion.js';
import { PetState, T, info, then } from './stateMachine.js';

const idleFaces = ['uwu', 'smug', 'deadpan', 'nervous', 'pouty', 'love'];
const walkFaces = ['neutral', 'neutral', 'happy', 'uwu', 'smug'];
const coin = () => Math.random() < 0.5;

function jump(c, t, start, dur, height) {
  c.overlay.bodyY += hop(t, start, dur, height);
  c.overlay.crouch += dip(t, start - 0.04, 0.07) + dip(t, start + dur + 0.04, 0.06);
}

function atDesk(c) {
  c.loco.stop();
  c.restLift = c.home?.lift ?? 0;
}

function sideToward(c) {
  if (c.attention) return c.attention[0] > c.loco.x ? 'L' : 'R';
  return coin() ? 'L' : 'R';
}

class BootState extends PetState {
  static info = info({ priority: 9, autoLook: false, blink: false });
  enter(c) { c.face.setExpression('asleep'); }
  update(c, dt, t) {
    c.poseRate = 4;
    c.target.headPitch = t < 1.3 ? 0.4 : 0;
    c.target.crouch = t < 1.3 ? 0.05 : 0.01;
    c.target.armSwingL = t < 1.3 ? 0.15 : 0;
    c.target.armSwingR = c.target.armSwingL;
    if (t > 1.3 && c.face.expression === 'asleep') c.face.setExpression('neutral');
    if (t > 2.4) return T('wave', { then: 'idle' });
    return null;
  }
}

class IdleState extends PetState {
  enter(c, p) {
    this.baseExpr = c.socialMode ? 'neutral' : c.brain.idleExpression();
    c.face.setExpression(this.baseExpr);
    this.duration = p.duration ?? rnd(4, 9);
    this.fidget = null;
    this.nextFidget = rnd(1.5, 4);
  }

  update(c, dt, t) {
    c.target.torsoRoll = Math.sin(t * 0.5) * 0.025;
    c.target.crouch = 0.01 + 0.006 * Math.sin(t * 0.9);

    this.nextFidget -= dt;
    if (!this.fidget && this.nextFidget <= 0) {
      const f = { type: pick(['tilt', 'tilt', 'lookBack', 'shrug', 'hands', 'sway', 'face', 'face']), t0: t, dur: rnd(1.4, 2.4), side: coin() ? -1 : 1 };
      if (f.type === 'face') {
        f.dur = rnd(1.8, 2.8);
        c.face.setExpression(pick(idleFaces));
      }
      this.fidget = f;
    }
    const f = this.fidget;
    if (f) {
      const k = (t - f.t0) / f.dur;
      if (k >= 1) {
        if (f.type === 'face') c.face.setExpression(this.baseExpr);
        this.fidget = null;
        this.nextFidget = rnd(2, 5);
      } else {
        const e = Math.sin(k * Math.PI);
        switch (f.type) {
          case 'face': c.target.headRoll += 0.15 * f.side * e; break;
          case 'tilt': c.target.headRoll += 0.3 * f.side * e; break;
          case 'lookBack':
            c.target.headYaw += 0.75 * f.side * e;
            c.lookHint = [f.side * 0.8 * e, 0.1];
            break;
          case 'shrug':
            c.target.armRaiseL += 0.3 * e;
            c.target.armRaiseR += 0.3 * e;
            c.target.headRoll += 0.12 * f.side * e;
            break;
          case 'hands':
            c.target.armSwingL = 0.55 * e;
            c.target.armSwingR = 0.55 * e;
            c.target.elbowL = 1.0 * e;
            c.target.elbowR = 1.0 * e;
            c.target.headPitch += 0.3 * e;
            c.lookHint = [0, -0.7 * e];
            break;
          case 'sway':
            c.target.torsoRoll += 0.08 * f.side * Math.sin(k * Math.PI * 2);
            c.target.headRoll -= 0.1 * f.side * Math.sin(k * Math.PI * 2);
            break;
        }
      }
    }
    if (t > this.duration) return c.brain.nextAction(c);
    return null;
  }
}

class WalkState extends PetState {
  static info = info({ priority: 1 });
  enter(c, p) {
    c.loco.walkTo(p.x ?? c.loco.x);
    if (p.lift != null) c.restLift = p.lift;
    c.face.setExpression(p.mood ?? pick(walkFaces));
  }
  update(c, dt, t, p) {
    c.target.torsoPitch = 0.05;
    if (!c.attention) c.lookHint = [-sgn(c.loco.speed) * 0.35, -0.05];
    if (c.loco.arrived && Math.abs(c.restLift - c.lift) < 0.08 * c.placement.scale && t > 0.3) return then(p);
    if (t > 30) return T('idle');
    return null;
  }
  exit(c) { c.loco.stop(); }
}

class HappyState extends PetState {
  static info = info({ priority: 2 });
  enter(c) { c.face.setExpression('joy'); }
  update(c, dt, t, p) {
    c.poseRate = 10;
    if (t > 1.5 && c.face.expression === 'joy') c.face.setExpression('happy');
    jump(c, t, 0.35, 0.42, 0.16);
    jump(c, t, 1.05, 0.42, 0.16);
    const up = env(t, 0.2, 2.4, 0.3);
    c.target.armRaiseL = 2.3 * up;
    c.target.armRaiseR = 2.3 * up;
    c.target.elbowL = 0.4 * up;
    c.target.elbowR = 0.4 * up;
    c.overlay.wristL = Math.sin(t * 12) * 0.4 * up;
    c.overlay.wristR = -Math.sin(t * 12) * 0.4 * up;
    c.target.headPitch = -0.12 * up;
    if (t > 3) return then(p);
    return null;
  }
}

class SadState extends PetState {
  static info = info({ priority: 2, autoLook: false });
  static length = (2 * 97) / 24;
  enter(c) { c.face.setExpression('sad'); }
  update(c, dt, t, p) {
    c.poseRate = 3;
    if (t > 0.6 && c.face.expression === 'sad') c.face.setExpression('crying');
    const crying = c.face.expression === 'crying';
    c.target.headPitch = crying ? 0.18 : 0.45;
    c.target.torsoPitch = 0.14;
    c.target.crouch = 0.03;
    c.target.armSwingL = 0.15;
    c.target.armSwingR = 0.15;
    c.target.armRaiseL = -0.08;
    c.target.armRaiseR = -0.08;
    c.target.headRoll = 0.1 * Math.sin(t * 0.7);
    c.overlay.bodyY = -0.012 * env(t, 1.5, 2.6, 0.5);
    c.lookHint = crying ? [0.15 * Math.sin(t * 0.5), -0.2] : [0.2 * Math.sin(t * 0.5), -0.8];
    if (t > SadState.length) return then(p);
    return null;
  }
}

class SleepyState extends PetState {
  static info = info({ priority: 2, autoLook: false });
  enter(c) {
    c.restLift = c.home?.lift ?? 0;
    c.face.setExpression('sleepy');
  }
  update(c, dt, t) {
    c.poseRate = 4;
    const yawn = env(t, 0.5, 2.6, 0.5);
    const open = 0.28 * (1 - yawn) + 0.05 * yawn;
    c.face.target.eyeOpen = [open, open];
    c.target.armRaiseL = 2.6 * yawn;
    c.target.armRaiseR = 2.6 * yawn;
    c.target.elbowL = 0.3 * yawn;
    c.target.elbowR = 0.3 * yawn;
    c.target.torsoPitch = -0.1 * yawn;
    c.target.headPitch = -0.25 * yawn;
    if (t > 2.6) {
      const nod = Math.max(0, Math.sin((t - 2.6) * 2.2));
      c.target.headPitch = 0.25 + nod * 0.15;
      c.target.crouch = 0.03;
    }
    if (t > 5.5) return T('sleep');
    return null;
  }
}

class SleepState extends PetState {
  static info = info({ priority: 3, autoLook: false, blink: false, attentive: false });
  static napLength = 60;
  enter(c) {
    c.restLift = c.home?.lift ?? 0;
    c.face.setExpression('asleep');
  }
  update(c, dt, t) {
    c.poseRate = 2.5;
    c.target.sit = 1;
    c.target.headPitch = 0.5;
    c.target.headRoll = 0.15;
    c.target.torsoPitch = 0.18;
    c.target.armSwingL = 0.35;
    c.target.armSwingR = 0.35;
    c.target.elbowL = 0.5;
    c.target.elbowR = 0.5;
    if (c.allowAutoWake && t > SleepState.napLength) {
      c.brain.energy = 1;
      return T('wake');
    }
    return null;
  }
}

class WakeState extends PetState {
  static info = info({ priority: 3, autoLook: false });
  enter(c) { c.face.setExpression('sleepy'); }
  update(c, dt, t, p) {
    c.poseRate = 3.5;
    if (t > (c.mob.hasScreenFace ? 1.8 : 1) && c.face.expression === 'sleepy') c.face.setExpression('neutral');
    const stretch = env(t, 1.0, 2.4, 0.4);
    c.target.armRaiseL = 2.5 * stretch;
    c.target.armRaiseR = 2.5 * stretch;
    c.target.torsoPitch = -0.08 * stretch;
    c.target.headPitch = t < 0.6 ? 0.4 : -0.15 * stretch;
    if (t > 3) return then(p);
    return null;
  }
}

class CuriousState extends PetState {
  static info = info({ priority: 1 });
  enter(c) {
    c.face.setExpression('curious');
    this.side = coin() ? -1 : 1;
    this.spot = [rnd(-0.8, 0.8), rnd(-0.3, 0.5)];
  }
  update(c, dt, t, p) {
    c.poseRate = 6;
    c.target.headRoll = 0.32 * this.side;
    c.target.torsoPitch = 0.12;
    c.target.headPitch = 0.05;
    c.target.armSwingR = 1.3;
    c.target.elbowR = 1.9;
    c.target.armRaiseR = -0.1;
    c.overlay.headRoll = 0.04 * Math.sin(t * 3);
    if (!c.attention) c.lookHint = this.spot;
    if (t > 4) return then(p);
    return null;
  }
}

class SurprisedState extends PetState {
  static info = info({ priority: 4 });
  enter(c) { c.face.setExpression('surprised'); }
  update(c, dt, t, p) {
    c.poseRate = 16;
    c.target.sit = 0;
    jump(c, t, 0.06, 0.3, 0.12);
    c.target.armRaiseL = 1.0;
    c.target.armRaiseR = 1.0;
    c.target.elbowL = 0.9;
    c.target.elbowR = 0.9;
    c.target.torsoPitch = -0.12;
    c.target.headPitch = -0.15;
    if (t > 1.6) return then(p);
    return null;
  }
}

class ExcitedState extends PetState {
  static info = info({ priority: 2 });
  enter(c) {
    c.face.setExpression(Math.random() < 0.4 ? 'love' : 'excited');
    this.second = false;
  }
  update(c, dt, t, p) {
    c.poseRate = 10;
    const on = env(t, 0, 3.4, 0.3);
    c.overlay.bodyY = Math.abs(Math.sin(t * 8)) * 0.07 * on;
    c.target.armRaiseL = 1.5 * on;
    c.target.armRaiseR = 1.5 * on;
    c.overlay.armRaiseL = Math.sin(t * 8) * 0.6 * on;
    c.overlay.armRaiseR = -Math.sin(t * 8) * 0.6 * on;
    c.target.elbowL = 0.8 * on;
    c.target.elbowR = 0.8 * on;
    c.overlay.headRoll = Math.sin(t * 4) * 0.12 * on;
    if (t > 1.6 && !this.second) {
      this.second = true;
      c.face.setExpression('joy');
    }
    if (t > 3.5) return then(p);
    return null;
  }
}

class WaveState extends PetState {
  static info = info({ priority: 2 });
  enter(c, p) {
    c.face.setExpression(pick(['happy', 'uwu', 'joy']));
    this.side = p.side ?? sideToward(c);
  }
  update(c, dt, t, p) {
    c.poseRate = 9;
    const side = this.side;
    const sign = side === 'L' ? 1 : -1;
    const up = env(t, 0, 2.7, 0.35);
    c.target[armRaise(side)] = 2.5 * up;
    c.target[elbow(side)] = 0.5 * up;
    c.target[armSwing(side)] = 0.25 * up;
    c.overlay[armRaise(side)] = Math.sin(t * 9) * 0.22 * up;
    c.overlay[wrist(side)] = Math.sin(t * 9 + 0.6) * 0.45 * up;
    c.target.headRoll = 0.15 * sign * up;
    c.target.torsoRoll = -0.05 * sign * up;
    if (t > 2.8) return then(p);
    return null;
  }
}

class PetPetState extends PetState {
  static info = info({ priority: 2 });
  enter(c, p) {
    const count = p.count ?? 1;
    c.face.setExpression(count > 3 ? 'love' : pick(['uwu', 'happy', 'love']));
    this.side = coin() ? -1 : 1;
  }
  update(c, dt, t, p) {
    c.poseRate = 10;
    const on = env(t, 0, 1.8, 0.3);
    c.target.headRoll = 0.3 * this.side * on;
    c.target.headPitch = 0.12 * on;
    c.target.crouch = 0.03 * on;
    c.overlay.bodyY = Math.abs(Math.sin(t * 9)) * 0.02 * on;
    c.target.armRaiseL = 0.6 * on;
    c.target.armRaiseR = 0.6 * on;
    c.target.elbowL = 1.2 * on;
    c.target.elbowR = 1.2 * on;
    c.overlay.headRoll = Math.sin(t * 5) * 0.05 * on;
    if (t > 1.9) return then(p);
    return null;
  }
}

class CarriedState extends PetState {
  static info = info({ priority: 8, autoLook: false, freeLift: true });
  enter(c) {
    c.loco.stop();
    c.face.setExpression('surprised');
  }
  update(c, dt, t) {
    c.poseRate = 7;
    if (t > 0.9 && c.face.expression === 'surprised') c.face.setExpression('nervous');
    const vx = c.carryVX ?? 0;
    const sway = clamp01(Math.abs(vx) / 6) * sgn(vx);
    c.target.sit = 0;
    c.target.armRaiseL = 0.95;
    c.target.armRaiseR = 0.95;
    c.target.elbowL = 0.35;
    c.target.elbowR = 0.35;
    c.target.legSwingL = 0.25 + Math.sin(t * 5) * 0.2 - sway * 0.4;
    c.target.legSwingR = 0.25 - Math.sin(t * 5) * 0.2 - sway * 0.4;
    c.target.kneeL = 0.6;
    c.target.kneeR = 0.6;
    c.target.torsoRoll = -sway * 0.25;
    c.target.torsoPitch = sway * 0.1;
    c.target.headRoll = sway * 0.2;
    c.target.headPitch = 0.1;
    c.lookHint = [-sway * 0.5, -0.5];
    return null;
  }
}

class SettleState extends PetState {
  static info = info({ priority: 8 });
  enter(c) {
    c.restLift = c.lift;
    c.loco.stop();
    c.setHome();
    c.face.setExpression(c.lift > 0.1 ? 'happy' : 'neutral');
    this.side = coin() ? -1 : 1;
  }
  update(c, dt, t, p) {
    c.poseRate = 9;
    const k = Math.exp(-t * 2.2);
    c.overlay.bodyY = Math.sin(t * 9) * 0.06 * k;
    c.overlay.torsoRoll = Math.sin(t * 7) * 0.2 * k * this.side;
    c.target.headRoll = 0.15 * this.side * k;
    if (t > 1.2) return then(p);
    return null;
  }
}

class DropState extends PetState {
  static info = info({ priority: 8, autoLook: false, freeLift: true });

  enter(c, p) {
    const scale = c.placement.scale;
    this.vy = p.vy ?? 0;
    this.vx = p.vx ?? 0;
    const speed = Math.hypot(this.vx, this.vy) / scale;
    this.daze = 0.2 + 0.3 * clamp01(speed / 10);
    this.spinDir = this.vx === 0 ? 1 : sgn(this.vx);
    this.landed = -1;
    this.recovered = false;
    this.impact = 0;
    this.slide = 0;
    c.restLift = c.lift;
    c.face.setExpression('surprised');
  }

  update(c, dt, t, p) {
    c.poseRate = 12;
    const pl = c.placement;
    const scale = pl.scale;
    if (this.landed < 0) {
      const dazed = t < this.daze;
      if (dazed) {
        this.vy -= 5.5 * scale * dt;
        this.vx *= Math.exp(-0.6 * dt);
      } else {
        this.vy += -this.vy * (1 - Math.exp(-7 * dt));
        this.vx += -this.vx * (1 - Math.exp(-3 * dt));
        if (!this.recovered) {
          this.recovered = true;
          c.face.setExpression('nervous');
        }
      }
      c.lift += this.vy * dt;
      const ceiling = pl.halfHeight - pl.floorY - 1.7 * scale;
      if (c.lift > ceiling) {
        c.lift = ceiling;
        this.vy = -Math.abs(this.vy) * 0.35;
      }
      let x = c.loco.x + this.vx * dt;
      if (x < pl.minX || x > pl.maxX) {
        x = clamp01((x - pl.minX) / (pl.maxX - pl.minX)) * (pl.maxX - pl.minX) + pl.minX;
        this.vx = -this.vx * 0.45;
      }
      c.loco.x = x;
      c.loco.targetX = x;
      c.restLift = c.lift;

      const speed = Math.hypot(this.vx, this.vy) / scale;
      const spin = clamp01(speed / 6) * smooth(0, 0.08, t) * (1 - smooth(this.daze - 0.12, this.daze, t));
      c.overlay.torsoRoll = Math.sin(t * 18) * 0.6 * spin * this.spinDir;
      c.overlay.torsoPitch = Math.cos(t * 14) * 0.4 * spin;
      c.target.torsoPitch += (this.vx / (8 * scale)) * 0.5 * (1 - spin);
      c.target.torsoRoll += (-this.vx / (8 * scale)) * 0.3 * (1 - spin);
      c.target.headPitch = -0.15;
      c.lookHint = [0, 0.4];

      if (c.lift <= 0) {
        c.lift = 0;
        c.restLift = 0;
        this.landed = t;
        this.impact = clamp01(-this.vy / (7 * scale));
        this.slide = this.vx * 0.6;
        c.face.setExpression(this.impact > 0.6 ? 'annoyed' : 'nervous');
        c.loco.stop();
      } else if (!dazed && speed < 0.5) {
        return this.afterLanding(c, this.daze > 0.35, p);
      }
      return null;
    }
    const k = t - this.landed;
    this.slide *= Math.exp(-5 * dt);
    const x = Math.min(pl.maxX, Math.max(pl.minX, c.loco.x + this.slide * dt));
    c.loco.x = x;
    c.loco.targetX = x;
    const squash = this.impact * Math.max(0, 1 - k / 0.45);
    c.target.crouch = 0.12 * squash;
    c.target.torsoPitch = 0.22 * squash;
    c.target.headPitch = 0.35 * squash;
    c.target.sit = Math.max(0, 1 - k / 1.2);
    c.overlay.headRoll = Math.sin(k * 14) * 0.12 * this.impact * env(k, 0.5, 1.4, 0.18);
    if (k > 1.4) return this.afterLanding(c, this.impact > 0.35, p);
    return null;
  }

  afterLanding(c, hard, p) {
    const next = p.then ?? 'idle';
    const sad = allows(c.settings, 'sad');
    if (hard && allows(c.settings, 'dizzy')) return T('dizzy', { then: sad ? 'sad' : next });
    return sad ? T('sad', { then: next }) : T(next);
  }

  exit(c) { c.setHome(); }
}

class GrumpyState extends PetState {
  static info = info({ priority: 5 });
  enter(c) {
    c.face.setExpression('angry');
    c.loco.stop();
  }
  update(c, dt, t, p) {
    c.poseRate = 9;
    const huff = env(t, 0, 3.6, 0.3);
    c.target.headPitch = 0.1 * huff;
    c.target.crouch = 0.02 * huff;
    c.overlay.torsoRoll = Math.sin(t * 22) * 0.04 * env(t, 0.2, 1.2, 0.2);
    c.overlay.bodyY = Math.abs(Math.sin(t * 11)) * 0.015 * env(t, 0.2, 1.2, 0.2);
    if (!c.attention) c.lookHint = [0, 0];
    if (t > 3.8) return then(p);
    return null;
  }
}


class TypingState extends PetState {
  static info = info({ priority: 1, autoLook: false, attentive: false, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('neutral');
  }
  update(c, dt, t) {
    c.poseRate = 8;
    c.target.sit = 1;
    c.target.headPitch = 0.2;
    c.target.torsoPitch = 0.06;
    c.target.armSwingL = 0.6;
    c.target.armSwingR = 0.6;
    c.target.elbowL = 1.2;
    c.target.elbowR = 1.2;
    c.overlay.armSwingL = Math.max(0, Math.sin(t * 14)) * 0.15;
    c.overlay.armSwingR = Math.max(0, Math.sin(t * 14 + Math.PI)) * 0.15;
    c.lookHint = [0.2 * Math.sin(t * 0.8), -0.75];
    return null;
  }
}


class ReactionState extends PetState {
  static info = info({ priority: 1, autoLook: false, attentive: false, turnBody: false });
  get expression() { return 'neutral'; }
  enter(c) {
    atDesk(c);
    c.face.setExpression(this.expression);
  }
  update(c) {
    c.poseRate = 6;
    c.lookHint = [0, 0];
    return null;
  }
}

class ThinkingState extends ReactionState {}
class ReadingState extends ReactionState {}
class SearchingState extends ReactionState { get expression() { return 'curious'; } }
class CommandState extends ReactionState { get expression() { return 'curious'; } }
class PlanningState extends ReactionState { get expression() { return 'happy'; } }
class SubagentsState extends ReactionState { get expression() { return 'happy'; } }
class CompactingState extends ReactionState { get expression() { return 'annoyed'; } }
class ErrorState extends ReactionState { get expression() { return 'sad'; } }

class PermissionState extends PetState {
  static info = info({ priority: 3, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('nervous');
  }
  update(c) {
    c.poseRate = 8;
    if (!c.attention) c.lookHint = [0, 0.1];
    return null;
  }
}

class QuestionState extends PetState {
  static info = info({ priority: 3, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('curious');
  }
  update(c) {
    c.poseRate = 8;
    if (!c.attention) c.lookHint = [0, 0.1];
    return null;
  }
}

class DoneState extends PetState {
  static info = info({ priority: 2, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('joy');
  }
  update(c, dt, t, p) {
    c.poseRate = 8;
    if (t > 1.2 && c.face.expression === 'joy') c.face.setExpression('happy');
    if (t > 2.4) return T('donehold', { then: p.then });
    return null;
  }
}

class WaitingState extends PetState {
  static info = info({ priority: 1, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('neutral');
    this.nextFace = rnd(3, 6);
  }
  update(c, dt, t) {
    c.poseRate = 6;
    c.target.torsoRoll = Math.sin(t * 0.8) * 0.03;
    c.overlay.legSwingR = Math.max(0, Math.sin(t * 7)) * 0.18 * (Math.sin(t * 0.6) > 0 ? 1 : 0);
    if (!c.attention) c.lookHint = [0, 0];
    this.nextFace -= dt;
    if (this.nextFace <= 0) {
      c.face.setExpression(c.face.expression === 'neutral' ? pick(['curious', 'uwu', 'smug']) : 'neutral');
      this.nextFace = rnd(3, 6);
    }
    return null;
  }
}

class AttentionState extends PetState {
  static info = info({ priority: 3, turnBody: false });
  enter(c) {
    atDesk(c);
    c.face.setExpression('surprised');
  }
  update(c, dt, t) {
    c.poseRate = 10;
    if (t > 1 && c.face.expression === 'surprised') c.face.setExpression('nervous');
    const beat = t % 1.6;
    jump(c, beat, 0.1, 0.32, 0.1);
    c.target.armRaiseL = 2.0;
    c.target.armRaiseR = 2.0;
    c.overlay.armRaiseL = Math.sin(t * 10) * 0.4;
    c.overlay.armRaiseR = -Math.sin(t * 10) * 0.4;
    c.target.headPitch = -0.1;
    if (!c.attention) c.lookHint = [0, 0.1];
    return null;
  }
}

class DanceState extends PetState {
  static info = info({ priority: 1 });
  enter(c) {
    c.face.setExpression('happy');
    this.nextNote = 0.2;
  }
  update(c, dt, t, p) {
    c.poseRate = 12;
    const beat = t * Math.PI * 4;
    const on = p.loop ? smooth(0, 0.4, t) : env(t, 0, 6, 0.4);
    c.overlay.crouch = (0.03 + 0.03 * Math.sin(beat)) * on;
    c.overlay.torsoRoll = Math.sin(beat / 2) * 0.12 * on;
    c.overlay.headRoll = -Math.sin(beat / 2) * 0.2 * on;
    c.overlay.torsoYaw = Math.sin(beat / 4) * 0.2 * on;
    c.target.armRaiseL = (1.2 + Math.sin(beat / 2) * 1.0) * on;
    c.target.armRaiseR = (1.2 - Math.sin(beat / 2) * 1.0) * on;
    c.target.elbowL = 0.9 * on;
    c.target.elbowR = 0.9 * on;
    c.overlay.legSwingL = Math.max(0, Math.sin(beat / 2)) * 0.25 * on;
    c.overlay.legSwingR = Math.max(0, -Math.sin(beat / 2)) * 0.25 * on;
    c.overlay.kneeL = c.overlay.legSwingL * 1.5;
    c.overlay.kneeR = c.overlay.legSwingR * 1.5;
    this.nextNote -= dt;
    if (this.nextNote <= 0) {
      c.face.setExpression(['happy', 'joy', 'uwu'][Math.floor(t / 1.1) % 3]);
      this.nextNote = 1.1;
    }
    if (t > 6 && !p.loop) return then(p);
    return null;
  }
}


class MoodState extends PetState {
  static info = info({ priority: 2 });
  get expression() { return 'neutral'; }
  get duration() { return 5; }
  enter(c) {
    c.loco.stop();
    c.face.setExpression(this.expression);
  }
  update(c, dt, t, p) {
    c.poseRate = 6;
    c.lookHint = [0, 0];
    if (t > this.duration) return then(p);
    return null;
  }
}

class CoffeeState extends MoodState {
  static info = info({ priority: 2, autoLook: false, blink: false });
  static loop = 97 / 24;
  static putAway = 0.35;
  get duration() { return CoffeeState.loop * 2 + CoffeeState.putAway; }
  update(c, dt, t, p) {
    const L = CoffeeState.loop;
    c.mob.mugAmount = smooth(0, 0.3, t) * (1 - smooth(L * 2, L * 2 + CoffeeState.putAway, t));
    if (!c.mob.hasScreenFace && t > L * 2) return then(p);
    const phase = (t % L) * 24 + 1;
    const face = phase >= 30 && phase < 56 ? 'asleep' : phase >= 56 && phase < 80 ? 'uwu' : 'neutral';
    if (c.face.expression !== face) c.face.setExpression(face);
    return super.update(c, dt, t, p);
  }
}

class WorkoutState extends MoodState {
  static info = info({ priority: 2, autoLook: false });
  get expression() { return 'annoyed'; }
}

class MeditateState extends MoodState {
  static info = info({ priority: 2, autoLook: false, blink: false, attentive: false });
  get expression() { return 'asleep'; }
  get duration() { return 8; }
}

class IdeaState extends MoodState {
  static info = info({ priority: 2, autoLook: false });
  get expression() { return 'surprised'; }
  get duration() { return 3.2; }
  update(c, dt, t, p) {
    if (t > 1.2 && c.face.expression === 'surprised') c.face.setExpression('happy');
    return super.update(c, dt, t, p);
  }
}

class AnnoyedState extends MoodState {
  static info = info({ priority: 4, autoLook: false });
  get expression() { return 'angry'; }
  get duration() { return 73 / 24; }
}

class DizzyState extends MoodState {
  static info = info({ priority: 5, autoLook: false, attentive: false });
  get expression() { return 'sleepy'; }
  get duration() { return 3; }
}

class DoneHoldState extends PetState {
  static info = info({ priority: 2, turnBody: false });
  static length = 30 - 2.4;
  enter(c) { c.face.setExpression('happy'); }
  update(c, dt, t, p) {
    c.poseRate = 6;
    if (t > DoneHoldState.length) return then(p);
    return null;
  }
}

export const STATES = {
  boot: BootState, idle: IdleState, walk: WalkState, happy: HappyState,
  sad: SadState, sleepy: SleepyState, sleep: SleepState, wake: WakeState,
  curious: CuriousState, surprised: SurprisedState, excited: ExcitedState,
  wave: WaveState, pet: PetPetState, carried: CarriedState, settle: SettleState,
  drop: DropState, grumpy: GrumpyState, typing: TypingState, command: CommandState,
  reading: ReadingState, waiting: WaitingState, attention: AttentionState,
  dance: DanceState, thinking: ThinkingState, searching: SearchingState,
  planning: PlanningState, subagents: SubagentsState, compacting: CompactingState,
  error: ErrorState, permission: PermissionState, question: QuestionState, done: DoneState, donehold: DoneHoldState,
  coffee: CoffeeState, workout: WorkoutState, meditate: MeditateState, idea: IdeaState,
  annoyed: AnnoyedState, dizzy: DizzyState,
};

export const ACTIONS = ['idle', 'happy', 'sad', 'sleepy', 'sleep', 'wake', 'curious', 'surprised', 'excited', 'wave', 'dance', 'pet'];
