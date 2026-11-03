import { test } from 'node:test'
import assert from 'node:assert/strict'

import { idVideoYoutube, urlEmbedYoutube } from '../app/utils/videoApresentacao.ts'

test('idVideoYoutube reconhece os formatos de link do YouTube', () => {
  const id = 'dQw4w9WgXcQ'
  for (const link of [
    id,
    `https://www.youtube.com/watch?v=${id}`,
    `https://youtube.com/watch?v=${id}&t=10s`,
    `https://m.youtube.com/watch?v=${id}`,
    `https://youtu.be/${id}?si=abc`,
    `youtu.be/${id}`,
    `https://www.youtube.com/shorts/${id}`,
    `https://www.youtube.com/embed/${id}`,
    `https://www.youtube-nocookie.com/embed/${id}`,
    `  https://youtu.be/${id}  `
  ]) {
    assert.equal(idVideoYoutube(link), id, link)
  }
})

test('idVideoYoutube recusa vazio e links que nao sao do YouTube', () => {
  for (const link of ['', null, undefined, 'abc', 'https://vimeo.com/123456', 'https://youtube.com/watch?v=curto', 'https://evil.com/watch?v=dQw4w9WgXcQ']) {
    assert.equal(idVideoYoutube(link), null, String(link))
  }
})

test('urlEmbedYoutube usa o dominio sem cookies e so toca apos o clique', () => {
  const url = new URL(urlEmbedYoutube('dQw4w9WgXcQ'))
  assert.equal(url.hostname, 'www.youtube-nocookie.com')
  assert.equal(url.pathname, '/embed/dQw4w9WgXcQ')
  assert.equal(url.searchParams.get('rel'), '0')
  assert.equal(url.searchParams.get('playsinline'), '1')
})
