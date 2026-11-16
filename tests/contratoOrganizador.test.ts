import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  cnpjValido,
  cpfValido,
  formatarDocumento,
  formatarTelefone,
  soDigitos,
  telefoneValido,
  validarDadosOrganizador
} from '../app/utils/documento.ts'
import {
  CONTRATO_ORGANIZADOR_VERSAO,
  mensagemErroContrato,
  rotaLiberadaComContratoPendente
} from '../app/utils/contratoOrganizador.ts'
import { lerMetadadosCadastro, metadadosCadastro, validarCadastro, type DadosCadastro } from '../app/utils/cadastro.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('CPF: digitos verificadores, repetidos e tamanho', () => {
  assert.equal(cpfValido('529.982.247-25'), true)
  assert.equal(cpfValido('52998224725'), true)
  assert.equal(cpfValido('529.982.247-24'), false)
  assert.equal(cpfValido('111.111.111-11'), false)
  assert.equal(cpfValido('123'), false)
  assert.equal(cpfValido(null), false)
})

test('CNPJ: digitos verificadores, repetidos e tamanho', () => {
  assert.equal(cnpjValido('11.222.333/0001-81'), true)
  assert.equal(cnpjValido('11222333000181'), true)
  assert.equal(cnpjValido('11.222.333/0001-80'), false)
  assert.equal(cnpjValido('00.000.000/0000-00'), false)
  assert.equal(cnpjValido('1122233300018'), false)
})

test('mascaras de documento e telefone', () => {
  assert.equal(formatarDocumento('CPF', '52998224725'), '529.982.247-25')
  assert.equal(formatarDocumento('CPF', '5299'), '529.9')
  assert.equal(formatarDocumento('CNPJ', '11222333000181'), '11.222.333/0001-81')
  assert.equal(formatarDocumento('CNPJ', '112223'), '11.222.3')
  assert.equal(formatarDocumento('CPF', '529982247251234'), '529.982.247-25')
  assert.equal(formatarTelefone('34999990000'), '(34) 99999-0000')
  assert.equal(formatarTelefone('3433334444'), '(34) 3333-4444')
  assert.equal(formatarTelefone('34'), '(34')
  assert.equal(soDigitos('(34) 99999-0000'), '34999990000')
  assert.equal(telefoneValido('(34) 99999-0000'), true)
  assert.equal(telefoneValido('9999-0000'), false)
})

test('validacao dos dados do organizador', () => {
  assert.deepEqual(
    validarDadosOrganizador({ tipoDocumento: 'CPF', documento: '529.982.247-25', responsavelNome: 'Fulano', telefone: '(34) 99999-0000' }),
    {}
  )
  const erros = validarDadosOrganizador({ tipoDocumento: 'CNPJ', documento: '529.982.247-25', responsavelNome: ' ', telefone: '1' })
  assert.match(erros.documento ?? '', /CNPJ inválido/)
  assert.match(erros.responsavelNome ?? '', /razão social/)
  assert.ok(erros.telefone)
})

const base: DadosCadastro = {
  nome: 'Fulano',
  email: 'f@x.com',
  senha: '12345678',
  confirmacao: '12345678',
  casaNome: 'Casa',
  casaSlug: 'casa',
  tipoDocumento: 'CPF',
  documento: '529.982.247-25',
  responsavelNome: 'Fulano de Tal',
  telefone: '(34) 99999-0000',
  termos: true,
  contrato: true
}

test('cadastro exige documento valido, telefone e aceite do contrato', () => {
  assert.deepEqual(validarCadastro(base), {})
  const erros = validarCadastro({ ...base, documento: '111', telefone: '', contrato: false })
  assert.ok(erros.documento)
  assert.ok(erros.telefone)
  assert.match(erros.contrato ?? '', /Contrato do Organizador/)
})

test('metadados do cadastro levam documento so com digitos e a versao do contrato', () => {
  const meta = metadadosCadastro(base)
  assert.equal(meta.documento, '52998224725')
  assert.equal(meta.telefone, '34999990000')
  assert.equal(meta.tipo_documento, 'CPF')
  assert.equal(meta.contrato_versao, CONTRATO_ORGANIZADOR_VERSAO)
  assert.deepEqual(lerMetadadosCadastro(meta), meta)
  // Conta antiga, sem os campos novos, continua sendo lida.
  const antiga = lerMetadadosCadastro({ nome: 'A', casa_nome: 'B', casa_slug: 'b', termos_versao: 'v1' })
  assert.equal(antiga?.tipo_documento, null)
  assert.equal(antiga?.contrato_versao, null)
})

test('com contrato pendente so a tela de aceite e a ajuda ficam liberadas', () => {
  assert.equal(rotaLiberadaComContratoPendente('/configuracoes/organizador'), true)
  assert.equal(rotaLiberadaComContratoPendente('/configuracoes/organizador/'), true)
  assert.equal(rotaLiberadaComContratoPendente('/ajuda/criar-evento'), true)
  assert.equal(rotaLiberadaComContratoPendente('/painel'), false)
  assert.equal(rotaLiberadaComContratoPendente('/eventos/novo'), false)
  assert.equal(rotaLiberadaComContratoPendente('/configuracoes'), false)
})

test('mensagens de erro do contrato', () => {
  assert.match(mensagemErroContrato('VERSAO_DESATUALIZADA'), /atualizado/)
  assert.match(mensagemErroContrato('DADOS_INCOMPLETOS'), /dados do organizador/)
  assert.match(mensagemErroContrato('CPF invalido: confira os numeros'), /CPF inválido/)
})

test('versao do contrato igual no app e no banco', () => {
  const migration = ler('../supabase/migrations/20261116010000_contrato_organizador.sql')
  assert.ok(migration.includes(`select '${CONTRATO_ORGANIZADOR_VERSAO}'::text`))
})

test('aceite e gravado pelo servidor com IP e sem modo suporte', () => {
  const rota = ler('../server/api/contrato/aceitar.post.ts')
  assert.ok(rota.includes('getRequestIP(event, { xForwardedFor: true })'))
  assert.ok(rota.includes("exigirAdminOrganizacaoAtiva(event)"))
  assert.ok(!rota.includes('permitirSuporte'))
  assert.ok(rota.includes("rpc('registrar_aceite_contrato'"))
})

test('painel leva o administrador para a tela de aceite (exceto modo suporte)', () => {
  const middleware = ler('../app/middleware/admin-auth.ts')
  assert.ok(middleware.includes('contratoPendente'))
  assert.ok(middleware.includes('!perfil.modoSuporte'))
  assert.ok(middleware.includes('navigateTo(TELA_DADOS_ORGANIZADOR)'))
})
