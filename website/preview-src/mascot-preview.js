// Website preview: runs Lil Agent's real mascot code (models, states,
// animation clips, props, face) inside a page element.
// Built into ../vendor/mascot-preview.js — see build.mjs.
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { ScreenSpace, Stage } from '../../LilAgentWindows/src/core/stage.js';
import { Pet } from '../../LilAgentWindows/src/character/pet.js';
import { Mascot } from '../../LilAgentWindows/src/model/mascot.js';
import { PointerDirector } from '../../LilAgentWindows/src/interaction/pointerDirector.js';

const MAX_DT = 1 / 20;
const loader = new GLTFLoader();
const buffers = new Map();

function fetchModel(base, name) {
  const url = new URL(`${name}.glb`, base).href;
  if (!buffers.has(url)) {
    buffers.set(url, fetch(url).then((r) => {
      if (!r.ok) throw new Error(`${r.status} loading ${url}`);
      return r.arrayBuffer();
    }));
  }
  return buffers.get(url).then((buf) => loader.parseAsync(buf.slice(0), url.slice(0, url.lastIndexOf('/') + 1)));
}

async function loadMascot(base, character) {
  const gltf = await fetchModel(base, character);
  let bed = null;
  if (gltf.scene.getObjectByProperty('name', 'face_eyes')) bed = await fetchModel(base, 'bed').catch(() => null);
  return new Mascot(gltf, bed);
}

/**
 * Mount a live mascot into `container`.
 * options: character ('clawd' | 'codex'), modelsBase (URL of the models folder),
 * size (pet height as a fraction of the container height), state (initial state),
 * interactive (pet / drag / throw with the app's pointer handling),
 * statusText (show the app's own status phrase above the pet).
 */
export async function mountMascot(container, options = {}) {
  const {
    character = 'clawd',
    modelsBase = new URL('assets/models/', document.baseURI).href,
    size = 0.8,
    state = 'idle',
    interactive = false,
    statusText = false,
    onReady,
  } = options;

  const stage = new Stage(container, { maxPixelRatio: 2 });
  const canvas = stage.renderer.domElement;
  canvas.style.cssText = 'display:block;width:100%;height:100%;touch-action:none;';
  const screen = new ScreenSpace(stage);
  const settings = { petSize: 200, autoWalk: false, walkSpeed: 1, showStatusText: statusText, typeAlong: false, agentReactions: true, disabled: [] };

  let sizeFrac = size;
  let mob = await loadMascot(modelsBase, character);
  stage.scene.add(mob.root);
  const pet = new Pet(mob, stage.scene, settings);
  pet.home = { x: 0, lift: 0 };

  const placement = () => {
    settings.petSize = Math.max(40, stage.height * sizeFrac);
    const scale = screen.scaleForPixels(settings.petSize);
    const facing = pet.loco.facing;
    const [minX, maxX] = screen.movementRange(scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, facing);
    const floorY = screen.floorY(scale, pet.mob.edgeHalfWidth, pet.mob.edgeHalfDepth, facing);
    const maxLift = interactive ? Math.max(0, (stage.height - 16) / screen.pixelsPerUnit - pet.mob.height * scale) : 0;
    pet.setPlacement({ scale, floorY, minX, maxX, halfWidth: screen.halfWidth, halfHeight: screen.halfHeight, maxLift });
    stage.setFocus(pet.loco.x, floorY, scale);
    stage.setShadowStrength(1 - pet.lift / (1.2 * scale));
  };

  let pointer = null;
  if (interactive) {
    pointer = new PointerDirector(pet, screen);
    pointer.size = () => settings.petSize;
    const local = (e) => {
      const r = canvas.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    };
    canvas.addEventListener('pointermove', (e) => pointer.move(...local(e)));
    canvas.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      canvas.setPointerCapture(e.pointerId);
      pointer.move(...local(e));
      pointer.down(...local(e));
    });
    const up = () => { pointer.up(); pet.home = { x: 0, lift: 0 }; pet.restLift = 0; };
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', up);
    canvas.addEventListener('pointerleave', () => pointer.leave());
  }

  const ro = new ResizeObserver(() => stage.resize());
  ro.observe(container);

  let visible = true;
  const io = new IntersectionObserver(([e]) => { visible = e.isIntersecting; }, { rootMargin: '100px' });
  io.observe(container);

  placement();
  pet.trigger(state, {}, true);
  await stage.renderer.compileAsync(stage.scene, stage.camera).catch(() => {});

  let last = performance.now();
  let frames = 0;
  let raf = 0;
  const frame = (t) => {
    const dt = Math.min(Math.max((t - last) / 1000, 0), MAX_DT);
    last = t;
    if (visible && !document.hidden) {
      placement();
      pointer?.update(dt);
      pet.letters.cameraDistance = stage.camera.position.z;
      pet.update(dt);
      stage.render();
      if (++frames === 4) onReady?.();
    }
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);

  let loadingCharacter = null;
  return {
    pet,
    get state() { return pet.stateName; },
    setState(name, params = {}) { return pet.trigger(name, params, true); },
    setSize(frac) { sizeFrac = frac; },
    async setCharacter(next) {
      loadingCharacter = next;
      const m = await loadMascot(modelsBase, next);
      if (loadingCharacter !== next) return m.dispose?.();
      pet.swapMob(m);
      mob = m;
    },
    dispose() {
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
      stage.renderer.dispose();
      canvas.remove();
    },
  };
}
