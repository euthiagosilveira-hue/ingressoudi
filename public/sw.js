/*
 * Ingressoudi - service worker do app instalado.
 *
 * 1) Mostrar uma tela "sem conexao" quando a internet cai.
 *    Paginas, dados, pagamentos e ingressos NUNCA sao guardados em cache: tudo
 *    continua vindo da rede, entao cada atualizacao do site chega na hora.
 * 2) Mostrar as notificacoes push (avisos do super admin) e abrir a pagina
 *    certa ao tocar nelas.
 */
const VERSAO = 'ingressoudi-v1'
const OFFLINE = '/offline.html'
const ARQUIVOS = [OFFLINE, '/icon-192.png']

self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches
      .open(VERSAO)
      .then((cache) => cache.addAll(ARQUIVOS))
      .then(() => self.skipWaiting())
  )
})

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches
      .keys()
      .then((chaves) => Promise.all(chaves.filter((c) => c !== VERSAO).map((c) => caches.delete(c))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener('fetch', (evento) => {
  const req = evento.request
  // So trata a abertura de paginas; o resto vai direto para a rede.
  if (req.method !== 'GET' || req.mode !== 'navigate') return
  evento.respondWith(
    fetch(req).catch(() => caches.match(OFFLINE).then((resp) => resp || Response.error()))
  )
})

self.addEventListener('push', (evento) => {
  let aviso = {}
  try {
    aviso = evento.data ? evento.data.json() : {}
  } catch (e) {
    aviso = { body: evento.data ? evento.data.text() : '' }
  }
  const titulo = aviso.title || 'Ingressoudi'
  evento.waitUntil(
    self.registration.showNotification(titulo, {
      body: aviso.body || '',
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      tag: aviso.tag || undefined,
      data: { url: aviso.url || '/' }
    })
  )
})

self.addEventListener('notificationclick', (evento) => {
  evento.notification.close()
  const destino = new URL((evento.notification.data && evento.notification.data.url) || '/', self.location.origin).href
  evento.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((janelas) => {
      for (const janela of janelas) {
        if ('focus' in janela && 'navigate' in janela) {
          return janela.navigate(destino).then((j) => (j || janela).focus())
        }
      }
      return self.clients.openWindow(destino)
    })
  )
})
