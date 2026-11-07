import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { ScreenSpace, Stage } from './core/stage.js';
import { Pet } from './character/pet.js';
import { Mascot } from './model/mascot.js';
import { AgentDirector } from './interaction/agentDirector.js';
import { PointerDirector } from './interaction/pointerDirector.js';
import { ACTIONS } from './character/states.js';

const api = window.pet;
const MAX_DT = 1 / 20;
const loader = new GLTFLoader();
const modelURL = (name) => new URL(`models/${name}.glb`, document.baseURI).href;

async function loadMascot(character) {
  const gltf = await loader.loadAsync(modelURL(character));
  let bed = null;
  const screenFace = gltf.scene.getObjectByProperty('name', 'face_eyes') ?? null;
  if (screenFace) bed = await loader.loadAsync(modelURL('bed')).catch(() => null);
  return new Mascot(gltf, bed);
}

async function main() {
  let settings = await api.getSettings();
  const debug = await api.getDebug();
  const stage = new Stage(document.getElementById('app'));
  const screen = new ScreenSpace(stage);
  let character = settings.character;
  const mob = await loadMascot(character);
  stage.scene.add(mob.root);
  const pet = new Pet(mob, stage.scene, settings);
  const pointer = new PointerDirector(pet, screen);
  const agent = new AgentDirector(pet, settings);
  let homeRestored = false;
  let centeredHome = false;
  let loading = null;
  let hidden = false;

  const applySettings = (s) => {
    settings = s;
    pet.settings = s;
    agent.settings = s;
    if (s.character !== character && s.character !== loading) switchCharacter(s.character);
  };

  async function switchCharacter(next) {
    loading = next;
    try {
      const m = await loadMascot(next);
      if (loading !== next) return m.dispose();
      loading = null;
      character = next;
      pet.swapMob(m);
    } catch (err) {
      console.log(`Couldn't load ${next}: ${err.message}`);
      loading = null;
    }
  }

  const canvas = stage.renderer.domElement;
  canvas.addEventListener('mousemove', (e) => pointer.move(e.clientX, e.clientY));
  canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) {
      pointer.move(e.clientX, e.clientY);
      pointer.down(e.clientX, e.clientY);
    }
  });
  window.addEventListener('mouseup', (e) => { if (e.button === 0) pointer.up(); });
  canvas.addEventListener('mouseleave', () => pointer.leave());
  canvas.addEventListener('wheel', (e) => pointer.wheel(e.deltaY), { passive: true });
  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (!pointer.dragging) api.openSettings(petOutline());
  });
  pointer.size = () => settings.petSize;
  pointer.onResize = (px) => api.setSettings({ petSize: px });
  pointer.onOverChange = (over) => api.setOver(over);
  pointer.onAirborneChange = (on) => api.setExpanded(on);

  api.onSettings(applySettings);
  api.onAgent((a) => agent.setAgent(a));
  api.onMusic((playing) => agent.setMusic(playing));
  api.onKey(({ code, ch }) => { if (!hidden) agent.onKey(ch, code); });
  api.onKeyUp((code) => agent.onKeyUp(code));
  api.onCursor((c) => { pointer.cursor = c; });
  api.onHidden((h) => { hidden = h; });
  api.onCommand((c) => {
    switch (c.type) {
      case 'trigger': trigger(c.name, c.surprised); break;
      case 'preview': agent.preview(c.name); break;
      case 'idleSleep': agent.setIdleAsleep(c.on); break;
      case 'resetPosition': {
        const home = centerHome();
        pet.home = home;
        pet.restLift = home.lift;
        centeredHome = true;
        pet.trigger('walk', { x: home.x, lift: home.lift }, true);
        break;
      }
      case 'petRect': api.reply(c.id, petOutline()); break;
    }
  });
  const initialAgent = await api.getAgent();
  if (initialAgent) agent.setAgent(initialAgent);

  function trigger(name, surprised) {
    if (name === 'wake' && agent.userTyping) return;
    if (name === 'wake' && surprised) pet.trigger('surprised', { then: 'wake' }, true);
    else if (name === 'wake') pet.trigger('wake', {}, true);
    else if (ACTIONS.includes(name)) pet.trigger(name, { then: 'idle' }, true);
  }

  const v = new THREE.Vector3();
  function petOutline() {
    const p = pet.mob.root.position;
    const s = pet.placement.scale, box = pet.mob.hitBox;
    const project = (x, y) => {
      v.set(x, y, p.z).project(stage.camera);
      return [(v.x + 1) / 2 * stage.width, (1 - v.y) / 2 * stage.height];
    };
    const [ax, ay] = project(p.x + box.minX * s, p.y);
    const [bx, by] = project(p.x + box.maxX * s, p.y + box.top * s);
    return { x: Math.min(ax, bx), y: Math.min(ay, by), width: Math.abs(bx - ax), height: Math.abs(by - ay) };
  }

  function updatePlacement() {
    const scale = screen.scaleForPixels(settings.petSize);
    const [minX, maxX] = screen.movementRange(scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, pet.loco.facing);
    const floorY = screen.floorY(scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, pet.loco.facing);
    const screenH = Math.max(window.screen.availHeight, stage.height);
    const maxLift = Math.max(0, (screenH - 24) / screen.pixelsPerUnit - pet.mob.height * scale);
    pet.setPlacement({ scale, floorY, minX, maxX, halfWidth: screen.halfWidth, halfHeight: screen.halfHeight, maxLift });
    stage.setFocus(pet.loco.x, floorY, scale);
    stage.setShadowStrength(1 - pet.lift / (1.2 * scale));
  }

  function centerHome() {
    const p = pet.placement;
    const floorOffset = p.floorY + screen.halfHeight;
    const lift = window.screen.availHeight / (2 * screen.pixelsPerUnit) - floorOffset - pet.mob.height * p.scale / 2;
    return { x: 0, lift: Math.min(p.maxLift, Math.max(0, lift)) };
  }

  function placeAtCenter() {
    const home = centerHome();
    pet.loco.x = home.x;
    pet.loco.targetX = home.x;
    pet.lift = home.lift;
    pet.restLift = home.lift;
    pet.home = home;
    centeredHome = true;
  }

  function followCenter() {
    const old = pet.home;
    if (!old) return;
    const home = centerHome();
    if (Math.abs(home.lift - old.lift) <= 0.01) return;
    if (Math.abs(pet.restLift - old.lift) < 0.01) pet.restLift = home.lift;
    pet.home = home;
  }

  function restoreHome() {
    homeRestored = true;
    const h = settings.home;
    if (debug.ignoreHome) return;
    if (!h) return placeAtCenter();
    const [minX, maxX] = screen.movementRange(pet.placement.scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, pet.loco.facing);
    const x = Math.min(maxX, Math.max(minX, screen.toWorldX(h.x * stage.width)));
    const lift = Math.max(0, h.lift / screen.pixelsPerUnit);
    pet.loco.x = x;
    pet.loco.targetX = x;
    pet.lift = lift;
    pet.restLift = lift;
    pet.home = { x, lift };
  }

  function saveHome() {
    pet.homeChanged = false;
    if (!pet.home) return;
    const x = pet.home.x / (2 * screen.halfWidth) + 0.5;
    const lift = Math.round(pet.home.lift * screen.pixelsPerUnit);
    api.setSettings({ home: { x, lift } });
  }

  if (debug.state) setTimeout(() => pet.trigger(debug.state, { loop: true }, true), 500);
  if (debug.then) setTimeout(() => pet.trigger(debug.then.state, {}, true), debug.then.at * 1000);
  if (debug.type) [...debug.type].forEach((ch, i) => setTimeout(() => agent.onKey(ch), 1000 + i * 120));

  await stage.renderer.compileAsync(stage.scene, stage.camera).catch(() => {});
  let lastState = '';
  let last = performance.now();
  let frames = 0;
  function frame(nowMs) {
    const dt = Math.min(Math.max((nowMs - last) / 1000, 0), MAX_DT);
    last = nowMs;
    if (!hidden) {
      updatePlacement();
      if (!homeRestored) restoreHome();
      if (centeredHome) followCenter();
      if (debug.center) { pet.loco.x = 0; pet.loco.targetX = 0; pet.loco.facing = 0; }
      pointer.update(dt);
      agent.update();
      if (pet.homeChanged) {
        centeredHome = false;
        saveHome();
      }
      pet.letters.cameraDistance = stage.camera.position.z;
      pet.update(dt);
      stage.render();
      if (pet.stateName !== lastState) {
        lastState = pet.stateName;
        api.setState(lastState);
      }
      if (++frames === 3) api.ready();
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

main().catch((err) => {
  console.error(err);
  api.fatal?.(String(err?.stack ?? err));
});
