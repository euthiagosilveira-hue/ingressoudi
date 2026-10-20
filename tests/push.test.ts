import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

import { chaveVapidParaBytes, precisaInstalarNoIphone, textoSituacaoPush } from '../app/utils/push.ts'
import { assinaturaExpirada, avisoNovaOrganizacao } from '../server/utils/push-mensagens.ts'

const ler = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8')

test('chaveVapidParaBytes decodifica base64url sem preenchimento', () => {
  const bytes = chaveVapidParaBytes('AQID_-8')
  assert.deepEqual(Array.from(bytes), [1, 2, 3, 255, 239])
})

test('iPhone fora do app instalado precisa instalar antes', () => {
  const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15'
  assert.equal(precisaInstalarNoIphone(iphone, false), true)
  assert.equal(precisaInstalarNoIphone(iphone, true), false)
  assert.equal(precisaInstalarNoIphone('Mozilla/5.0 (Linux; Android 14) Chrome/130', false), false)
  assert.ok(textoSituacaoPush('instalar-iphone').includes('Adicionar à Tela de Início'))
})

test('aviso de casa nova leva para Organizacoes e diz se aguarda aprovacao', () => {
  const pendente = avisoNovaOrganizacao('Bar do Zé', false)
  assert.equal(pendente.title, 'Nova casa cadastrada')
  assert.equal(pendente.body, 'Bar do Zé se cadastrou e aguarda sua aprovação.')
  assert.equal(pendente.url, '/plataforma/organizacoes')
  assert.equal(avisoNovaOrganizacao('Casa X', true).body, 'Casa X acabou de se cadastrar.')
})

test('aparelho inexistente (404/410) e removido; outros erros nao', () => {
  assert.equal(assinaturaExpirada(410), true)
  assert.equal(assinaturaExpirada(404), true)
  assert.equal(assinaturaExpirada(500), false)
  assert.equal(assinaturaExpirada(undefined), false)
})

test('service worker mostra a notificacao e abre a pagina do aviso', () => {
  const sw = ler('../public/sw.js')
  assert.ok(sw.includes("addEventListener('push'"))
  assert.ok(sw.includes('showNotification'))
  assert.ok(sw.includes("addEventListener('notificationclick'"))
})

test('cadastro do produtor avisa os super admins so quando cria a casa', () => {
  const pagina = ler('../app/pages/cadastro/concluir.vue')
  assert.ok(pagina.includes('if (!cadastro.jaExistente && cadastro.organizacaoId) await avisarNovaOrganizacao('))
})
