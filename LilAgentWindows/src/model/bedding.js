import * as THREE from 'three';

const COMMON =            `
uniform vec3 offs;
uniform vec3 hC;
uniform vec3 hR;
uniform vec3 bC;
uniform vec3 bR;
uniform vec3 lC;
uniform vec3 lR;
uniform float uOn;
uniform float floorY;
uniform float puff;
uniform float reveal;
`;

export const dentShader = {
  key: 'lilagent-bed-dent',
  functions:            `
void bedPress(vec3 p, vec3 c, vec3 r, inout float depth, inout float rim, inout vec3 best) {
  vec2 q = (p.xz - c.xz) / r.xz;
  float s = 1.0 - dot(q, q);
  float bottom = c.y - r.y * sqrt(max(s, 0.0));
  float d = s > 0.0 ? max(0.0, p.y - bottom) : 0.0;
  float u = sqrt(dot(q, q));
  rim = max(rim, smoothstep(0.95, 1.12, u) * (1.0 - smoothstep(1.12, 1.6, u)) * step(c.y - r.y, p.y + 0.6));
  if (d > depth) { depth = d; best = c; }
}
`,
  normal:            `
vec3 bedP = position + offs;
float bedDepth = 0.0;
float bedRim = 0.0;
vec3 bedBest = vec3(0.0);
bedPress(bedP, hC, hR, bedDepth, bedRim, bedBest);
bedPress(bedP, bC, bR, bedDepth, bedRim, bedBest);
bedPress(bedP, lC, lR, bedDepth, bedRim, bedBest);
float bedUp = clamp(normal.y, 0.0, 1.0);
float bedDy = -min(bedDepth, max(0.0, bedP.y - floorY)) * uOn + puff * bedRim * bedUp * uOn * step(bedDepth, 0.0001);
if (bedDepth > 0.0 && uOn > 0.0) {
  vec3 inward = normalize(bedBest - vec3(bedP.x, bedP.y + bedDy, bedP.z));
  objectNormal = normalize(mix(objectNormal, inward, 0.75 * uOn * bedUp));
}
`,
  position:            `
transformed.y += bedDy;
`,
};

export const blanketShader = {
  key: 'lilagent-bed-blanket',
  functions:            `
float bedTent(vec2 xz, vec3 c, vec3 r, float spread, float base) {
  float u = length((xz - c.xz) / r.xz);
  if (u < 1.0) return c.y + r.y * sqrt(1.0 - u * u);
  float f = 1.0 - smoothstep(1.0, 1.0 + spread, u);
  return mix(base, c.y, f * f);
}
float bedBase(float z) {
  float a = abs(z);
  float top = 0.65;
  if (a <= 1.75) return top;
  float t = min(1.0, (a - 1.75) / 0.3);
  return top - (top - 0.34) * (1.0 - (1.0 - t) * (1.0 - t));
}
float bedHeight(vec2 xz) {
  float base = bedBase(xz.y);
  float t = max(bedTent(xz, bC, bR, 0.9, base), bedTent(xz, lC, lR, 0.9, base));
  float h = t + 0.07;
  float k = 0.12;
  float m = clamp(0.5 + 0.5 * (h - base) / k, 0.0, 1.0);
  float y = mix(base, h, m) + k * m * (1.0 - m);
  return y + 0.022 * sin(xz.x * 6.0 + xz.y * 1.7);
}
`,
  normal:            `
vec3 bedP = position + offs;
float bedX = min(bedP.x + (1.0 - reveal) * 1.41, 1.55);
vec2 bedXZ = vec2(bedX, bedP.z);
float bedE = 0.03;
float bedH = bedHeight(bedXZ);
float bedHx = bedHeight(bedXZ + vec2(bedE, 0.0)) - bedHeight(bedXZ - vec2(bedE, 0.0));
float bedHz = bedHeight(bedXZ + vec2(0.0, bedE)) - bedHeight(bedXZ - vec2(0.0, bedE));
vec3 bedN = normalize(vec3(-bedHx / (2.0 * bedE), 1.0, -bedHz / (2.0 * bedE)));
if (normal.y > 0.4) objectNormal = bedN;
else if (normal.y < -0.4) objectNormal = -bedN;
`,
  position:            `
transformed = vec3(bedX, bedH + (bedP.y - 0.62), bedP.z) - offs;
`,
};

export function reactive(material, shader, { offs, floorY, puff }) {
  const m = material.clone();
  const u = {
    offs: { value: offs.clone() },
    hC: { value: new THREE.Vector3(0, 50, 0) }, hR: { value: new THREE.Vector3(0.01, 0.01, 0.01) },
    bC: { value: new THREE.Vector3(0, 50, 0) }, bR: { value: new THREE.Vector3(0.01, 0.01, 0.01) },
    lC: { value: new THREE.Vector3(0, 50, 0) }, lR: { value: new THREE.Vector3(0.01, 0.01, 0.01) },
    uOn: { value: 0 }, floorY: { value: floorY }, puff: { value: puff }, reveal: { value: 0 },
  };
  m.userData.bed = u;
  m.onBeforeCompile = (s) => {
    Object.assign(s.uniforms, u);
    s.vertexShader = s.vertexShader
      .replace('#include <common>', `#include <common>\n${COMMON}\n${shader.functions}`)
      .replace('#include <beginnormal_vertex>', `#include <beginnormal_vertex>\n${shader.normal}`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>\n${shader.position}`);
  };
  m.customProgramCacheKey = () => shader.key;
  return m;
}
