const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('splash', {
  entered: () => ipcRenderer.send('splash:entered'),
  onDismiss: (fn) => ipcRenderer.on('splash:dismiss', (_e, ms) => fn(Number(ms) || 0)),
});
