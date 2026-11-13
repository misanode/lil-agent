import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { app, BrowserWindow, dialog, globalShortcut, ipcMain, Menu, nativeImage, nativeTheme, net, powerMonitor, screen, shell, Tray } from 'electron';
import { APP_ID, APP_NAME, UPDATE_REPO } from '../brand.js';
import { CHARACTERS, SIZE_PRESETS, SettingsStore, clampSize } from './settings.js';
import { WORKING, startAgentBridge } from './agentBridge.js';
import { claudeHooks, codexHooks } from './hooks.js';
import { startMusicWatcher } from './musicWatcher.js';
import { startKeyWatcher } from './keyWatcher.js';
import { createSplash } from './splash.js';
import { createStartup } from './startup.js';
import { createUpdateChecker } from './updates.js';
import { createAutomaticUpdates } from './automaticUpdates.js';
import { createPanelPresentation } from './panelPresentation.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEV_URL = process.env.VITE_DEV_SERVER_URL;
const STRIP_HEIGHT_RATIO = 2.6;
const IDLE_POLL_S = 5;
const AWAY_WHILE_WAITING = 30 * 60;
const ASLEEP = new Set(['sleep', 'sleepy']);
const AGENT_BUSY = new Set([...WORKING, 'attention', 'permission', 'question']);
const SIZE_STEP = 1.15;
const SHORTCUT = 'CommandOrControl+\\';
const SHORTCUT_LABEL = process.platform === 'darwin' ? '⌘\\' : 'Ctrl+\\';
const STARTUP_LIMIT_MS = 60_000;
const ASSETS = path.join(__dirname, '..', 'assets');
const STATUS = {
  attention: 'Claude needs you', permission: 'Claude needs your permission', question: 'Claude has a question',
  thinking: 'Claude is thinking', typing: 'Claude is writing', reading: 'Claude is reading', searching: 'Claude is searching',
  command: 'Claude is running a command', planning: 'Claude is planning', subagents: 'Claude sent out helpers',
  compacting: 'Claude is compacting', error: 'Something failed', waiting: 'Claude is waiting for you', idle: 'Claude is idle',
};
const DEBUG = {
  state: process.env.LILAGENT_STATE,
  type: process.env.LILAGENT_TYPE,
  ignoreHome: !!process.env.LILAGENT_IGNORE_HOME,
  center: !!process.env.LILAGENT_CENTER,
  then: process.env.LILAGENT_THEN ? { state: process.env.LILAGENT_THEN.split('@')[0], at: Number(process.env.LILAGENT_THEN.split('@')[1]) } : null,
  noKeys: !!process.env.LILAGENT_NO_KEYS,
  character: process.env.LILAGENT_CHARACTER,
  size: Number(process.env.LILAGENT_SIZE) || null,
  snapshot: process.env.LILAGENT_SNAPSHOT,
  snapshotAfter: Number(process.env.LILAGENT_SNAPSHOT_AFTER) || 4,
  film: process.env.LILAGENT_FILM,
  filmAt: (process.env.LILAGENT_FILM_AT ?? '1,0.25,12').split(',').map(Number),
  settingsShot: process.env.LILAGENT_SETTINGS_SHOT,
  splashFilm: process.env.LILAGENT_SPLASH_FILM,
  splashFilmAt: (process.env.LILAGENT_SPLASH_FILM_AT ?? '0,0.05,24').split(',').map(Number),
  failStartup: !!process.env.LILAGENT_FAIL_STARTUP,
};
const testing = !!(DEBUG.snapshot || DEBUG.film || DEBUG.settingsShot || DEBUG.splashFilm);

app.setName(APP_NAME);
if (process.platform === 'darwin') app.setPath('userData', path.join(app.getPath('appData'), `${APP_NAME} (Electron)`));
if (process.platform === 'win32') app.setAppUserModelId(APP_ID);
const primary = testing || app.requestSingleInstanceLock();
if (!primary) {
  console.log(`${APP_NAME} is already running. Quitting this copy.`);
  app.quit();
}

const store = new SettingsStore();
if (DEBUG.character && CHARACTERS[DEBUG.character]) store.values.character = DEBUG.character;
if (DEBUG.size) store.values.petSize = clampSize(DEBUG.size);
let win = null;
let settingsWin = null;
let settingsPresentation = null;
let tray = null;
let petState = 'boot';
let idleSleeping = false;
let expanded = false;
let hidden = false;
let agent = null;
let music = null;
let keys = null;
let shortcutErrors = [];
let cursorTimer = null;
let splash = null;
let startup = null;
let startupTimer = null;
let startupFinished = false;
const automaticUpdates = process.platform === 'win32' && app.isPackaged && !testing && !process.env.LILAGENT_UPDATE_REPO;
const onUpdateChange = () => {
  buildTray();
  settingsWin?.webContents.send('panel:state', panelState());
};
const updates = automaticUpdates ? createAutomaticUpdates({
  updater: createRequire(import.meta.url)('electron-updater').autoUpdater,
  onChange: onUpdateChange,
}) : createUpdateChecker({
  current: app.getVersion(),
  repo: process.env.LILAGENT_UPDATE_REPO || UPDATE_REPO,
  userAgent: APP_NAME.replace(/\s+/g, '-'),
  fetch: (url, options) => net.fetch(url, options),
  onChange: onUpdateChange,
});
const replies = new Map();
let replyId = 0;

const send = (channel, payload) => win?.webContents.send(channel, payload);
const command = (type, extra = {}) => send('command', { type, ...extra });
function ask(type, timeoutMs = 300) {
  return new Promise((resolve) => {
    const id = ++replyId;
    replies.set(id, resolve);
    command(type, { id });
    setTimeout(() => { if (replies.delete(id)) resolve(null); }, timeoutMs);
  });
}


function display() { return screen.getPrimaryDisplay(); }

function stripBounds() {
  const { workArea } = display();
  const height = expanded ? workArea.height : Math.min(workArea.height, Math.round(store.values.petSize * STRIP_HEIGHT_RATIO));
  return { x: workArea.x, y: workArea.y + workArea.height - height, width: workArea.width, height };
}

function applyLevel() {
  if (!win) return;
  if (store.values.keepOnTop) win.setAlwaysOnTop(true, process.platform === 'darwin' ? 'floating' : 'screen-saver');
  else win.setAlwaysOnTop(false);
}

function createWindow() {
  win = new BrowserWindow({
    ...stripBounds(),
    transparent: true,
    frame: false,
    hasShadow: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    focusable: false,
    skipTaskbar: true,
    acceptFirstMouse: true,
    hiddenInMissionControl: true,
    show: false,
    backgroundColor: '#00000000',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false,
    },
  });
  applyLevel();
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.setIgnoreMouseEvents(true, { forward: true });
  win.on('closed', () => (win = null));
  win.webContents.on('render-process-gone', (_e, details) => startup?.fail(`The pet stopped while starting (${details.reason}).`));
  win.webContents.on('did-fail-load', (_e, code, desc, _url, isMainFrame) => { if (isMainFrame) startup?.fail(`The pet couldn't load (${desc || code}).`); });
  if (testing) win.webContents.on('console-message', (e) => { if (e.level !== 'info' && e.level !== 'debug') console.log(`[renderer ${e.level}] ${e.message}`); });
  if (DEV_URL) win.loadURL(DEV_URL);
  else win.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
}


function settingsChanged(old, next) {
  if (old.showHideShortcut !== next.showHideShortcut) syncShowHideShortcut();
  send('settings', next);
  settingsWin?.webContents.send('panel:state', panelState());
  if (old.petSize !== next.petSize) win?.setBounds(stripBounds());
  if (old.typeAlong !== next.typeAlong) keys?.sync(next.typeAlong && !DEBUG.noKeys);
  if (old.musicDance !== next.musicDance) music?.poll();
  if (old.keepOnTop !== next.keepOnTop) {
    applyLevel();
    keepMascotInFront();
  }
  if (old.showInDock !== next.showInDock) {
    syncDock();
    if (settingsWin?.isVisible()) setTimeout(() => { settingsWin?.show(); settingsWin?.focus(); }, 0);
  }
  if (old.openAtLogin !== next.openAtLogin && app.isPackaged) app.setLoginItemSettings({ openAtLogin: next.openAtLogin });
  buildTray();
}
store.onChange = settingsChanged;

function syncDock() {
  if (!app.dock) return;
  if (store.values.showInDock) app.dock.show();
  else app.dock.hide();
}

function setAppMenu() {
  if (process.platform !== 'darwin') return;
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: APP_NAME,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { label: 'Settings…', accelerator: 'Command+,', click: () => showSettingsBesideMascot() },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    { role: 'editMenu' },
  ]));
}

function syncShowHideShortcut() {
  globalShortcut.unregister(SHORTCUT);
  shortcutErrors = [];
  if (testing || !store.values.showHideShortcut) return;
  if (!globalShortcut.register(SHORTCUT, () => {
    if (store.values.showHideShortcut) toggleMascot();
  })) shortcutErrors = [`${SHORTCUT_LABEL} is unavailable; another app may be using it.`];
}

function agentStatusLabel() {
  if (!agent?.listening) return 'Agents: not listening';
  const a = agent.current;
  const name = a.provider === 'codex' ? 'Codex' : 'Claude';
  const label = a.provider == null ? 'Agents are idle' : (STATUS[a.activity] ?? 'Claude is idle').replace('Claude', name);
  return label + (a.project ? ` · ${a.project}` : '');
}


async function toggleHooks(which) {
  const hooks = which === 'codex' ? codexHooks : claudeHooks;
  const installed = hooks.installed();
  const name = which === 'codex' ? 'Codex' : 'Claude Code';
  try {
    if (installed) hooks.uninstall(); else hooks.install();
    const detail = which === 'codex'
      ? (installed ? 'Restart open Codex sessions to reload the hook configuration.'
        : 'Open /hooks in Codex CLI to review and trust the hooks, then start a new session. Hooks must be enabled in Codex.')
      : 'Restart any Claude Code sessions that are already open.';
    const message = installed ? `Removed the ${name} hooks.` : which === 'codex' ? `${APP_NAME}’s Codex hooks are installed.` : `Connected: ${APP_NAME} will now react to Claude Code.`;
    await dialog.showMessageBox(settingsWin ?? undefined, { type: 'info', message, detail });
  } catch (err) {
    await dialog.showMessageBox(settingsWin ?? undefined, { type: 'warning', message: `${name} hooks`, detail: err.message });
  }
  buildTray();
  settingsWin?.webContents.send('panel:state', panelState());
}


function trayImage() {
  if (process.platform === 'darwin') {
    const icon = nativeImage.createFromPath(path.join(ASSETS, 'trayTemplate.png'));
    icon.setTemplateImage(true);
    return icon;
  }
  const dark = nativeTheme.shouldUseDarkColorsForSystemIntegratedUI ?? true;
  return nativeImage.createFromPath(path.join(ASSETS, dark ? 'trayWindowsWhite.png' : 'trayWindowsBlack.png'));
}

function buildTray() {
  if (!tray) {
    tray = new Tray(trayImage());
    tray.setToolTip(APP_NAME);
    if (process.platform === 'win32') tray.on('click', () => showSettingsBesideMascot());
  }
  const s = store.values;
  const asleep = ASLEEP.has(petState);
  const check = (label, key) => ({ label, type: 'checkbox', checked: !!s[key], click: (i) => store.update((v) => { v[key] = i.checked; }) });
  const radio = (label, on, change) => ({ label, type: 'radio', checked: on, click: () => store.update(change) });
  const keyNote = keys?.status === 'needs-permission' ? ' (allow Accessibility)' : keys?.status === 'unavailable' ? ' (unavailable)' : '';
  const name = CHARACTERS[s.character] ?? APP_NAME;
  const update = updates.state;
  const updateItem = update.status === 'available' ? { label: `Update Available (${update.latest})…`, click: () => openUpdatePage() }
    : update.status === 'downloading' ? { label: `Downloading Update (${update.percent}%)…`, enabled: false }
      : update.status === 'downloaded' ? { label: 'Restart to Update…', click: () => openUpdatePage() }
        : update.status === 'installing' ? { label: 'Installing Update…', enabled: false }
          : update.status === 'failed' && update.latest && update.operation !== 'check' ? { label: 'Retry Update…', click: () => openUpdatePage() } : null;
  tray.setContextMenu(Menu.buildFromTemplate([
    ...(updateItem ? [updateItem, { type: 'separator' }] : []),
    { label: 'Settings…', click: () => showSettingsBesideMascot() },
    { label: hidden ? `Show ${name}` : `Hide ${name}`, accelerator: s.showHideShortcut ? SHORTCUT : undefined, registerAccelerator: false, click: () => toggleMascot() },
    { type: 'separator' },
    { label: asleep ? 'Wake up' : 'Go to sleep', click: () => command('trigger', { name: asleep ? 'wake' : 'sleepy' }) },
    { label: 'Dance', enabled: !asleep, click: () => command('trigger', { name: 'dance' }) },
    { label: 'Wave', enabled: !asleep, click: () => command('trigger', { name: 'wave' }) },
    { type: 'separator' },
    { label: agentStatusLabel(), enabled: false },
    check('React to Claude Code and Codex', 'agentReactions'),
    check('Dance to music (Spotify, Apple Music)', 'musicDance'),
    { ...check(`Type along with my keyboard${keyNote}`, 'typeAlong') },
    { label: claudeHooks.installed() ? 'Remove Claude Code hooks' : 'Connect to Claude Code…', click: () => toggleHooks('claude') },
    { label: codexHooks.installed() ? 'Remove Codex hooks' : 'Connect to Codex…', click: () => toggleHooks('codex') },
    { type: 'separator' },
    { label: 'Character', submenu: Object.entries(CHARACTERS).map(([key, label]) => radio(label, s.character === key, (v) => { v.character = key; })) },
    check('Wanders around', 'autoWalk'),
    check('Looks at the cursor', 'lookAtCursor'),
    {
      label: 'Size',
      submenu: [
        { label: 'Bigger', click: () => store.update((v) => { v.petSize = clampSize(v.petSize * SIZE_STEP); }) },
        { label: 'Smaller', click: () => store.update((v) => { v.petSize = clampSize(v.petSize / SIZE_STEP); }) },
        { type: 'separator' },
        ...SIZE_PRESETS.map(([label, px]) => radio(label, s.petSize === px, (v) => { v.petSize = px; })),
        ...(SIZE_PRESETS.some(([, px]) => px === s.petSize) ? [] : [radio(`Custom (${s.petSize} px)`, true, () => {})]),
        { type: 'separator' },
        { label: 'Tip: scroll over the pet to resize', enabled: false },
      ],
    },
    {
      label: 'Sleep when idle',
      submenu: [['Never', 0], ['After 30 seconds', 0.5], ['After 5 min', 5], ['After 15 min', 15], ['After 25 min', 25]]
        .map(([label, m]) => radio(label, s.idleSleepMin === m, (v) => { v.idleSleepMin = m; })),
    },
    check('Open at login', 'openAtLogin'),
    { type: 'separator' },
    { label: `Quit ${APP_NAME}`, role: 'quit' },
  ]));
}


function pollIdle() {
  const idle = powerMonitor.getSystemIdleTime();
  let limit = store.values.idleSleepMin * 60;
  if (agent?.current.activity === 'waiting') limit = limit > 0 ? Math.min(limit, AWAY_WHILE_WAITING) : AWAY_WHILE_WAITING;
  const agentBusy = AGENT_BUSY.has(agent?.current.activity);
  if (limit > 0 && !idleSleeping && idle >= limit && !agentBusy) {
    idleSleeping = true;
    command('idleSleep', { on: true });
    if (!ASLEEP.has(petState)) command('trigger', { name: 'sleepy' });
  } else if (idleSleeping && (idle < IDLE_POLL_S || agentBusy || limit === 0)) {
    idleSleeping = false;
    command('idleSleep', { on: false });
    if (ASLEEP.has(petState)) command('trigger', { name: 'wake', surprised: idle < IDLE_POLL_S });
  }
}


function toggleMascot() {
  if (startup?.phase === 'starting') return;
  hidden = !hidden;
  send('hidden', hidden);
  if (hidden) win?.hide();
  else {
    win?.showInactive();
    applyLevel();
  }
  buildTray();
}


const PANEL_SIZE = { width: 448, height: 540 };

function panelState() {
  const s = store.values;
  return {
    values: s,
    appName: APP_NAME,
    version: app.getVersion(),
    claudeConnected: claudeHooks.installed(),
    codexConnected: codexHooks.installed(),
    agentStatus: agentStatusLabel(),
    typingNote: s.typeAlong && keys?.status === 'needs-permission' ? 'Needs Accessibility permission to see your keys.'
      : s.typeAlong && keys?.status === 'unavailable' ? 'Typing along isn’t available.' : null,
    asleep: ASLEEP.has(petState),
    shortcutErrors,
    shortcutLabel: SHORTCUT_LABEL,
    platform: process.platform,
    update: {
      status: updates.state.status,
      latest: updates.state.latest ?? null,
      automatic: automaticUpdates,
      percent: updates.state.percent ?? 0,
      operation: updates.state.operation ?? null,
      error: updates.state.error ?? null,
    },
  };
}

function openUpdatePage() {
  if (automaticUpdates) return updates.apply();
  const { status, page } = updates.state;
  if (status === 'available' && page) shell.openExternal(page);
}

function panelOrigin(size, pet) {
  const center = { x: pet.x + pet.width / 2, y: pet.y + pet.height / 2 };
  const vf = screen.getDisplayNearestPoint(center).workArea;
  const gap = 14, margin = 8;
  const fitsRight = pet.x + pet.width + gap + size.width <= vf.x + vf.width - margin;
  const fitsLeft = pet.x - gap - size.width >= vf.x + margin;
  let x, y;
  if (fitsRight || fitsLeft) {
    x = fitsRight ? pet.x + pet.width + gap : pet.x - gap - size.width;
    y = pet.y + pet.height - size.height;
  } else {
    x = center.x - size.width / 2;
    y = pet.y - gap - size.height;
  }
  x = Math.min(Math.max(x, vf.x + margin), vf.x + vf.width - size.width - margin);
  y = Math.min(Math.max(y, vf.y + margin), vf.y + vf.height - size.height - margin);
  return { x: Math.round(x), y: Math.round(y) };
}

function createSettingsWindow() {
  const panel = settingsWin = new BrowserWindow({
    ...PANEL_SIZE,
    minWidth: PANEL_SIZE.width,
    minHeight: 380,
    show: false,
    frame: false,
    resizable: true,
    maximizable: false,
    fullscreenable: false,
    title: `${APP_NAME} Settings`,
    backgroundColor: '#000000',
    skipTaskbar: false,
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true },
  });
  settingsPresentation = createPanelPresentation({
    window: panel,
    prepare: prepareSettingsWindow,
    activate: () => {
      if (process.platform === 'darwin') app.focus({ steal: true });
    },
    afterShow: keepMascotInFront,
  });
  panel.on('closed', () => {
    if (settingsWin !== panel) return;
    settingsWin = null;
    settingsPresentation = null;
  });
  for (const ev of ['focus', 'show', 'moved']) panel.on(ev, () => keepMascotInFront());
  panel.webContents.once('render-process-gone', (_e, details) => {
    console.error(`Settings stopped: ${details.reason}`);
    if (!panel.isDestroyed()) panel.destroy();
  });
  const loading = DEV_URL ? panel.loadURL(new URL('settings.html', DEV_URL).href)
    : panel.loadFile(path.join(__dirname, '..', 'dist', 'settings.html'));
  loading.catch((err) => {
    console.error(`Settings couldn't load: ${err.message}`);
    if (!panel.isDestroyed()) panel.destroy();
  });
}

function keepMascotInFront() {
  if (!win || hidden || !settingsWin?.isVisible()) return;
  if (!store.values.keepOnTop) win.moveTop();
}

function prepareSettingsWindow(panel, petRect) {
  panel.webContents.send('panel:state', panelState());
  if (petRect && petRect.width > 0 && win) {
    const b = win.getBounds();
    const pet = { x: b.x + petRect.x, y: b.y + petRect.y, width: petRect.width, height: petRect.height };
    const [w, h] = panel.getSize();
    const o = panelOrigin({ width: w, height: h }, pet);
    panel.setPosition(o.x, o.y);
  } else if (!panel.isVisible()) panel.center();
}

async function showSettings(petRect) {
  if (!settingsWin) createSettingsWindow();
  return settingsPresentation.show(petRect);
}

async function showSettingsBesideMascot() {
  showSettings(hidden ? null : await ask('petRect'));
}


ipcMain.handle('settings:get', () => store.values);
ipcMain.handle('debug:get', () => DEBUG);
ipcMain.handle('agent:get', () => agent?.current ?? null);
ipcMain.on('settings:set', (_e, patch) => store.update((v) => Object.assign(v, patch)));
ipcMain.on('pointer:over', (_e, over) => win?.setIgnoreMouseEvents(!over, { forward: true }));
ipcMain.on('window:expand', (_e, on) => {
  if (on === expanded) return;
  expanded = on;
  win?.setBounds(stripBounds());
});
ipcMain.on('state', (_e, name) => {
  const changed = ASLEEP.has(name) !== ASLEEP.has(petState);
  petState = name;
  if (changed) {
    buildTray();
    settingsWin?.webContents.send('panel:state', panelState());
  }
});
ipcMain.on('reply', (_e, { id, value }) => {
  const r = replies.get(id);
  if (r) {
    replies.delete(id);
    r(value);
  }
});
ipcMain.on('ready', (e) => {
  if (e.sender !== win?.webContents) return;
  if (startup?.phase === 'starting') return startup.appReady();
  if (!win || win.isVisible() || hidden) return;
  win.showInactive();
  applyLevel();
});
ipcMain.on('settings:open', (_e, petRect) => showSettings(petRect));
ipcMain.on('fatal', (e, msg) => {
  if (e.sender !== win?.webContents) return;
  console.error(`Renderer failed: ${msg}`);
  startup?.fail(String(msg).split('\n')[0]);
});

ipcMain.handle('panel:get', () => panelState());
ipcMain.on('panel:ready', (e) => {
  if (e.sender === settingsWin?.webContents) settingsPresentation?.rendered();
});
ipcMain.on('panel:change', (_e, patch) => store.update((v) => Object.assign(v, patch)));
ipcMain.on('panel:allow', (_e, { state, on }) => store.update((v) => {
  v.disabled = v.disabled.filter((s) => s !== state);
  if (!on) v.disabled.push(state);
}));
ipcMain.on('panel:preview', (_e, state) => command('preview', { name: state }));
ipcMain.on('panel:command', (_e, name) => command('trigger', { name }));
ipcMain.on('panel:resetPosition', () => {
  store.update((v) => { v.home = null; });
  command('resetPosition');
});
ipcMain.on('panel:hooks', (_e, which) => toggleHooks(which));
ipcMain.on('panel:permissions', () => {
  if (process.platform === 'darwin') shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
});
ipcMain.on('panel:close', () => settingsWin?.hide());
ipcMain.on('panel:checkUpdates', () => updates.check());
ipcMain.on('panel:openUpdate', () => openUpdatePage());
ipcMain.on('panel:quit', () => app.quit());


async function capture(webContents, file) {
  const img = await webContents.capturePage();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, img.toPNG());
}

function beginStartup() {
  startup = createStartup({ entered: testing && !DEBUG.splashFilm, onFinish: finishStartup, onFail: failStartup });
  if (!testing || DEBUG.splashFilm) {
    splash = createSplash({
      devUrl: DEV_URL,
      workArea: display().workArea,
      name: APP_NAME,
      onEntered: () => { if (!DEBUG.splashFilm) startup?.entranceDone(); },
      onClosed: () => { splash = null; },
    });
  }
  startupTimer = setTimeout(() => startup.fail(`${APP_NAME} took too long to start. Try opening it again.`), STARTUP_LIMIT_MS);
  if (DEBUG.failStartup) setTimeout(() => startup.fail('Startup failure requested by LILAGENT_FAIL_STARTUP.'), 300);
}

function finishStartup() {
  clearTimeout(startupTimer);
  startupFinished = true;
  splash?.dismiss();
  if (!win || hidden) return;
  win.showInactive();
  applyLevel();
}

function failStartup(message) {
  clearTimeout(startupTimer);
  splash?.destroy();
  console.error(`${APP_NAME} couldn't start: ${message}`);
  if (!testing) dialog.showErrorBox(`${APP_NAME} couldn't start`, message);
  app.quit();
}

function startTestHooks() {
  if (DEBUG.splashFilm && splash) {
    const [start, step, count] = DEBUG.splashFilmAt;
    for (let k = 0; k < count; k++) {
      setTimeout(async () => {
        if (splash) await capture(splash.webContents, path.join(DEBUG.splashFilm, `f${String(k).padStart(2, '0')}.png`));
        if (k === count - 1) app.exit(0);
      }, (start + k * step) * 1000);
    }
  }
  if (DEBUG.snapshot) setTimeout(async () => { await capture(win.webContents, DEBUG.snapshot); app.exit(0); }, DEBUG.snapshotAfter * 1000);
  if (DEBUG.film) {
    const [start, step, count] = DEBUG.filmAt;
    for (let k = 0; k < count; k++) {
      setTimeout(async () => {
        await capture(win.webContents, path.join(DEBUG.film, `f${String(k).padStart(2, '0')}.png`));
        if (k === count - 1) app.exit(0);
      }, (start + k * step) * 1000);
    }
  }
  if (DEBUG.settingsShot) {
    setTimeout(async () => {
      await showSettings(null);
      for (const tab of ['general', 'character', 'moods', 'agents', 'keybinds']) {
        settingsWin.webContents.send('panel:tab', tab);
        await new Promise((r) => setTimeout(r, 400));
        await capture(settingsWin.webContents, path.join(DEBUG.settingsShot, `${tab}.png`));
      }
      app.exit(0);
    }, 2500);
  }
}


app.whenReady().then(() => {
  if (!primary) return;
  setAppMenu();
  syncDock();
  beginStartup();
  createWindow();
  agent = startAgentBridge({
    onActivity: (a) => {
      send('agent', a);
      buildTray();
      settingsWin?.webContents.send('panel:state', panelState());
    },
  });
  music = startMusicWatcher({ enabled: () => store.values.musicDance, onChange: (playing) => send('music', playing) });
  keys = startKeyWatcher({
    onKey: (code, ch) => send('key', { code, ch }),
    onKeyUp: (code) => send('keyup', code),
    onStatus: () => {
      buildTray();
      settingsWin?.webContents.send('panel:state', panelState());
    },
  });
  keys.sync(store.values.typeAlong && !DEBUG.noKeys);
  syncShowHideShortcut();
  buildTray();
  setInterval(pollIdle, IDLE_POLL_S * 1000);
  cursorTimer = setInterval(() => {
    if (!win || hidden) return;
    const p = screen.getCursorScreenPoint();
    const b = win.getBounds();
    send('cursor', { x: p.x - b.x, y: p.y - b.y });
  }, 33);
  for (const ev of ['display-metrics-changed', 'display-added', 'display-removed']) screen.on(ev, () => win?.setBounds(stripBounds()));
  nativeTheme.on('updated', () => tray?.setImage(trayImage()));
  startTestHooks();
  if (!testing || DEBUG.settingsShot) updates.start();
});

app.on('window-all-closed', () => {});
app.on('activate', () => {
  if (startupFinished) showSettingsBesideMascot();
});
app.on('before-quit', () => {
  startup?.cancel();
  clearTimeout(startupTimer);
  splash?.destroy();
});
app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  keys?.stop();
  music?.stop();
  agent?.stop();
  clearInterval(cursorTimer);
  updates.stop();
});
app.on('second-instance', () => showSettingsBesideMascot());
