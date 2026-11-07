export const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
export const clamp01 = (x) => clamp(x, 0, 1);
export const rnd = (a, b) => a + Math.random() * (b - a);
export const pick = (options) => options[Math.floor(Math.random() * options.length)];
export const sgn = (x) => (x > 0 ? 1 : x < 0 ? -1 : 0);

export function smooth(a, b, x) {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

export const env = (t, a, b, fade = 0.25) => smooth(a, a + fade, t) * (1 - smooth(b - fade, b, t));

export function hop(t, start, dur, h) {
  const k = (t - start) / dur;
  return k > 0 && k < 1 ? 4 * h * k * (1 - k) : 0;
}

export const dip = (t, at, depth, width = 0.12) => depth * Math.max(0, 1 - Math.abs(t - at) / width);
export const damp = (current, target, rate, dt) => current + (target - current) * (1 - Math.exp(-rate * dt));
export const easeOutBack = (x) => 1 + 2.70158 * (x - 1) ** 3 + 1.70158 * (x - 1) ** 2;
export const easeOutCubic = (x) => 1 - (1 - x) ** 3;
export const lerp = (a, b, t) => a + (b - a) * t;

export const now = () => performance.now() / 1000;
