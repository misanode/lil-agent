import * as THREE from 'three';
import { clamp, clamp01, easeOutBack, easeOutCubic, lerp, rnd } from '../core/util.js';
import { FONT_FAMILY } from './statusText.js';

// Type-along keycaps: every key you press pops a matching keycap out of the pet's laptop,
// launched from a random spot on the lid in a random direction, then floats away and fades.

/** Keycap edge length in pet-scale units, so caps grow and shrink with the pet size setting. */
const SIZE = 0.24;
const POP_S = 0.3;
const HOLD_S = 0.42;
const FADE_S = 0.34;
const STAGGER = 0.05;
const MAX_ALIVE = 24;
/** Widest launch angle either side of straight up. */
const SPREAD = 1.3;
const CANDIDATES = 5;
const TEXTURE_SIZE = 192;
export const DEFAULT_KEY_COLOR = '#7E6345';

const NAMES = {
  '&': 'ampersand', '*': 'asterisk', '@': 'at', '\\': 'backslash', '`': 'backtick', '}': 'brace-close', '{': 'brace-open',
  ']': 'bracket-close', '[': 'bracket-open', '^': 'caret', ':': 'colon', ',': 'comma', '$': 'dollar', '"': 'double-quote',
  '=': 'equals', '!': 'exclamation', '>': 'greater-than', '#': 'hash', '<': 'less-than', '-': 'minus', '(': 'paren-open',
  ')': 'paren-close', '%': 'percent', '.': 'period', '|': 'pipe', '+': 'plus', '?': 'question', "'": 'quote',
  ';': 'semicolon', '/': 'slash', '~': 'tilde', '_': 'underscore',
};

const keyURL = (file) => new URL(`keys/${file}.png`, document.baseURI).href;

export function parseHex(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex ?? '').trim());
  if (!m) return null;
  const v = parseInt(m[1], 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = keyURL(file);
  });
}

function imagePixels(img) {
  const c = document.createElement('canvas');
  c.width = c.height = TEXTURE_SIZE;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
  return ctx.getImageData(0, 0, TEXTURE_SIZE, TEXTURE_SIZE).data;
}

function printable(ch) {
  if ([...ch].length !== 1 || /\s/.test(ch)) return false;
  const u = ch.codePointAt(0);
  return u >= 0x20 && u !== 0x7f && !(u >= 0xf700 && u <= 0xf8ff);
}

export class TypedKeys {
  constructor(scene) {
    this.group = new THREE.Group();
    scene.add(this.group);
    this.caps = [];
    this.textures = new Map();
    this.pairs = new Map();
    this.time = 0;
    this.lastBirth = -Infinity;
    this.cameraDistance = 10;
    this.accentHex = DEFAULT_KEY_COLOR;
    this.accent = parseHex(DEFAULT_KEY_COLOR);
    this.plane = new THREE.PlaneGeometry(1, 1);
  }

  /** Accent colour as #RRGGBB; changing it recolours keys typed from then on. */
  setAccent(hex) {
    if (hex === this.accentHex) return;
    this.accentHex = hex;
    this.accent = parseHex(hex) ?? parseHex(DEFAULT_KEY_COLOR);
    // Keys still in the air keep their old colour; a texture is freed once nothing shows it.
    const live = new Set(this.caps.map((c) => c.mesh.material.map));
    for (const t of this.textures.values()) if (!live.has(t)) t.dispose();
    this.textures.clear();
  }

  input(ch) {
    const texture = this.texture(ch);
    if (!texture) return;
    if (this.caps.length >= MAX_ALIVE) this.dispose(this.caps.shift());
    const born = Math.max(this.time, this.lastBirth + STAGGER);
    this.lastBirth = born;

    // Best of a few random angles: whichever is furthest from the keys still in the air.
    let angle = 0, gap = -1;
    for (let i = 0; i < CANDIDATES; i++) {
      const a = rnd(-SPREAD, SPREAD);
      const g = Math.min(Infinity, ...this.caps.map((c) => Math.abs(c.angle - a)));
      if (g > gap) { angle = a; gap = g; }
    }
    const u = clamp(Math.sin(angle) / Math.sin(SPREAD) * 0.7 + rnd(-0.15, 0.15), -0.9, 0.9);
    const rollFrom = rnd(-0.9, 0.9);

    const material = new THREE.MeshBasicMaterial({
      map: texture, transparent: true, depthTest: true, depthWrite: false, toneMapped: false, side: THREE.DoubleSide,
    });
    const mesh = new THREE.Mesh(this.plane, material);
    mesh.renderOrder = 10;
    mesh.frustumCulled = false;
    mesh.visible = false;
    mesh.scale.setScalar(0.0001);
    this.group.add(mesh);
    this.caps.push({
      mesh, born, u, v: rnd(0.55, 0.85), angle, distance: rnd(0.8, 1.25),
      rollFrom, rollTo: -angle * 0.25 + rnd(-0.2, 0.2), tiltX: rnd(-0.35, 0.35), tiltY: rnd(-0.4, 0.4), wobble: rnd(0, 2 * Math.PI),
    });
  }

  /**
   * @param laptop world-space bounds of the laptop ({ lo, hi } arrays), or null when it isn't out; caps then spring from `fallback`.
   * @param bounds half extents of the visible stage, used to keep caps on screen.
   */
  update(dt, { laptop, fallback, scale, bounds }) {
    this.time += dt;
    const side = SIZE * scale;
    const margin = side * 0.6;
    const lo = laptop?.lo ?? [fallback[0] - 0.25 * scale, fallback[1] - 0.2 * scale, fallback[2]];
    const hi = laptop?.hi ?? [fallback[0] + 0.25 * scale, fallback[1], fallback[2]];
    const cx = (lo[0] + hi[0]) / 2, cz = (lo[2] + hi[2]) / 2, halfX = (hi[0] - lo[0]) / 2;

    for (let i = this.caps.length - 1; i >= 0; i--) {
      const c = this.caps[i];
      const age = this.time - c.born;
      if (age >= POP_S + HOLD_S + FADE_S) {
        this.dispose(c);
        this.caps.splice(i, 1);
        continue;
      }
      if (age < 0) {
        c.mesh.visible = false;
        continue;
      }
      c.mesh.visible = true;

      const sx = cx + c.u * halfX * 0.8, sy = lo[1] + c.v * (hi[1] - lo[1]), sz = cz;
      const reach = c.distance * scale;
      const ex = clamp(sx + Math.sin(c.angle) * reach, -bounds.x + margin, bounds.x - margin);
      const ey = Math.min(Math.max(hi[1] + side * 0.4, sy + Math.cos(c.angle) * reach), bounds.y - margin);
      const ez = hi[2] + side * 0.3;

      const pop = clamp01(age / POP_S);
      const fly = clamp01(age / (POP_S * 1.4));
      const fade = clamp01((age - POP_S - HOLD_S) / FADE_S);
      const travel = 0.88 * easeOutCubic(fly) + 0.12 * clamp01((age - POP_S) / (HOLD_S + FADE_S));
      const bob = Math.sin(age * 7 + c.wobble) * 0.02 * scale * pop + fade * 0.12 * scale;
      c.mesh.position.set(lerp(sx, ex, travel), lerp(sy, ey, travel) + bob, lerp(sz, ez, travel));

      const grow = easeOutBack(pop) * (1 - 0.3 * fade);
      c.mesh.scale.setScalar(Math.max(side * grow, 0.0001));
      const settle = easeOutCubic(pop);
      const roll = lerp(c.rollFrom, c.rollTo, settle) + Math.sin(age * 5 + c.wobble) * 0.05;
      c.mesh.rotation.set(c.tiltX * (1 - 0.6 * settle), c.tiltY * (1 - 0.6 * settle), roll, 'XYZ');
      c.mesh.material.opacity = 1 - fade * fade;
    }
  }

  dispose(cap) {
    this.group.remove(cap.mesh);
    cap.mesh.material.dispose();
    const map = cap.mesh.material.map;
    const cached = [...this.textures.values()].includes(map);
    if (!cached && !this.caps.some((c) => c !== cap && c.mesh.material.map === map)) map.dispose();
  }

  texture(ch) {
    if (!printable(ch)) return null;
    const name = /^[a-z]$/i.test(ch) ? ch.toUpperCase() : NAMES[ch];
    const key = name ?? `blank+${ch}`;
    let texture = this.textures.get(key);
    if (texture) return texture;
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = TEXTURE_SIZE;
    texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 4;
    this.textures.set(key, texture);
    const accent = this.accent;
    this.pair(name ?? 'blank').then((pair) => {
      this.paint(canvas, pair, accent, name ? null : ch);
      texture.needsUpdate = true;
    }).catch(() => {});
    return texture;
  }

  /** The two renders of a key: its accent painted black and painted white (see LilAgentMac/Art/Keys/export.sh). */
  pair(name) {
    let p = this.pairs.get(name);
    if (!p) {
      p = Promise.all([loadImage(`key-${name}-0`), loadImage(`key-${name}-1`)]).then(([lo, hi]) => [imagePixels(lo), imagePixels(hi)]);
      p.catch(() => this.pairs.delete(name));
      this.pairs.set(name, p);
    }
    return p;
  }

  /**
   * Every gradient, blur and blend in the key art is linear in the accent colour, so mixing the
   * black- and white-accent renders by the accent rebuilds the key exactly in that colour.
   * Keys without their own art (digits, accented letters…) get the blank cap with `label` drawn on.
   */
  paint(canvas, [lo, hi], accent, label) {
    const s = TEXTURE_SIZE;
    const ctx = canvas.getContext('2d');
    const out = ctx.createImageData(s, s);
    const k = accent.map((v) => v / 255);
    for (let i = 0; i < lo.length; i += 4) {
      for (let c = 0; c < 3; c++) out.data[i + c] = lo[i + c] + (hi[i + c] - lo[i + c]) * k[c];
      out.data[i + 3] = lo[i + 3];
    }
    ctx.putImageData(out, 0, 0);
    if (!label) return;
    ctx.save();
    ctx.translate(s * 0.514, s * 0.505);
    ctx.rotate(-5.13 * Math.PI / 180);
    ctx.font = `800 ${Math.round(s * 0.6)}px ${FONT_FAMILY}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.shadowColor = `rgba(${accent.join(', ')}, 0.9)`;
    ctx.shadowBlur = s * 0.05;
    ctx.shadowOffsetY = s * 0.012;
    ctx.fillStyle = '#fff';
    ctx.fillText(label, 0, s * 0.02);
    ctx.restore();
  }
}
