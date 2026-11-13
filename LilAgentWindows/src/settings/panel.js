const api = window.panel;
let state = null;
let tab = 'general';

const TABS = [
  ['general', 'General', 'settings'],
  ['character', 'Character', 'palette'],
  ['moods', 'Moods', 'smile'],
  ['agents', 'Agents', 'sparkles'],
  ['keybinds', 'Keybinds', 'command'],
];

const MOODS = [
  ['Coffee break', 'coffee', 'coffee'], ['Workout', 'workout', 'dumbbell'], ['Meditate', 'meditate', 'flower-2'],
  ['Bright idea', 'idea', 'lightbulb'], ['Happy', 'happy', 'smile'], ['Excited', 'excited', 'star'], ['Curious', 'curious', 'eye'],
  ['Sad', 'sad', 'cloud-rain'], ['Dance', 'dance', 'party-popper'], ['Wave', 'wave', 'hand'],
  ['Annoyed (lots of clicks)', 'annoyed', 'mouse-pointer-click'], ['Dizzy (thrown)', 'dizzy', 'tornado'],
];
const SLEEP = [['Sleepy', 'sleepy', 'moon'], ['Asleep', 'sleep', 'bed'], ['Waking up', 'wake', 'sun']];
const REACTIONS = [
  ['Thinking', 'thinking', 'brain'], ['Reading a file', 'reading', 'book-open'], ['Searching', 'searching', 'search'],
  ['Editing (laptop)', 'typing', 'laptop'], ['Running a command', 'command', 'terminal'], ['Planning', 'planning', 'list-checks'],
  ['Sending out helpers', 'subagents', 'users'], ['Needs your permission', 'permission', 'lock'],
  ['Asking a question', 'question', 'message-circle-question'], ['Needs your attention', 'attention', 'bell'],
  ['Compacting', 'compacting', 'fold-vertical'], ['Something failed', 'error', 'triangle-alert'], ['Done', 'done', 'circle-check'],
  ['Waiting for you', 'waiting', 'hourglass'],
];
const IDLE_CHOICES = [['Never', 0], ['After 30 s', 0.5], ['After 5 min', 5], ['After 15 min', 15], ['After 25 min', 25]];
const SIZE_PRESETS = [['Tiny', 110], ['Small', 150], ['Medium', 210], ['Large', 290], ['Huge', 400]];
const SIZE_RANGE = [80, 520];
const CHARACTERS = [['clawd', 'Clawd'], ['codex', 'Codex']];
const KEY_COLORS = [
  ['Mocha', '#7E6345'], ['Clay', '#C9603A'], ['Ocean', '#4062E0'], ['Forest', '#3F7D4E'],
  ['Plum', '#7A4A8C'], ['Rose', '#C2556F'], ['Graphite', '#4A4A4F'],
];


function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style') Object.assign(el.style, v);
    else if (k.startsWith('on')) el.addEventListener(k.slice(2).toLowerCase(), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}
const ICON_SVGS = import.meta.glob('/public/icons/*.svg', { query: '?raw', import: 'default', eager: true });
const iconURL = (name) => `url("data:image/svg+xml;utf8,${encodeURIComponent(ICON_SVGS[`/public/icons/${name}.svg`] ?? '')}")`;
const icon = (name, cls = '') => {
  const url = iconURL(name);
  return h('span', { class: `ico ${cls}`, style: { webkitMaskImage: url, maskImage: url }, 'aria-hidden': 'true' });
};
const label = (text) => h('span', { class: 'label' }, text);
const header = (text) => h('div', { class: 'header', role: 'heading' }, text);
const note = (text, error = false) => h('div', { class: `note${error ? ' error' : ''}` }, text);
const gap = (px) => h('div', { class: 'gap', style: { flexGrow: String(px), flexBasis: `${px}px` } });
const space = (px) => h('div', { style: { height: `${px}px`, flex: 'none' } });

function toggle(title, on, set) {
  return h('button', { class: `switch${on ? ' on' : ''}`, role: 'switch', 'aria-checked': String(on), 'aria-label': title, onClick: () => set(!on) });
}
const outline = (text, onClick, { width = 52.5, disabled = false, selected = false, title } = {}) =>
  h('button', { class: `outline${selected ? ' selected' : ''}`, style: { minWidth: `${width}px` }, disabled, 'aria-label': title ?? text, onClick }, text);

function row(iconName, text, ...controls) {
  return h('div', { class: 'row' }, icon(iconName), label(text), h('div', { class: 'spacer' }), h('div', { class: 'controls' }, ...controls));
}

const v = () => state.values;
const change = (patch) => api.change(patch);
const allows = (s) => !v().disabled.includes(s);


function versionText() {
  const u = state.update;
  const base = `${state.appName} version ${state.version}`;
  return u?.status === 'available' ? `${base} (${u.latest} is out)` : base;
}

function updateButton() {
  const u = state.update ?? { status: 'idle' };
  if (u.status === 'available') return outline('Update Available', () => api.openUpdate(), { selected: true, title: u.automatic ? `Download and install ${state.appName} ${u.latest}, then restart` : `Download ${state.appName} ${u.latest}` });
  if (u.status === 'downloading') return outline(`Downloading ${u.percent}%`, () => {}, { disabled: true });
  if (u.status === 'downloaded') return outline('Restart to Update', () => api.openUpdate(), { selected: true });
  if (u.status === 'installing') return outline('Installing…', () => {}, { disabled: true });
  if (u.status === 'failed' && u.latest && u.operation !== 'check') return outline('Try Again', () => api.openUpdate(), { title: u.error ?? 'Try the update again' });
  if (u.status === 'checking') return outline('Checking…', () => {}, { disabled: true });
  if (u.status === 'current') return outline('Up to Date', () => api.checkUpdates(), { title: 'Up to date. Check for updates again' });
  if (u.status === 'failed') return outline('Try Again', () => api.checkUpdates(), { title: u.error ?? 'Couldn’t check for updates. Try again' });
  return outline('Check', () => api.checkUpdates(), { title: 'Check for updates' });
}

function general() {
  const s = v();
  return h('div', { class: 'page spread', style: { padding: '0 43px 0 38px' } },
    gap(47), header('Updates'),
    gap(20), row('download', versionText(), updateButton()),
    gap(20), header('Behavior'),
    gap(16), row('rotate-ccw', 'Reset Position', outline('Reset', () => api.resetPosition(), { title: 'Reset the mascot’s position' })),
    gap(21), row('pin', 'Keep on top of all windows', toggle('Keep on top of all windows', s.keepOnTop, (on) => change({ keepOnTop: on }))),
    gap(16), row('eye', 'Show mascot text', toggle('Show mascot text', s.showStatusText, (on) => change({ showStatusText: on }))),
    state.platform === 'darwin' ? gap(16) : null,
    state.platform === 'darwin' ? row('dock', 'Show in Dock', toggle('Show in Dock', s.showInDock, (on) => change({ showInDock: on }))) : null,
    gap(23.5), header('Startup'),
    gap(16.5), row(s.openAtLogin ? 'power' : 'power-off', `${state.appName} will automatically open at login`,
      toggle('Open at login', s.openAtLogin, (on) => change({ openAtLogin: on }))),
    gap(23), h('button', { class: 'quit', 'aria-label': `Quit ${state.appName}`, onClick: () => api.quit() }, icon('power-off'), label('Quit')),
    gap(17.5));
}

function character() {
  const s = v();
  const fill = ((s.petSize - SIZE_RANGE[0]) / (SIZE_RANGE[1] - SIZE_RANGE[0])) * 100;
  const slider = h('input', {
    type: 'range', min: SIZE_RANGE[0], max: SIZE_RANGE[1], value: s.petSize, 'aria-label': 'Size', style: { '--fill': `${fill}%` },
    onInput: (e) => change({ petSize: Number(e.target.value) }),
  });
  return h('div', { class: 'page spread', style: { padding: '0 30px' } },
    gap(26.5), header('Character'),
    gap(12), h('div', { class: 'characters' }, CHARACTERS.map(([key, title]) => {
      const selected = s.character === key;
      return h('button', { class: `character${selected ? ' selected' : ''}`, 'aria-label': title, 'aria-pressed': String(selected), onClick: () => change({ character: key }) },
        label(title), h('img', { src: `characters/${key}.png`, alt: '' }), h('span', { class: 'check' }, icon('check')));
    })),
    gap(24), header('Size'),
    gap(14), row('move-diagonal', `${s.petSize} px`, slider),
    gap(14), h('div', { class: 'presets' }, SIZE_PRESETS.map(([name, px]) => outline(name, () => change({ petSize: px }), { width: 44, selected: s.petSize === px }))),
    gap(14), note('Each character keeps its own size. You can also scroll over the mascot to resize it.'),
    gap(18), gap(24.5));
}

function activity([title, stateName, iconName], canDisable = true) {
  return h('div', {}, row(iconName, title,
    outline('Preview', () => api.preview(stateName), { title: `Preview ${title}` }),
    canDisable ? toggle(title, allows(stateName), (on) => api.allow(stateName, on)) : h('span', { style: { width: '38.5px' } })), space(10));
}

function moods() {
  const s = v();
  const asleep = state.asleep;
  const idle = h('select', { class: 'outline', style: { minWidth: '86px' }, 'aria-label': 'Falls asleep when you’re away', onChange: (e) => change({ idleSleepMin: Number(e.target.value) }) },
    IDLE_CHOICES.map(([t, m]) => h('option', { value: m, selected: s.idleSleepMin === m }, t)));
  return h('div', { class: 'page list' },
    header('Right Now'), space(14),
    h('div', { style: { display: 'flex', gap: '8px' } },
      outline(asleep ? 'Wake up' : 'Go to sleep', () => api.command(asleep ? 'wake' : 'sleepy'), { width: 70 }),
      outline('Wave', () => api.command('wave'), { disabled: asleep }),
      outline('Dance', () => api.command('dance'), { disabled: asleep })),
    space(24), header('Behavior'), space(14),
    row('footprints', 'Wanders around the screen', toggle('Wanders around', s.autoWalk, (on) => change({ autoWalk: on }))), space(12),
    row('eye', 'Looks at your cursor', toggle('Looks at your cursor', s.lookAtCursor, (on) => change({ lookAtCursor: on }))), space(12),
    row('moon', 'Falls asleep when you’re away', idle), space(12),
    row('music', 'Dances while Spotify or Apple Music plays', toggle('Dance to music', s.musicDance, (on) => change({ musicDance: on }))),
    space(24), header('Moods'), space(6),
    note('Things he does by himself now and then. Turn any off and he won’t.'), space(12),
    MOODS.map((m) => activity(m)),
    space(14), header('Sleep'), space(12),
    SLEEP.map((m) => activity(m, false)));
}

function agents() {
  const s = v();
  const connection = (name, connected, which) => row(connected ? 'circle-check' : 'link', connected ? `${name} is connected` : `${name} isn’t connected`,
    outline(connected ? 'Disconnect' : 'Connect…', () => api.hooks(which), { width: 80, title: connected ? `Disconnect ${name}` : `Connect ${name}` }));
  return h('div', { class: 'page list' },
    header('Connections'), space(14),
    connection('Claude Code', state.claudeConnected, 'claude'), space(12),
    connection('Codex', state.codexConnected, 'codex'), space(10),
    note(state.agentStatus), space(22),
    header('Behavior'), space(14),
    row('sparkles', 'Reacts to Claude Code and Codex', toggle('React to Claude Code and Codex', s.agentReactions, (on) => change({ agentReactions: on }))), space(12),
    row('keyboard', 'Types along with your keyboard', toggle('Type along', s.typeAlong, (on) => change({ typeAlong: on }))), space(12),
    h('div', { class: `row${s.typeAlong ? '' : ' dimmed'}` }, icon('palette'), label('Key color'), h('div', { class: 'spacer' }), keyColors(s.keyColor)), space(8),
    state.typingNote ? h('div', { class: 'row' }, note(state.typingNote, true), h('div', { class: 'spacer' }),
      state.platform === 'darwin' ? outline('Open Settings', () => api.permissions(), { width: 80 }) : null) : null,
    space(14), header('Reactions'), space(6),
    note('What he acts out while an agent works. Turn any off and he ignores it.'), space(12),
    REACTIONS.map((r) => activity(r)));
}

function keyColors(current) {
  const swatches = KEY_COLORS.map(([name, hex]) => h('button', {
    class: `swatch${current === hex ? ' selected' : ''}`, style: { background: hex }, title: name,
    'aria-label': `${name} keys`, 'aria-pressed': String(current === hex), onClick: () => change({ keyColor: hex }),
  }));
  const custom = h('input', {
    type: 'color', class: 'swatch-custom', value: current.toLowerCase(), title: 'Custom color', 'aria-label': 'Custom key color',
    onChange: (e) => change({ keyColor: e.target.value.toUpperCase() }),
  });
  return h('div', { class: 'swatches' }, swatches, custom);
}

function keybinds() {
  const mac = state.platform === 'darwin';
  const mouse = (iconName, text, result) => h('div', { class: 'row mouserow' }, icon(iconName), label(text), h('div', { class: 'spacer' }), h('span', { class: 'result' }, result));
  return h('div', { class: 'page spread', style: { padding: '0 40px 0 29.5px' } },
    gap(29), header('Mascot'),
    gap(15), h('div', { class: 'row keyrow', role: 'group', 'aria-label': `Show or hide the mascot: ${state.shortcutLabel}` },
      icon('eye'), label('Show or hide the mascot'), h('div', { class: 'spacer' }),
      h('div', { class: 'keys', 'aria-hidden': 'true' },
        mac ? icon('command') : h('span', { class: 'key' }, 'Ctrl'),
        h('span', { class: 'plus' }, '+'),
        icon('slash', 'mirror')),
      toggle('Enable show/hide shortcut', v().showHideShortcut, (on) => change({ showHideShortcut: on }))),
    state.shortcutErrors.map((e) => [gap(8), note(e, true)]),
    gap(36), header('Mouse'),
    gap(14), mouse('mouse-pointer-click', 'Right-click the mascot', 'Settings'),
    gap(14), mouse('move', 'Drag the mascot', 'Carry or throw'),
    gap(14), mouse('hand', 'Click the mascot', 'Pet it'),
    gap(14), mouse('mouse', 'Scroll over the mascot', 'Resize'),
    gap(29));
}


const PAGES = { general, character, moods, agents, keybinds };
let scrollTops = {};

function render() {
  if (!state) return;
  const root = document.getElementById('panel');
  const oldPage = root.querySelector('.page');
  if (oldPage) scrollTops[tab] = oldPage.scrollTop;
  root.replaceChildren(
    h('div', { class: 'titlebar' },
      h('div', { class: 'title', role: 'heading' }, `${state.appName} Settings`),
      h('button', { class: 'close', 'aria-label': 'Close', onClick: () => api.close() }, icon('x'))),
    h('nav', { class: 'tabs', role: 'tablist' }, TABS.map(([key, title, iconName]) =>
      h('button', { class: `tab${tab === key ? ' selected' : ''}`, role: 'tab', 'aria-selected': String(tab === key), onClick: () => { tab = key; render(); } },
        h('span', { class: 'tile' }, icon(iconName)), h('span', { class: 'caption' }, title)))),
    h('main', { class: 'card' }, PAGES[tab]()));
  const page = root.querySelector('.page');
  if (page && scrollTops[tab]) page.scrollTop = scrollTops[tab];
}

document.addEventListener('keydown', (e) => { if (e.key === 'Escape') api.close(); });
api.onState((s) => { state = s; render(); });
api.onTab((t) => { tab = t; render(); });
api.get().then((s) => {
  state = s;
  render();
  requestAnimationFrame(() => requestAnimationFrame(() => api.ready()));
});
