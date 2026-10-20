/*
 * Ingressoudi - service worker do app instalado.
 *
 * Proposito unico: mostrar uma tela "sem conexao" quando a internet cai.
 * Paginas, dados, pagamentos e ingressos NUNCA sao guardados em cache: tudo
 * continua vindo da rede, entao cada atualizacao do site chega na hora.
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
