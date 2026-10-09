import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  codigoErroPerfil,
  decidirAcessoOperador,
  mensagemLoginErro,
  perfilPermitido,
  resolverUid,
  sanitizarRedirect,
  uidDoUsuario
} from '../app/utils/auth.ts'

test('perfilPermitido aceita ADMINISTRADOR e PORTARIA', () => {
  assert.equal(perfilPermitido('ADMINISTRADOR'), true)
  assert.equal(perfilPermitido('PORTARIA'), true)
  assert.equal(perfilPermitido('FINANCEIRO'), false)
  assert.equal(perfilPermitido(null), false)
  assert.equal(perfilPermitido(undefined), false)
})

test('decidirAcessoOperador: sem sessao vai para login', () => {
  assert.equal(
    decidirAcessoOperador({ temSessao: false, perfil: null, ativo: null }),
    'IR_LOGIN'
  )
})

test('decidirAcessoOperador: sem usuario/perfil permitido nega', () => {
  assert.equal(
    decidirAcessoOperador({ temSessao: true, perfil: null, ativo: null }),
    'NEGAR'
  )
  assert.equal(
    decidirAcessoOperador({ temSessao: true, perfil: 'FINANCEIRO', ativo: true }),
    'NEGAR'
  )
})

test('decidirAcessoOperador: perfil permitido mas inativo nega', () => {
  assert.equal(
    decidirAcessoOperador({ temSessao: true, perfil: 'PORTARIA', ativo: false }),
    'NEGAR'
  )
})

test('decidirAcessoOperador: PORTARIA e ADMINISTRADOR ativos permitem', () => {
  assert.equal(
    decidirAcessoOperador({ temSessao: true, perfil: 'PORTARIA', ativo: true }),
    'PERMITIR'
  )
  assert.equal(
    decidirAcessoOperador({ temSessao: true, perfil: 'ADMINISTRADOR', ativo: true }),
    'PERMITIR'
  )
})

test('mensagemLoginErro nao expoe detalhes tecnicos', () => {
  assert.equal(mensagemLoginErro('CREDENCIAIS_INVALIDAS'), 'E-mail ou senha inválidos.')
  assert.equal(mensagemLoginErro('SEM_PERMISSAO'), 'Você não tem permissão para acessar a portaria.')
  assert.equal(mensagemLoginErro('ERRO_TEMPORARIO'), 'Não foi possível entrar agora. Tente novamente.')
})

// --- race condition: uid do signIn nao depende do ref reativo -----------------

test('A) usa data.user.id mesmo com useSupabaseUser ainda null', () => {
  assert.equal(resolverUid('auth-db1e2c3d', null, null), 'auth-db1e2c3d')
})

test('B) fallback para data.session.user.id', () => {
  assert.equal(resolverUid(null, 'session-9f8e7d6c', null), 'session-9f8e7d6c')
})

test('C) sem uid disponivel => null (tratado como ERRO_TEMPORARIO, nao SEM_USUARIO)', () => {
  assert.equal(resolverUid(null, null, null), null)
  assert.equal(resolverUid(undefined, undefined), null)
})

test('D) uid conhecido + perfil inexistente => SEM_USUARIO', () => {
  assert.equal(codigoErroPerfil(null), 'SEM_USUARIO')
})

test('E) perfil PORTARIA ativo => autorizado (sem erro)', () => {
  assert.equal(codigoErroPerfil({ ativo: true, perfil: 'PORTARIA' }), null)
})

test('F) perfil ADMINISTRADOR ativo => autorizado (sem erro)', () => {
  assert.equal(codigoErroPerfil({ ativo: true, perfil: 'ADMINISTRADOR' }), null)
})

test('G) perfil inativo => negado', () => {
  assert.equal(codigoErroPerfil({ ativo: false, perfil: 'PORTARIA' }), 'INATIVO')
})

test('perfil ativo nao autorizado => SEM_PERMISSAO', () => {
  assert.equal(codigoErroPerfil({ ativo: true, perfil: 'FINANCEIRO' }), 'SEM_PERMISSAO')
})

// --- middleware: nao derrubar sessao por atraso reativo -----------------------

test('H) middleware com ref atrasado mas sessao presente => usa uid da sessao (sem signOut)', () => {
  const uid = resolverUid(null, 'session-9f8e7d6c')
  assert.equal(uid, 'session-9f8e7d6c')
})

test('I) sem sessao => null (redirect /login)', () => {
  assert.equal(resolverUid(null, null), null)
})

// --- SSR: useSupabaseUser() retorna JWT claims (sub), nao User (id) -----------

test('uidDoUsuario extrai sub das claims (SSR) e id do objeto User (client)', () => {
  // SSR (@nuxtjs/supabase v2): claims com `sub`
  assert.equal(uidDoUsuario({ sub: 'sub-9f8e7d6c', email: 'x@y.z' }), 'sub-9f8e7d6c')
  // client: objeto User com `id`
  assert.equal(uidDoUsuario({ id: 'user-123' }), 'user-123')
  // ambos: prefere id
  assert.equal(uidDoUsuario({ id: 'user-123', sub: 'sub-9f8e7d6c' }), 'user-123')
  // invalidos
  assert.equal(uidDoUsuario(null), null)
  assert.equal(uidDoUsuario(undefined), null)
  assert.equal(uidDoUsuario({}), null)
  assert.equal(uidDoUsuario('string'), null)
})

test('middleware SSR resolve uid a partir das claims (sem session.user)', () => {
  // No SSR: user = claims(sub); session nao tem `user` (deletado pelo modulo)
  const uid = resolverUid(uidDoUsuario({ sub: 'sub-abc' }), undefined)
  assert.equal(uid, 'sub-abc')
})

// --- open redirect ------------------------------------------------------------

test('sanitizarRedirect aceita apenas caminhos internos seguros', () => {
  assert.equal(sanitizarRedirect('/eventos'), '/eventos')
  assert.equal(sanitizarRedirect('/pedidos?evento=1'), '/pedidos?evento=1')
  assert.equal(sanitizarRedirect('  /portaria '), '/portaria')
})

test('sanitizarRedirect bloqueia destinos externos/perigosos', () => {
  assert.equal(sanitizarRedirect('https://externo.com'), null)
  assert.equal(sanitizarRedirect('http://externo.com'), null)
  assert.equal(sanitizarRedirect('//externo.com'), null)
  assert.equal(sanitizarRedirect('/\\externo.com'), null)
  assert.equal(sanitizarRedirect('javascript:alert(1)'), null)
  assert.equal(sanitizarRedirect('data:text/html,x'), null)
  assert.equal(sanitizarRedirect('eventos'), null)
  assert.equal(sanitizarRedirect(null), null)
  assert.equal(sanitizarRedirect(undefined), null)
  assert.equal(sanitizarRedirect('/ok\nset-cookie'), null)
})
