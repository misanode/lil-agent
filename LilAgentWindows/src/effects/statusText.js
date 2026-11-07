import * as THREE from 'three';
import { font, PALETTES } from './typedLetters.js';
import { STATUS_PHRASES, statusTextExtent, statusTextLayout, avoidStatusProps } from './statusTextLayout.js';

export class StatusText {
  constructor(scene) {
    this.material = new THREE.MeshBasicMaterial({ transparent: true, depthTest: false, depthWrite: false, toneMapped: false });
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), this.material);
    this.mesh.renderOrder = 11;
    this.mesh.visible = false;
    this.mesh.frustumCulled = false;
    scene.add(this.mesh);
    this.canvas = document.createElement('canvas');
    this.key = '';
    this.text = '';
    this.side = 1;
    this.opacity = 0;
  }

  draw(text, px, ratio, codex) {
    const ctx = this.canvas.getContext('2d');
    ctx.font = font(px * ratio);
    const lines = [];
    let line = '';
    for (const word of text.split(' ')) {
      const next = line ? `${line} ${word}` : word;
      if (line && ctx.measureText(next).width > 180 * ratio) {
        lines.push(line);
        line = word;
      } else line = next;
    }
    lines.push(line);
    const pad = Math.ceil(px * ratio * 0.4), step = px * ratio * 1.35;
    const width = Math.ceil(Math.max(...lines.map((line) => ctx.measureText(line).width)) + pad * 2);
    const height = Math.ceil(step * lines.length + pad * 2);
    this.canvas.width = width;
    this.canvas.height = height;
    ctx.font = font(px * ratio);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round';
    ctx.lineWidth = px * ratio * 0.16;
    const palette = codex ? PALETTES.codex : PALETTES.clawd;
    lines.forEach((line, i) => {
      const x = width / 2, y = pad + step * (i + 0.5) + px * ratio * 0.05;
      ctx.shadowColor = palette.shadow;
      ctx.shadowOffsetY = px * ratio * 0.05;
      ctx.shadowBlur = px * ratio * 0.1;
      ctx.strokeStyle = palette.rim;
      ctx.fillStyle = palette.rim;
      ctx.strokeText(line, x, y);
      ctx.fillText(line, x, y);
      ctx.shadowColor = 'transparent';
      ctx.strokeText(line, x, y);
      ctx.fillText(line, x, y);
      ctx.fillStyle = palette.fill;
      ctx.fillText(line, x, y);
    });
    this.material.map?.dispose();
    const texture = new THREE.CanvasTexture(this.canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.generateMipmaps = false;
    texture.minFilter = THREE.LinearFilter;
    this.material.map = texture;
    this.material.needsUpdate = true;
    this.width = width / ratio / 100;
    this.height = height / ratio / 100;
  }

  update(dt, pet) {
    const text = pet.settings.showStatusText === false ? '' : STATUS_PHRASES[pet.stateName] ?? '';
    this.mesh.visible = !!text;
    if (!text) { this.opacity = 0; this.text = ''; return; }
    const { scale, halfWidth, halfHeight } = pet.placement;
    const px = Math.round(Math.max(14, Math.min(24, 0.24 * scale * 100 * 0.6875)));
    const ratio = Math.min(3, window.devicePixelRatio || 1);
    const key = `${text}|${px}|${ratio}|${pet.mob.hasScreenFace}`;
    if (text !== this.text) { this.opacity = 0; this.text = text; }
    if (key !== this.key) { this.draw(text, px, ratio, pet.mob.hasScreenFace); this.key = key; }
    if (Math.abs(pet.loco.facing) > 0.12) this.side = Math.sign(pet.loco.facing);
    const inset = pet.mob.hasScreenFace ? 0.08 * scale : 0;
    let textHeight = 0.50 - (pet.stateName === 'command' ? 0.10 : 0);
    if (pet.stateName === 'permission' || pet.stateName === 'error') textHeight = 0.20;
    const extent = Math.max(0, statusTextExtent(pet.loco.x, pet.loco.facing, scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, pet.letters.cameraDistance) - inset);
    const base = statusTextLayout({
      x: pet.loco.x, y: pet.mob.root.position.y + pet.mob.height * scale * textHeight,
      extent, width: this.width, height: this.height, halfWidth, halfHeight, side: this.side,
    });
    const layout = avoidStatusProps(base, {
      width: this.width, height: this.height, halfWidth, halfHeight,
      obstacles: pet.mob.sidePropBounds?.(pet.letters.cameraDistance) ?? [],
      attachBelow: ['command', 'permission', 'error'].includes(pet.stateName),
    });
    this.mesh.visible = layout.scale > 0;
    this.mesh.position.set(layout.x, layout.y, 0);
    this.mesh.scale.set(this.width * layout.scale, this.height * layout.scale, 1);
    this.opacity = Math.min(1, this.opacity + dt / 0.15);
    this.material.opacity = this.opacity;
  }
}
