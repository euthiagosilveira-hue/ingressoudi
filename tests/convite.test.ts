import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  CONVITE_EXPIRADO_MSG,
  destinoAposConvite,
  extrairErroConvite,
  lerTokenConvite,
  linkWhatsappConvite,
  mensagemConvite,
  mensagemErroConviteLink,
  validarSenhaConvite
} from '../app/utils/convite.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const endpoint = ler('../server/api/admin/users/invite.post.ts')
const novoLink = ler('../server/api/admin/users/link-convite.post.ts')
const utilLink = ler('../server/utils/link-convite.ts')
const pagina = ler('../app/pages/auth/convite.vue')
const nuxtConfig = ler('../nuxt.config.ts')
const envExample = ler('../.env.example')

// A/B/C) siteUrl de producao + redirectTo correto + sem localhost no endpoint
test('link de convite usa NUXT_PUBLIC_SITE_URL e aponta para /auth/convite', () => {
  assert.ok(utilLink.includes('config.public.siteUrl'))
  assert.ok(utilLink.includes('`${siteUrl}/auth/convite`'))
  assert.ok(utilLink.includes('token_hash'))
  assert.ok(endpoint.includes('urlDoSite(event)'))
  assert.ok(!endpoint.includes('/login`'))
})

test('convite gera link sem e-mail (generateLink) e devolve o link', () => {
  assert.ok(utilLink.includes('generateLink'))
  assert.ok(utilLink.includes('hashed_token'))
  assert.ok(!endpoint.includes('inviteUserByEmail'))
  assert.ok(endpoint.includes('gerarLinkConvite'))
  assert.ok(endpoint.includes('link: convite.link'))
})

test('novo link: so ADMIN, so membro pendente sem outra organizacao', () => {
  assert.ok(novoLink.includes('exigirAdminOrganizacaoAtiva(event)'))
  assert.ok(novoLink.includes("'situacao_convite_usuario'"))
  assert.ok(novoLink.includes('situacao.membro'))
  assert.ok(novoLink.includes('CONVITE_JA_ACEITO'))
  assert.ok(novoLink.includes('outras_organizacoes'))
  assert.ok(novoLink.includes('limitar(event'))
  assert.ok(!/service_role|SECRET_KEY|secretKey/.test(novoLink))
})

test('config expõe public.siteUrl a partir de NUXT_PUBLIC_SITE_URL', () => {
  assert.ok(nuxtConfig.includes('siteUrl: process.env.NUXT_PUBLIC_SITE_URL'))
})

test('.env.example documenta NUXT_PUBLIC_SITE_URL com URL https de producao (sem dominio do GZ1)', () => {
  assert.ok(envExample.includes('NUXT_PUBLIC_SITE_URL'))
  assert.ok(/Producao: https:\/\//.test(envExample))
  assert.ok(!envExample.includes('gz-1-ingressos'))
})

// D) convite expirado -> mensagem amigavel
test('extrairErroConvite detecta expiracao no hash e na query', () => {
  assert.deepEqual(
    extrairErroConvite('', '#error=access_denied&error_code=otp_expired&error_description=x'),
    { error: 'access_denied', errorCode: 'otp_expired' }
  )
  assert.deepEqual(extrairErroConvite('?error=access_denied&error_code=otp_expired', ''), {
    error: 'access_denied',
    errorCode: 'otp_expired'
  })
  assert.equal(extrairErroConvite('', '#access_token=abc&type=invite'), null)
  assert.equal(extrairErroConvite('', ''), null)
})

test('mensagemErroConviteLink e amigavel (nao expoe erro bruto)', () => {
  const msg = mensagemErroConviteLink({ error: 'access_denied', errorCode: 'otp_expired' })
  assert.equal(msg, CONVITE_EXPIRADO_MSG)
  assert.match(msg, /expirou|utilizado/)
  assert.ok(!msg.includes('access_denied'))
  assert.ok(!msg.includes('otp_expired'))
})

// E/F/G/H) fluxo de senha e destino por perfil
test('pagina /auth/convite conclui setup via updateUser({ password })', () => {
  assert.ok(pagina.includes('updateUser({ password: form.senha })'))
  assert.ok(pagina.includes('exchangeCodeForSession'))
  assert.ok(pagina.includes('setSession'))
  assert.ok(pagina.includes('extrairErroConvite'))
  assert.ok(pagina.includes('mensagemErroConviteLink'))
  assert.ok(pagina.includes('layout: false'))
  assert.ok(pagina.includes('verifyOtp'))
  assert.ok(pagina.includes('lerTokenConvite'))
  assert.ok(pagina.includes('Aceitar convite'))
  assert.ok(!pagina.includes("middleware: ['admin-auth']"))
})

test('destinoAposConvite: PORTARIA -> /portaria, ADMIN/outros -> /painel', () => {
  assert.equal(destinoAposConvite('PORTARIA'), '/portaria')
  assert.equal(destinoAposConvite('ADMINISTRADOR'), '/painel')
  assert.equal(destinoAposConvite(null), '/painel')
  assert.equal(destinoAposConvite(undefined), '/painel')
})

test('validarSenhaConvite exige senha forte e confirmacao', () => {
  assert.ok(validarSenhaConvite('', '').senha)
  assert.ok(validarSenhaConvite('123', '123').senha)
  assert.ok(validarSenhaConvite('12345678', '').confirmacao)
  assert.ok(validarSenhaConvite('12345678', '87654321').confirmacao)
  assert.deepEqual(validarSenhaConvite('12345678', '12345678'), {})
})

test('seguranca: endpoint mantem service role server-side e sem secrets expostos', () => {
  assert.ok(endpoint.includes('serverSupabaseServiceRole'))
  assert.ok(endpoint.includes('gerarLinkConvite'))
  assert.ok(endpoint.includes("perfil !== 'ADMINISTRADOR'"))
  assert.ok(!endpoint.includes('serviceKey'))
  assert.ok(!/SECRET_KEY|service_role/.test(endpoint))
})

test('lerTokenConvite le token_hash e tipo do link', () => {
  assert.deepEqual(lerTokenConvite('?token_hash=abc&tipo=invite'), { tokenHash: 'abc', tipo: 'invite' })
  assert.deepEqual(lerTokenConvite('token_hash=abc&tipo=recovery'), { tokenHash: 'abc', tipo: 'recovery' })
  assert.deepEqual(lerTokenConvite('?token_hash=abc&tipo=outro'), { tokenHash: 'abc', tipo: 'invite' })
  assert.equal(lerTokenConvite('?code=123'), null)
  assert.equal(lerTokenConvite(''), null)
  assert.equal(lerTokenConvite(undefined), null)
})

test('mensagem e WhatsApp do convite levam o link', () => {
  const link = 'https://www.ingressoudi.com.br/auth/convite?token_hash=abc&tipo=invite'
  const texto = mensagemConvite('Maria Souza', link)
  assert.match(texto, /^Olá, Maria!/)
  assert.ok(texto.includes(link))
  assert.match(mensagemConvite('', link), /^Olá!/)
  const wa = linkWhatsappConvite('Maria', link)
  assert.ok(wa.startsWith('https://wa.me/?text='))
  assert.equal(decodeURIComponent(wa.replace('https://wa.me/?text=', '')), mensagemConvite('Maria', link))
})
