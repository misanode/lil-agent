import fs from 'node:fs';
import path from 'node:path';
import { app } from 'electron';

export const CHARACTERS = { clawd: 'Clawd', codex: 'Codex' };
export const SIZE_PRESETS = [['Tiny', 110], ['Small', 150], ['Medium', 210], ['Large', 290], ['Huge', 400]];
export const SIZE_RANGE = [80, 520];
export const DEFAULT_SIZE = 290;
export const DEFAULT_KEY_COLOR = '#7E6345';
const normalizeHex = (v) => (typeof v === 'string' && /^#?[0-9a-f]{6}$/i.test(v.trim()) ? `#${v.trim().replace('#', '').toUpperCase()}` : null);

export function clampSize(px) {
  const v = Number.isFinite(px) ? px : DEFAULT_SIZE;
  return Math.round(Math.min(SIZE_RANGE[1], Math.max(SIZE_RANGE[0], v)));
}

export const DEFAULTS = {
  petSize: DEFAULT_SIZE,
  sizes: {},
  disabled: [],
  autoWalk: true,
  lookAtCursor: true,
  walkSpeed: 1,
  idleSleepMin: 5,
  openAtLogin: false,
  keepOnTop: true,
  showInDock: true,
  showHideShortcut: true,
  showStatusText: true,
  agentReactions: true,
  musicDance: true,
  typeAlong: true,
  keyColor: DEFAULT_KEY_COLOR,
  home: null,
  character: 'clawd',
};

const file = () => path.join(app.getPath('userData'), 'settings.json');

function sanitize(raw) {
  const s = { ...DEFAULTS };
  for (const [k, def] of Object.entries(DEFAULTS)) {
    const v = raw?.[k];
    if (v === undefined) continue;
    if (k === 'home') s.home = v && Number.isFinite(v.x) && Number.isFinite(v.lift) ? { x: v.x, lift: v.lift } : null;
    else if (k === 'sizes') s.sizes = v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).filter(([, n]) => Number.isFinite(n))) : {};
    else if (k === 'disabled') s.disabled = Array.isArray(v) ? v.filter((x) => typeof x === 'string') : [];
    else if (k === 'keyColor') s.keyColor = normalizeHex(v) ?? DEFAULT_KEY_COLOR;
    else if (k === 'character') s.character = CHARACTERS[v] ? v : DEFAULTS.character;
    else if (typeof v === typeof def) s[k] = v;
  }
  s.petSize = clampSize(s.sizes[s.character] ?? s.petSize);
  s.sizes[s.character] = s.petSize;
  return s;
}

export class SettingsStore {
  constructor() {
    let raw = null;
    try {
      raw = JSON.parse(fs.readFileSync(file(), 'utf8'));
    } catch {}
    this.values = sanitize(raw);
    this.onChange = null;
    this.saveTimer = null;
  }

  update(change) {
    const old = structuredClone(this.values);
    const next = structuredClone(this.values);
    change(next);
    if (next.character !== old.character && CHARACTERS[next.character]) {
      next.sizes[old.character] = old.petSize;
      next.petSize = next.sizes[next.character] ?? DEFAULT_SIZE;
    }
    next.petSize = clampSize(next.petSize);
    next.sizes[next.character] = next.petSize;
    if (JSON.stringify(next) === JSON.stringify(old)) return;
    this.values = next;
    this.scheduleSave();
    this.onChange?.(old, next);
  }

  scheduleSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      try {
        fs.mkdirSync(path.dirname(file()), { recursive: true });
        const tmp = `${file()}.tmp`;
        fs.writeFileSync(tmp, JSON.stringify(this.values, null, 2));
        fs.renameSync(tmp, file());
      } catch (err) {
        console.log(`Couldn't save settings: ${err.message}`);
      }
    }, 300);
  }
}
