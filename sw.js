// O painel do Visus Clipper mudou para https://painel.visusclipper.online.
// Este arquivo substitui o service worker antigo do painel neste endereço:
// apaga a cópia guardada, se desinstala e recarrega as abas na página nova.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) await caches.delete(k);
    await self.registration.unregister();
    for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url.split('#')[0]);
  })());
});
