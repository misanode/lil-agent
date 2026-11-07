import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

export const CAMERA_FOV = 28;
export const PIXELS_PER_UNIT = 100;
const FLOOR_OPACITY = 0.28;

export class Stage {
  constructor(container, { maxPixelRatio = 2 } = {}) {
    this.container = container;
    this.maxPixelRatio = maxPixelRatio;
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, premultipliedAlpha: true, powerPreference: 'high-performance', preserveDrawingBuffer: false });
    renderer.setClearColor(0x000000, 0);
    renderer.toneMapping = THREE.NeutralToneMapping;
    renderer.toneMappingExposure = 1.0;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    container.appendChild(renderer.domElement);
    this.renderer = renderer;

    this.scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    const environment = new RoomEnvironment();
    this.scene.environment = pmrem.fromScene(environment, 0.04).texture;
    environment.dispose();
    environment.traverse((object) => { if (object.isInstancedMesh) object.dispose(); });
    this.scene.environmentIntensity = 0.375;
    pmrem.dispose();

    this.camera = new THREE.PerspectiveCamera(CAMERA_FOV, 1, 0.1, 200);
    this.#createFloor();
    this.#createLights();
    this.resize = this.resize.bind(this);
    window.addEventListener('resize', this.resize);
    this.resize();
  }

  #createLights() {
    this.lightRig = new THREE.Group();
    this.scene.add(this.lightRig);
    this.focus = new THREE.Object3D();
    this.lightRig.add(this.focus);

    const key = new THREE.DirectionalLight(0xffffff, 2.6);
    key.position.set(-3.5, 6, 6);
    key.target = this.focus;
    key.castShadow = true;
    key.shadow.mapSize.set(2048, 2048);
    key.shadow.camera.near = 1;
    key.shadow.camera.far = 20;
    key.shadow.bias = -0.0004;
    key.shadow.normalBias = 0.02;
    key.shadow.radius = 6;
    this.lightRig.add(key);

    const fill = new THREE.DirectionalLight(0xdfe9ff, 0.4);
    fill.position.set(5, 2, 4);
    fill.target = this.focus;
    const rimL = new THREE.DirectionalLight(0x9fe8ff, 1.6);
    rimL.position.set(-5, 3, -5);
    rimL.target = this.focus;
    const rimR = new THREE.DirectionalLight(0x9fe8ff, 1.3);
    rimR.position.set(5, 4, -5);
    rimR.target = this.focus;
    this.lightRig.add(fill, rimL, rimR);
    this.lights = { key, fill, rimL, rimR };
    this.setFocus(0, 0, 1);
  }

  #createFloor() {
    this.floor = new THREE.Mesh(new THREE.PlaneGeometry(60, 20), new THREE.ShadowMaterial({ opacity: FLOOR_OPACITY, transparent: true }));
    this.floor.rotation.x = -Math.PI / 2;
    this.floor.receiveShadow = true;
    this.floor.renderOrder = -1;
    this.scene.add(this.floor);
  }

  setShadowStrength(k) { this.floor.material.opacity = FLOOR_OPACITY * Math.min(1, Math.max(0, k)); }

  setFocus(x, floorY, scale) {
    this.lightRig.position.set(x, floorY, 0);
    this.focus.position.set(0, 1.2 * scale, 0);
    this.floor.position.y = floorY;
    if (scale !== this.focusScale) {
      this.focusScale = scale;
      const cam = this.lights.key.shadow.camera;
      const r = 2.2 * scale;
      Object.assign(cam, { left: -r, right: r, top: r, bottom: -r });
      cam.updateProjectionMatrix();
    }
  }

  get width() { return this.container.clientWidth || window.innerWidth; }
  get height() { return this.container.clientHeight || window.innerHeight; }

  resize() {
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, this.maxPixelRatio));
    this.renderer.setSize(this.width, this.height);
    this.camera.aspect = this.width / this.height;
    const halfHeight = this.height / (2 * PIXELS_PER_UNIT);
    this.camera.position.set(0, 0, halfHeight / Math.tan(THREE.MathUtils.degToRad(CAMERA_FOV / 2)));
    this.camera.updateProjectionMatrix();
  }

  render() { this.renderer.render(this.scene, this.camera); }
}

export const PET_HEIGHT = 1.25;
const FLOOR_MARGIN_PX = 8;

export class ScreenSpace {
  constructor(stage) { this.stage = stage; }
  get pixelsPerUnit() { return PIXELS_PER_UNIT; }
  get halfHeight() { return this.stage.height / (2 * PIXELS_PER_UNIT); }
  get halfWidth() { return this.stage.width / (2 * PIXELS_PER_UNIT); }
  heightAboveFloor(py, floorY) { return this.toWorldY(py) - floorY; }
  scaleForPixels(px) { return px / (PET_HEIGHT * PIXELS_PER_UNIT); }
  toWorldX(px) { return (px / this.stage.width - 0.5) * 2 * this.halfWidth; }
  toWorldY(py) { return (0.5 - py / this.stage.height) * 2 * this.halfHeight; }

  floorY(scale, halfWidth, halfDepth, facing) {
    const d = this.stage.camera.position.z;
    const near = (Math.abs(Math.sin(facing)) * halfWidth + Math.abs(Math.cos(facing)) * halfDepth) * scale;
    return (-this.halfHeight + FLOOR_MARGIN_PX / PIXELS_PER_UNIT) * ((d - near) / d);
  }

  movementRange(scale, halfWidth, halfDepth, facing) {
    const edge = Math.max(0, this.halfWidth - FLOOR_MARGIN_PX / PIXELS_PER_UNIT);
    const d = this.stage.camera.position.z;
    const c = Math.cos(facing), s = Math.sin(facing);
    let lo = -Infinity, hi = Infinity;
    for (const x of [-halfWidth, halfWidth]) {
      for (const z of [-halfDepth, halfDepth]) {
        const px = (c * x + s * z) * scale;
        const pz = (-s * x + c * z) * scale;
        const limit = edge * (1 - pz / d);
        lo = Math.max(lo, -limit - px);
        hi = Math.min(hi, limit - px);
      }
    }
    if (lo > hi) lo = hi = 0;
    return [lo, hi];
  }
}
