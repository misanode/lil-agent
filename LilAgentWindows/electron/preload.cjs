const { contextBridge, ipcRenderer } = require('electron');

const on = (channel) => (fn) => ipcRenderer.on(channel, (_e, payload) => fn(payload));

contextBridge.exposeInMainWorld('pet', {
  getSettings: () => ipcRenderer.invoke('settings:get'),
  getDebug: () => ipcRenderer.invoke('debug:get'),
  getAgent: () => ipcRenderer.invoke('agent:get'),
  setSettings: (patch) => ipcRenderer.send('settings:set', patch),
  setOver: (over) => ipcRenderer.send('pointer:over', over),
  setExpanded: (on) => ipcRenderer.send('window:expand', on),
  setState: (name) => ipcRenderer.send('state', name),
  openSettings: (petRect) => ipcRenderer.send('settings:open', petRect),
  reply: (id, value) => ipcRenderer.send('reply', { id, value }),
  ready: () => ipcRenderer.send('ready'),
  fatal: (msg) => ipcRenderer.send('fatal', msg),
  onSettings: on('settings'),
  onAgent: on('agent'),
  onMusic: on('music'),
  onKey: on('key'),
  onKeyUp: on('keyup'),
  onCursor: on('cursor'),
  onHidden: on('hidden'),
  onCommand: on('command'),
});

contextBridge.exposeInMainWorld('panel', {
  get: () => ipcRenderer.invoke('panel:get'),
  ready: () => ipcRenderer.send('panel:ready'),
  change: (patch) => ipcRenderer.send('panel:change', patch),
  allow: (state, on) => ipcRenderer.send('panel:allow', { state, on }),
  preview: (state) => ipcRenderer.send('panel:preview', state),
  command: (name) => ipcRenderer.send('panel:command', name),
  resetPosition: () => ipcRenderer.send('panel:resetPosition'),
  hooks: (which) => ipcRenderer.send('panel:hooks', which),
  permissions: () => ipcRenderer.send('panel:permissions'),
  close: () => ipcRenderer.send('panel:close'),
  checkUpdates: () => ipcRenderer.send('panel:checkUpdates'),
  openUpdate: () => ipcRenderer.send('panel:openUpdate'),
  quit: () => ipcRenderer.send('panel:quit'),
  onState: on('panel:state'),
  onTab: on('panel:tab'),
});
