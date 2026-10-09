import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  CONVITE_EXPIRADO_MSG,
  destinoAposConvite,
  extrairErroConvite,
  mensagemErroConviteLink,
  validarSenhaConvite
} from '../app/utils/convite.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const endpoint = ler('../server/api/admin/users/invite.post.ts')
const pagina = ler('../app/pages/auth/convite.vue')
const nuxtConfig = ler('../nuxt.config.ts')
const envExample = ler('../.env.example')

// A/B/C) siteUrl de producao + redirectTo correto + sem localhost no endpoint
test('endpoint usa NUXT_PUBLIC_SITE_URL e redireciona para /auth/convite', () => {
  assert.ok(endpoint.includes('config.public.siteUrl'))
  assert.ok(endpoint.includes('`${siteUrl}/auth/convite`'))
  assert.ok(!endpoint.includes('/login`'))
})

test('config expõe public.siteUrl a partir de NUXT_PUBLIC_SITE_URL', () => {
  assert.ok(nuxtConfig.includes('siteUrl: process.env.NUXT_PUBLIC_SITE_URL'))
})

test('.env.example documenta NUXT_PUBLIC_SITE_URL com o dominio de producao', () => {
  assert.ok(envExample.includes('NUXT_PUBLIC_SITE_URL'))
  assert.ok(envExample.includes('https://gz-1-ingressos.vercel.app'))
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
  assert.ok(!pagina.includes("middleware: ['admin-auth']"))
})

test('destinoAposConvite: PORTARIA -> /portaria, ADMIN/outros -> /', () => {
  assert.equal(destinoAposConvite('PORTARIA'), '/portaria')
  assert.equal(destinoAposConvite('ADMINISTRADOR'), '/')
  assert.equal(destinoAposConvite(null), '/')
  assert.equal(destinoAposConvite(undefined), '/')
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
  assert.ok(endpoint.includes('inviteUserByEmail'))
  assert.ok(endpoint.includes("perfil !== 'ADMINISTRADOR'"))
  assert.ok(!endpoint.includes('serviceKey'))
  assert.ok(!/SECRET_KEY|service_role/.test(endpoint))
})
