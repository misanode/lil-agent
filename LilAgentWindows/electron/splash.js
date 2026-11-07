import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BrowserWindow, ipcMain } from 'electron';
import { SPLASH, splashBounds } from './startup.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function createSplash({ devUrl, workArea, name, onEntered, onClosed }) {
  const win = new BrowserWindow({
    ...splashBounds(workArea),
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
    hiddenInMissionControl: true,
    show: false,
    backgroundColor: '#00000000',
    webPreferences: {
      preload: path.join(__dirname, 'splash-preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false,
    },
  });
  win.setIgnoreMouseEvents(true);
  win.setAlwaysOnTop(true, process.platform === 'darwin' ? 'floating' : 'screen-saver');

  let entered = false;
  let closing = false;
  let closeTimer = null;
  const enter = () => {
    if (entered) return;
    entered = true;
    clearTimeout(enterTimer);
    onEntered();
  };
  const enterTimer = setTimeout(enter, SPLASH.enterLimitMs);
  const onMessage = (e) => { if (e.sender === win.webContents) enter(); };
  ipcMain.on('splash:entered', onMessage);
  const destroy = () => { if (!win.isDestroyed()) win.destroy(); };

  win.once('ready-to-show', () => { if (!closing) win.showInactive(); });
  win.webContents.on('did-fail-load', (_e, _code, _desc, _url, isMainFrame) => { if (isMainFrame) destroy(); });
  win.webContents.on('render-process-gone', destroy);
  win.on('closed', () => {
    clearTimeout(enterTimer);
    clearTimeout(closeTimer);
    ipcMain.removeListener('splash:entered', onMessage);
    enter();
    onClosed?.();
  });

  const query = { gap: String(SPLASH.gap), spinner: String(SPLASH.spinner), edge: String(SPLASH.edge), lift: String(18 / SPLASH.cardWidth), name };
  if (devUrl) win.loadURL(new URL(`splash.html?${new URLSearchParams(query)}`, devUrl).href);
  else win.loadFile(path.join(__dirname, '..', 'dist', 'splash.html'), { query });

  return {
    webContents: win.webContents,
    dismiss() {
      if (closing || win.isDestroyed()) return;
      closing = true;
      if (!win.isVisible()) return destroy();
      win.webContents.send('splash:dismiss', SPLASH.fadeOutMs);
      closeTimer = setTimeout(destroy, SPLASH.fadeOutMs + 40);
    },
    destroy,
  };
}
