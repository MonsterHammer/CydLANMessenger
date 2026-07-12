const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('cydlan', {
  window: {
    minimize: () => ipcRenderer.invoke('window:minimize'),
    maximize: () => ipcRenderer.invoke('window:maximize'),
    close: () => ipcRenderer.invoke('window:close'),
  },
  lan: {
    start: () => ipcRenderer.invoke('lan:start'),
    onReady: (callback) => ipcRenderer.on('lan:ready', (_event, data) => callback(data)),
    onPacket: (callback) => ipcRenderer.on('lan:packet', (_event, data) => callback(data)),
    onError: (callback) => ipcRenderer.on('lan:error', (_event, message) => callback(message)),
  },
});
