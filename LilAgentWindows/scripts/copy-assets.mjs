import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const native = path.resolve(root, '..', 'LilAgentMac', 'LilAgent');
const resources = path.join(native, 'Resources');
const settingsAssets = path.join(native, 'Assets.xcassets', 'Settings');
const lucide = path.join(root, 'node_modules', 'lucide-static', 'icons');

const copy = (from, to) => {
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
};

for (const model of ['clawd', 'codex', 'bed']) copy(path.join(resources, `${model}.glb`), path.join(root, 'public', 'models', `${model}.glb`));
for (const c of ['clawd', 'codex']) {
  copy(path.join(settingsAssets, `character-${c}.imageset`, `character-${c}.png`), path.join(root, 'public', 'characters', `${c}.png`));
}
copy(path.join(resources, 'trayTemplate.png'), path.join(root, 'assets', 'trayTemplate.png'));
copy(path.join(resources, 'trayTemplate@2x.png'), path.join(root, 'assets', 'trayTemplate@2x.png'));
for (const layer of ['card', 'logo', 'wordmark']) copy(path.join(resources, `splash-${layer}.svg`), path.join(root, 'public', 'splash', `${layer}.svg`));

const ICONS = [
  'settings', 'palette', 'smile', 'sparkles', 'command', 'download', 'rotate-ccw', 'pin', 'power', 'power-off', 'move-diagonal',
  'footprints', 'eye', 'moon', 'music', 'coffee', 'dumbbell', 'flower-2', 'lightbulb', 'star', 'cloud-rain', 'disc-3', 'hand',
  'mouse-pointer-click', 'tornado', 'bed', 'sun', 'brain', 'book-open', 'search', 'laptop', 'terminal', 'list-checks', 'users',
  'lock', 'message-circle-question', 'bell', 'fold-vertical', 'triangle-alert', 'circle-check', 'hourglass', 'link', 'keyboard',
  'mouse', 'x', 'slash', 'move', 'party-popper', 'check',
];
for (const name of ICONS) {
  const svg = fs.readFileSync(path.join(lucide, `${name}.svg`), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const target = path.join(root, 'public', 'icons', `${name}.svg`);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, svg);
}
copy(path.join(root, 'node_modules', 'lucide-static', 'LICENSE'), path.join(root, 'public', 'icons', 'LICENSE'));
console.log('assets copied');
