import * as THREE from 'three';
import { clamp, damp, easeOutBack, easeOutCubic, lerp } from '../core/util.js';
import { PIXELS_PER_UNIT } from '../core/stage.js';

const FAMILY = '"SF Pro Rounded", ui-rounded, "Nunito", "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif';
export const font = (px) => `700 ${px}px ${FAMILY}`;
const TRACKING = 0.045;
const EM = 0.6875;
const BOX_H = 1.35;
const SIZE = 0.24;
const CLIP_FEATHER = 0.12;
const PAUSE_S = 1.5;
const SEND_S = 0.9;
const POP_S = 0.24;
const STAGGER = 0.045;

export const PALETTES = {
  clawd: { rim: 'rgb(201, 96, 58)', fill: 'rgb(255, 250, 245)', shadow: 'rgba(70, 25, 10, 0.45)' },
  codex: { rim: 'rgb(64, 98, 224)', fill: 'rgb(236, 252, 255)', shadow: 'rgba(14, 20, 60, 0.45)' },
};

function isControl(ch) {
  const u = ch.codePointAt(0);
  return u == null || u < 0x20 || (u >= 0xf700 && u <= 0xf8ff);
}

function clippedMaterial(texture, clip) {
  const m = new THREE.MeshBasicMaterial({ map: texture, transparent: true, depthTest: false, depthWrite: false, toneMapped: false });
  m.onBeforeCompile = (s) => {
    Object.assign(s.uniforms, clip);
    s.vertexShader = s.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vClipView;')
      .replace('#include <project_vertex>', '#include <project_vertex>\nvClipView = mvPosition.xyz;');
    s.fragmentShader = s.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vClipView;\nuniform float clipMin;\nuniform float clipMax;\nuniform float clipFeather;')
      .replace('#include <dithering_fragment>', `#include <dithering_fragment>
float clipS = vClipView.x / max(-vClipView.z, 0.0001);
float clipA = smoothstep(clipMin, clipMin + clipFeather, clipS) * (1.0 - smoothstep(clipMax - clipFeather, clipMax, clipS));
gl_FragColor *= clipA;`);
  };
  m.customProgramCacheKey = () => 'lilagent-letters';
  return m;
}

export class TypedLetters {
  constructor(scene) {
    this.group = new THREE.Group();
    scene.add(this.group);
    this.glyphs = new Map();
    this.meshGlyphs = new WeakMap();
    this.line = [];
    this.sent = [];
    this.removed = [];
    this.lastKey = -Infinity;
    this.lastBirth = -Infinity;
    this.warmQueue = [];
    this.time = 0;
    this.scroll = 0;
    this.scale = 1;
    this.res = 0;
    this.palette = PALETTES.clawd;
    this.clip = { clipMin: { value: -10 }, clipMax: { value: 10 }, clipFeather: { value: 0.01 } };
    this.cameraDistance = 10;
    this.measure = document.createElement('canvas').getContext('2d');
    document.fonts?.load(font(88)).catch(() => {});
  }

  get palette() { return this._palette; }
  set palette(p) {
    this._palette = p;
    this.clearGlyphs();
    this.warm();
  }

  clearGlyphs() {
    for (const glyph of this.glyphs.values()) {
      glyph.cached = false;
      if (glyph.refs === 0) glyph.texture.dispose();
    }
    this.glyphs.clear();
  }

  warm() {
    this.warmQueue = [];
    for (let c = 33; c <= 126; c++) this.warmQueue.push(String.fromCharCode(c));
  }

  setResolution(scale) {
    const r = Math.max(24, Math.round(SIZE * scale * PIXELS_PER_UNIT * (window.devicePixelRatio || 1)));
    if (Math.abs(r - this.res) <= 1) return;
    this.res = r;
    this.px = Math.round(r * EM);
    this.clearGlyphs();
    this.warm();
  }

  width(text) {
    this.measure.font = font(this.px);
    return this.measure.measureText(text).width / this.res;
  }

  kern(a, b) {
    if (a == null) return 0;
    return this.width(a + b) - this.width(a) - this.width(b);
  }

  glyph(ch) {
    const cached = this.glyphs.get(ch);
    if (cached) return cached;
    const r = this.res, px = this.px;
    const pad = Math.ceil(r * 0.28);
    this.measure.font = font(px);
    const metrics = this.measure.measureText(ch);
    const advance = metrics.width;
    const inkW = Math.max(advance, (metrics.actualBoundingBoxLeft ?? 0) + (metrics.actualBoundingBoxRight ?? advance));
    const width = Math.ceil(inkW + pad * 2);
    const height = Math.ceil(r * BOX_H);
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, width);
    canvas.height = Math.max(1, height);
    const ctx = canvas.getContext('2d');
    ctx.font = font(px);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const x = width / 2, y = height / 2 + px * 0.05;
    ctx.lineJoin = 'round';
    ctx.lineWidth = px * 0.16;
    ctx.shadowColor = this.palette.shadow;
    ctx.shadowOffsetY = px * 0.05;
    ctx.shadowBlur = px * 0.1;
    ctx.fillStyle = this.palette.rim;
    ctx.strokeStyle = this.palette.rim;
    ctx.strokeText(ch, x, y);
    ctx.fillText(ch, x, y);
    ctx.shadowColor = 'transparent';
    ctx.strokeText(ch, x, y);
    ctx.fillText(ch, x, y);
    ctx.fillStyle = this.palette.fill;
    ctx.fillText(ch, x, y);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.generateMipmaps = false;
    texture.minFilter = THREE.LinearFilter;
    const g = { texture, w: width / r, h: height / r, advance: advance / r + TRACKING, refs: 0, cached: true };
    this.glyphs.set(ch, g);
    return g;
  }

  node(g) {
    const mesh = new THREE.Mesh(PLANE, clippedMaterial(g.texture, this.clip));
    g.refs += 1;
    this.meshGlyphs.set(mesh, g);
    mesh.renderOrder = 10;
    mesh.frustumCulled = false;
    this.size(mesh, g, 0.0001);
    this.group.add(mesh);
    return mesh;
  }

  size(mesh, g, s) { mesh.scale.set(s * g.w, s * g.h, 1); }

  input(ch) {
    this.lastKey = this.time;
    if (ch === '\r' || ch === '\n') return this.send();
    if (ch === '\u007f' || ch === '\b') {
      const last = this.line.pop();
      if (last?.node) this.removed.push({ node: last.node, glyph: last.glyph, t: 0 });
      return;
    }
    this.setResolution(this.scale);
    if (ch === ' ' || ch === '\t') {
      this.line.push({ ch: null, node: null, glyph: null, lead: 0, advance: this.width(' ') * 1.15 + TRACKING, born: this.nextBirth() });
      return;
    }
    if (isControl(ch)) return;
    const g = this.glyph(ch);
    const prev = this.line[this.line.length - 1];
    this.line.push({ ch, node: this.node(g), glyph: g, lead: this.kern(prev?.ch ?? null, ch), advance: g.advance, born: this.nextBirth() });
  }

  nextBirth() {
    const born = Math.max(this.time, this.lastBirth + STAGGER);
    this.lastBirth = born;
    return born;
  }

  send() {
    const nodes = this.line.map((l) => l.node).filter(Boolean);
    if (nodes.length) this.sent.push({ nodes, base: nodes.map((n) => n.position.clone()), t: 0 });
    this.line = [];
    this.scroll = 0;
  }

  release(mesh) {
    this.group.remove(mesh);
    mesh.material.dispose();
    const glyph = this.meshGlyphs.get(mesh);
    if (glyph) {
      glyph.refs -= 1;
      if (glyph.refs === 0 && !glyph.cached) glyph.texture.dispose();
      this.meshGlyphs.delete(mesh);
    }
  }

  update(dt, { origin, scale, lineY, clipCenter, clipHalf, clipDepth }) {
    this.time += dt;
    this.scale = scale;
    this.setResolution(scale);
    for (let i = 0; i < 3 && this.warmQueue.length; i++) this.glyph(this.warmQueue.pop());
    if (this.line.length && this.time - this.lastKey > PAUSE_S) this.send();

    const unit = SIZE * scale;
    const letterZ = origin[2] + 0.1 * scale;
    const toFront = Math.max(this.cameraDistance - clipDepth, 0.001);
    const toLetter = Math.max(this.cameraDistance - letterZ, 0.001);
    const toLetters = toLetter / toFront;
    this.clip.clipMin.value = (clipCenter - clipHalf) / toFront;
    this.clip.clipMax.value = (clipCenter + clipHalf) / toFront;
    this.clip.clipFeather.value = (CLIP_FEATHER * unit) / toLetter;
    const lineCenter = clipCenter * toLetters;
    const width = this.line.reduce((s, l) => s + l.lead + l.advance, 0);
    const maxW = Math.max(unit, 2 * clipHalf * toLetters - 2 * CLIP_FEATHER * unit - 0.1 * unit);
    const targetScroll = Math.max(0, width * unit - maxW);
    this.scroll = damp(this.scroll, targetScroll, 22, dt);
    const left = -Math.min(width * unit, maxW) / 2 - this.scroll;
    let cursor = 0;
    for (const l of this.line) {
      cursor += l.lead;
      const slot = left + (cursor + l.advance / 2) * unit;
      cursor += l.advance;
      if (!l.node) continue;
      const k = clamp((this.time - l.born) / POP_S, 0, 1);
      const fly = easeOutCubic(k);
      l.node.position.set(lerp(origin[0], lineCenter + slot, fly), lerp(origin[1], lineY, fly), letterZ);
      this.size(l.node, l.glyph, unit * easeOutBack(k));
    }

    for (let i = this.sent.length - 1; i >= 0; i--) {
      const s = this.sent[i];
      s.t += dt;
      const k = s.t / SEND_S;
      if (k >= 1) {
        s.nodes.forEach((n) => this.release(n));
        this.sent.splice(i, 1);
        continue;
      }
      s.nodes.forEach((n, j) => {
        n.position.set(s.base[j].x, s.base[j].y + 0.5 * scale * easeOutCubic(k), s.base[j].z);
        n.material.opacity = 1 - k;
      });
    }

    for (let i = this.removed.length - 1; i >= 0; i--) {
      const r = this.removed[i];
      r.t += dt;
      const k = r.t / 0.2;
      if (k >= 1) {
        this.release(r.node);
        this.removed.splice(i, 1);
        continue;
      }
      this.size(r.node, r.glyph, unit * (1 - k));
      r.node.material.opacity = 1 - k;
    }
  }
}

const PLANE = new THREE.PlaneGeometry(1, 1);
