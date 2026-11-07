export const info = (o = {}) => ({
  priority: 0,
  autoLook: true,
  blink: true,
  attentive: true,
  turnBody: true,
  freeLift: false,
  ...o,
});

export class PetState {
  static info = info();
  enter(_c, _p) {}
  update(_c, _dt, _t, _p) { return null; }
  exit(_c) {}
}

export const T = (name, params = {}) => ({ name, params });
export const then = (p, fallback = 'idle') => T(p.then ?? fallback);

export class StateMachine {
  constructor(ctx, states) {
    this.ctx = ctx;
    this.states = states;
    this.name = null;
    this.state = null;
    this.params = {};
    this.time = 0;
    this.listeners = [];
  }

  get info() { return this.state ? this.state.constructor.info : info(); }

  go(next) {
    const Type = this.states[next.name];
    if (!Type) return;
    const prev = this.name;
    this.state?.exit(this.ctx);
    const s = new Type();
    this.name = next.name;
    this.state = s;
    this.params = next.params ?? {};
    this.time = 0;
    s.enter(this.ctx, this.params);
    for (const fn of this.listeners) fn(next.name, prev);
  }

  update(dt) {
    if (!this.state) return;
    this.time += dt;
    const next = this.state.update(this.ctx, dt, this.time, this.params);
    if (next) this.go(next);
  }
}
