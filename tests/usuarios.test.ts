import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  contarAdminsAtivos,
  emailValido,
  formularioValido,
  mapearUsuarioAdmin,
  mapearUsuariosAdmin,
  mensagemErroConvite,
  mensagemErroUsuario,
  montarPayloadAtualizacao,
  rotuloPerfil,
  validarConvite,
  validarEdicao
} from '../app/utils/usuarios.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const ROW_ADMIN = {
  id: 'a',
  nome: 'Admin',
  email: 'admin@x.com',
  perfil: 'ADMINISTRADOR',
  ativo: true,
  ultimo_acesso_em: null,
  criado_em: '2026-01-01T00:00:00Z'
}
const ROW_ADMIN2 = { ...ROW_ADMIN, id: 'b', nome: 'Admin 2', email: 'admin2@x.com' }
const ROW_PORT = {
  ...ROW_ADMIN,
  id: 'c',
  nome: 'Portaria',
  email: 'port@x.com',
  perfil: 'PORTARIA',
  ativo: true
}

test('mapearUsuariosAdmin marca o unico ADMIN ativo e formata dados', () => {
  const lista = mapearUsuariosAdmin([ROW_ADMIN, ROW_PORT])
  assert.equal(lista[0].ehUltimoAdminAtivo, true)
  assert.equal(lista[1].ehUltimoAdminAtivo, false)
  assert.equal(lista[0].ultimoAcesso, 'Sem registro')
  assert.equal(lista[0].criadoEm.length > 0, true)
})

test('com 2 ADMINs ativos nenhum e marcado como ultimo', () => {
  const lista = mapearUsuariosAdmin([ROW_ADMIN, ROW_ADMIN2, ROW_PORT])
  assert.equal(lista[0].ehUltimoAdminAtivo, false)
  assert.equal(lista[1].ehUltimoAdminAtivo, false)
  assert.equal(contarAdminsAtivos([ROW_ADMIN, ROW_ADMIN2, ROW_PORT]), 2)
})

test('admin inativo nao conta nem e marcado como ultimo', () => {
  const inativo = { ...ROW_ADMIN, ativo: false }
  const lista = mapearUsuariosAdmin([inativo, ROW_PORT])
  assert.equal(contarAdminsAtivos([inativo, ROW_PORT]), 0)
  assert.equal(lista[0].ehUltimoAdminAtivo, false)
})

test('mapearUsuarioAdmin isolado nunca marca ultimo', () => {
  assert.equal(mapearUsuarioAdmin(ROW_ADMIN).ehUltimoAdminAtivo, false)
})

test('rotuloPerfil e emailValido', () => {
  assert.equal(rotuloPerfil('ADMINISTRADOR'), 'Administrador')
  assert.equal(rotuloPerfil('PORTARIA'), 'Portaria')
  assert.equal(emailValido('a@b.com'), true)
  assert.equal(emailValido('a@b'), false)
  assert.equal(emailValido(''), false)
})

test('validarConvite exige nome, email valido e perfil', () => {
  assert.ok(!formularioValido(validarConvite({ nome: '', email: 'a@b.com', perfil: 'PORTARIA' })))
  assert.ok(!formularioValido(validarConvite({ nome: 'X', email: 'invalido', perfil: 'PORTARIA' })))
  assert.ok(
    !formularioValido(
      validarConvite({ nome: 'X', email: 'a@b.com', perfil: 'GESTOR' as never })
    )
  )
  assert.ok(formularioValido(validarConvite({ nome: 'X', email: 'a@b.com', perfil: 'PORTARIA' })))
})

test('validarEdicao exige nome e perfil', () => {
  assert.equal(validarEdicao({ id: 'a', nome: '  ', perfil: 'PORTARIA', ativo: true }).nome, 'Informe o nome.')
  assert.ok(formularioValido(validarEdicao({ id: 'a', nome: 'X', perfil: 'PORTARIA', ativo: false })))
})

test('montarPayloadAtualizacao aplica trim e mapeia campos', () => {
  const payload = montarPayloadAtualizacao({
    id: 'u1',
    nome: '  Maria  ',
    perfil: 'PORTARIA',
    ativo: false
  })
  assert.deepEqual(payload, {
    p_usuario_id: 'u1',
    p_nome: 'Maria',
    p_perfil: 'PORTARIA',
    p_ativo: false
  })
})

test('mensagemErroUsuario traduz erros conhecidos', () => {
  assert.match(mensagemErroUsuario({ code: '42501', message: 'proprio' }, 'x'), /próprio/)
  assert.match(
    mensagemErroUsuario({ code: '23514', message: 'pelo menos um administrador ativo' }, 'x'),
    /administrador ativo/
  )
  assert.match(mensagemErroUsuario({ code: '23505' }, 'x'), /Já existe/)
  assert.match(mensagemErroUsuario({ code: '23503' }, 'x'), /não encontrado/)
  assert.equal(mensagemErroUsuario(null, 'padrao'), 'padrao')
})

test('mensagemErroConvite cobre codigos do endpoint', () => {
  assert.match(mensagemErroConvite('EMAIL_DUPLICADO'), /Já existe/)
  assert.match(mensagemErroConvite('SEM_PERMISSAO'), /permissão/)
  assert.match(mensagemErroConvite('DADOS_INVALIDOS'), /Verifique/)
  assert.match(mensagemErroConvite('FALHA_CONVITE'), /convite/)
  assert.equal(mensagemErroConvite(undefined), 'Não foi possível concluir a operação.')
})

test('pagina /configuracoes/usuarios exige admin-auth', () => {
  const pagina = ler('../app/pages/configuracoes/usuarios.vue')
  assert.ok(pagina.includes("middleware: ['admin-auth']"))
  assert.ok(pagina.includes("sidebarActive: 'Configurações'"))
})

test('sidebar aponta Configurações para /configuracoes', () => {
  const sidebar = ler('../app/components/AdminSidebar.vue')
  assert.ok(sidebar.includes("to: '/configuracoes'"))
  assert.ok(sidebar.includes("label: 'Configurações'"))
})

test('endpoint de convite usa service role + Auth Admin e nao expoe chave', () => {
  const endpoint = ler('../server/api/admin/users/invite.post.ts')
  assert.ok(endpoint.includes('serverSupabaseServiceRole'))
  assert.ok(endpoint.includes('inviteUserByEmail'))
  assert.ok(endpoint.includes("perfil !== 'ADMINISTRADOR'"))
  assert.ok(!endpoint.includes('serviceKey'))
  assert.ok(!/SECRET_KEY|secretKey/.test(endpoint))
})

test('service do frontend nao referencia service role', () => {
  const service = ler('../app/services/admin/usuarios.ts')
  assert.ok(service.includes('/api/admin/users/invite'))
  assert.ok(!/service_role|serviceRole|SUPABASE_SECRET/i.test(service))
})
