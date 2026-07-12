const detail = document.querySelector('#connection-detail');

window.cydlan?.lan.onReady(({ port }) => {
  detail.textContent = `Legacy protocol ready · Port ${port}`;
});

window.cydlan?.lan.onError((message) => {
  detail.textContent = `LAN error · ${message}`;
});

window.cydlan?.lan.onPacket((packet) => {
  detail.textContent = `Legacy packet detected from ${packet.address}`;
});

document.querySelector('#minimize').addEventListener('click', () => window.cydlan.window.minimize());
document.querySelector('#maximize').addEventListener('click', () => window.cydlan.window.maximize());
document.querySelector('#close').addEventListener('click', () => window.cydlan.window.close());
