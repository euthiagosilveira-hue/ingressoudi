import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { COR_PADRAO, corTextoContraste, iniciais, normalizarCor } from '../app/utils/marca.ts'
import {
  TERMOS_VERSAO,
  gerarSlug,
  lerMetadadosCadastro,
  mensagemErroCadastro,
  metadadosCadastro,
  slugValido,
  temErros,
  validarCadastro,
  type DadosCadastro
} from '../app/utils/cadastro.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('marca: normaliza cor #RRGGBB', () => {
  assert.equal(normalizarCor(' #FF00aa '), '#ff00aa')
  assert.equal(normalizarCor('#fff'), null)
  assert.equal(normalizarCor('vermelho'), null)
  assert.equal(normalizarCor(null), null)
})

test('marca: texto contrasta com a cor da casa', () => {
  assert.equal(corTextoContraste('#ffffff'), '#09090b')
  assert.equal(corTextoContraste(COR_PADRAO), '#09090b')
  assert.equal(corTextoContraste('#000000'), '#ffffff')
  assert.equal(corTextoContraste('#1d4ed8'), '#ffffff')
  assert.equal(corTextoContraste('invalida'), corTextoContraste(COR_PADRAO))
})

test('marca: iniciais da casa', () => {
  assert.equal(iniciais('Galeria Teste'), 'GT')
  assert.equal(iniciais('Bar do Samba'), 'BS')
  assert.equal(iniciais('galeria'), 'GA')
  assert.equal(iniciais('  '), '?')
})

test('cadastro: slug como o banco (sem acento, minusculo, hifens)', () => {
  assert.equal(gerarSlug('Bar do Zé!'), 'bar-do-ze')
  assert.equal(gerarSlug('  ÁGUA   Viva  '), 'agua-viva')
  assert.equal(gerarSlug('Casa_123'), 'casa-123')
  assert.equal(gerarSlug('---'), '')
  assert.ok(slugValido('casa-1'))
  assert.ok(!slugValido('casa--1'))
  assert.ok(!slugValido('-casa'))
  assert.ok(!slugValido('Casa'))
})

const valido: DadosCadastro = {
  nome: 'Ana',
  email: 'ana@exemplo.com',
  senha: 'senha-forte-1',
  confirmacao: 'senha-forte-1',
  casaNome: 'Bar do Samba',
  casaSlug: 'bar-do-samba',
  termos: true
}

test('cadastro: validacao do formulario', () => {
  assert.equal(temErros(validarCadastro(valido)), false)
  assert.ok(validarCadastro({ ...valido, termos: false }).termos)
  assert.ok(validarCadastro({ ...valido, email: 'ana' }).email)
  assert.ok(validarCadastro({ ...valido, senha: '123', confirmacao: '123' }).senha)
  assert.ok(validarCadastro({ ...valido, confirmacao: 'outra-senha' }).confirmacao)
  assert.ok(validarCadastro({ ...valido, casaSlug: 'Bar do Samba' }).casaSlug)
  assert.ok(validarCadastro({ ...valido, casaNome: ' ' }).casaNome)
})

test('cadastro: metadados levam a versao dos termos e voltam intactos', () => {
  const meta = metadadosCadastro(valido)
  assert.equal(meta.termos_versao, TERMOS_VERSAO)
  assert.deepEqual(lerMetadadosCadastro(meta), meta)
  assert.equal(lerMetadadosCadastro({ nome: 'Ana' }), null)
  assert.equal(lerMetadadosCadastro(null), null)
})

test('cadastro: mensagens de erro amigaveis', () => {
  assert.match(mensagemErroCadastro('User already registered'), /já tem conta/)
  assert.match(mensagemErroCadastro('Endereco indisponivel: escolha outro'), /endereço/)
  assert.match(mensagemErroCadastro('email rate limit exceeded'), /Aguarde/)
  assert.match(mensagemErroCadastro('qualquer coisa'), /Não foi possível/)
})

test('cadastro: paginas usam o fluxo real (signUp + RPC)', () => {
  const cadastro = ler('../app/pages/cadastro/index.vue')
  assert.ok(cadastro.includes('supabase.auth.signUp'))
  assert.ok(cadastro.includes('/cadastro/concluir'))
  assert.ok(cadastro.includes('slugDisponivel'))
  const concluir = ler('../app/pages/cadastro/concluir.vue')
  assert.ok(concluir.includes('concluirCadastroProdutor'))
  assert.ok(concluir.includes('exchangeCodeForSession'))
  const servico = ler('../app/services/auth/cadastro.ts')
  assert.ok(servico.includes("rpc('concluir_cadastro_produtor'"))
})

test('termos e privacidade publicados e linkados no checkout e no rodape', () => {
  assert.ok(ler('../app/pages/termos.vue').includes('Termos de uso'))
  assert.ok(ler('../app/pages/privacidade.vue').includes('LGPD'))
  assert.ok(ler('../app/components/public/PublicFooter.vue').includes('to="/termos"'))
  assert.ok(ler('../app/components/public/checkout/CheckoutReviewStep.vue').includes('to="/privacidade"'))
})

test('painel avisa quando a casa esta em analise', () => {
  const shell = ler('../app/components/AdminShell.vue')
  assert.ok(shell.includes('aprovada === false'))
})
