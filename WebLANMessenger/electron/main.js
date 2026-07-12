const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const dgram = require('dgram');

const LEGACY_PORT = 50000;
let mainWindow;
let discoverySocket;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 780,
    minWidth: 960,
    minHeight: 600,
    frame: false,
    backgroundColor: '#08111d',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'src', 'index.html'));
}

function startDiscovery() {
  if (discoverySocket) return;

  discoverySocket = dgram.createSocket({ type: 'udp4', reuseAddr: true });
  discoverySocket.on('message', (message, remote) => {
    mainWindow?.webContents.send('lan:packet', {
      address: remote.address,
      port: remote.port,
      payload: message.toString('base64'),
    });
  });
  discoverySocket.on('error', (error) => {
    mainWindow?.webContents.send('lan:error', error.message);
  });
  discoverySocket.bind(LEGACY_PORT, '0.0.0.0', () => {
    discoverySocket.setBroadcast(true);
    mainWindow?.webContents.send('lan:ready', { port: LEGACY_PORT });
  });
}

ipcMain.handle('window:minimize', () => mainWindow?.minimize());
ipcMain.handle('window:maximize', () => {
  if (!mainWindow) return;
  mainWindow.isMaximized() ? mainWindow.unmaximize() : mainWindow.maximize();
});
ipcMain.handle('window:close', () => mainWindow?.close());
ipcMain.handle('lan:start', () => startDiscovery());

app.whenReady().then(() => {
  createWindow();
  startDiscovery();
});

app.on('window-all-closed', () => {
  discoverySocket?.close();
  if (process.platform !== 'darwin') app.quit();
});
