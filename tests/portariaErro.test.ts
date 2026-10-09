import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  REQUEST_TIMEOUT_MS,
  classificarErroGate,
  comTimeout,
  ehErroTecnico,
  estaOffline,
  mensagemErroTecnico
} from '../app/utils/portariaErro.ts'
import { registrarNaSessao, SESSAO_VAZIA } from '../app/utils/portariaSessao.ts'
import { deveAutoRetomar } from '../app/utils/portariaQr.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const scanner = ler('../app/composables/useGateScanner.ts')
const busca = ler('../app/composables/useGateNameSearch.ts')
const qrPanel = ler('../app/components/portaria/GateQrScanner.vue')
const nomePanel = ler('../app/components/portaria/GateNameSearchPanel.vue')
const conectividade = ler('../app/composables/useGateConectividade.ts')
const gateApp = ler('../app/components/portaria/GateApp.vue')
const eventosService = ler('../app/services/gate/eventos.ts')
const pagina = ler('../app/pages/portaria/index.vue')

// A) OFFLINE
test('A. sem conexao -> OFFLINE', () => {
  assert.equal(estaOffline({ onLine: false }), true)
  assert.equal(classificarErroGate({}, { online: false }), 'OFFLINE')
  assert.equal(classificarErroGate(new TypeError('Failed to fetch'), { online: false }), 'OFFLINE')
})

// B) TIMEOUT
test('B. abort/timeout -> TIMEOUT', () => {
  assert.equal(classificarErroGate(new DOMException('x', 'AbortError'), { online: true }), 'TIMEOUT')
  assert.equal(classificarErroGate({ message: 'request timeout' }, { online: true }), 'TIMEOUT')
})

// C) SERVIDOR INDISPONIVEL
test('C. rede/5xx -> SERVIDOR_INDISPONIVEL', () => {
  assert.equal(
    classificarErroGate({ message: 'Failed to fetch' }, { online: true }),
    'SERVIDOR_INDISPONIVEL'
  )
  assert.equal(classificarErroGate({ status: 503 }, { online: true }), 'SERVIDOR_INDISPONIVEL')
  assert.equal(classificarErroGate({ statusCode: 500 }, { online: true }), 'SERVIDOR_INDISPONIVEL')
})

// D) SEM PERMISSAO
test('D. permissao/jwt -> SEM_PERMISSAO', () => {
  assert.equal(classificarErroGate({ code: '42501' }, { online: true }), 'SEM_PERMISSAO')
  assert.equal(classificarErroGate({ message: 'JWT expired' }, { online: true }), 'SEM_PERMISSAO')
  assert.equal(classificarErroGate({ message: 'permissao negada' }, { online: true }), 'SEM_PERMISSAO')
})

// E) DESCONHECIDO
test('E. fallback -> DESCONHECIDO', () => {
  assert.equal(classificarErroGate({ message: 'algo inesperado' }, { online: true }), 'DESCONHECIDO')
  assert.equal(classificarErroGate(null, { online: true }), 'DESCONHECIDO')
})

// F) resultado de negocio nao e erro tecnico
test('F. resultado de negocio nao e classificado como erro tecnico', () => {
  assert.equal(ehErroTecnico('LIBERADO'), false)
  assert.equal(ehErroTecnico('JA_UTILIZADO'), false)
  assert.equal(ehErroTecnico('OFFLINE'), true)
  assert.equal(ehErroTecnico('SEM_EVENTO'), false)
})

// W) mensagens fixas e seguras
test('W. mensagens de erro sao fixas e sem dado sensivel', () => {
  const todas = [
    mensagemErroTecnico('OFFLINE'),
    mensagemErroTecnico('TIMEOUT'),
    mensagemErroTecnico('SERVIDOR_INDISPONIVEL'),
    mensagemErroTecnico('SEM_PERMISSAO'),
    mensagemErroTecnico('DESCONHECIDO')
  ]
  for (const msg of todas) {
    assert.ok(msg.length > 0)
    assert.ok(!/sqlstate|exception|select |insert |uuid|[0-9a-f]{8}-[0-9a-f]{4}/i.test(msg))
    assert.ok(!msg.toLowerCase().includes('inválido'))
  }
})

// timeout helper
test('comTimeout resolve rapido e rejeita quando estoura', async () => {
  assert.equal(await comTimeout(Promise.resolve(42), 200), 42)
  await assert.rejects(() => comTimeout(new Promise(() => {}), 20))
  assert.equal(REQUEST_TIMEOUT_MS >= 5000, true)
})

// G/H/I/J/K/L) QR retry
test('G. erro tecnico de QR nao agenda auto-resume', () => {
  assert.equal(
    deveAutoRetomar({ autoHabilitado: true, temResultado: false, erroTecnico: true }),
    false
  )
})

test('H/I/J. retry QR reutiliza o token, ignora cooldown e chama RPC uma vez', () => {
  assert.ok(scanner.includes('tokenPendente'))
  assert.ok(scanner.includes('const token = tokenPendente.value'))
  assert.ok(/function tentarNovamente\(\)[\s\S]*?limparCooldown\(\)[\s\S]*?executarRegistro\(token\)/.test(scanner))
  assert.ok(scanner.includes('if (!token || processando.value) return'))
})

test('K/L. retry usa o mesmo reducer (LIBERADO conta, JA_UTILIZADO nao)', () => {
  const um = registrarNaSessao(SESSAO_VAZIA, {
    resultado: 'LIBERADO',
    nome: 'X',
    tipo: 'INGRESSO',
    horario: '10:00'
  })
  assert.equal(um.total, 1)
  const dois = registrarNaSessao(um, {
    resultado: 'JA_UTILIZADO',
    nome: 'X',
    tipo: 'INGRESSO',
    horario: '10:01'
  })
  assert.equal(dois.total, 1)
})

// M/N/O/P) busca/registro preservam contexto
test('M/N. erro de busca preserva o nome e permite retry', () => {
  assert.ok(busca.includes("contextoErro.value = 'BUSCA'"))
  assert.ok(busca.includes('function tentarBuscarNovamente()'))
  assert.ok(/tentarBuscarNovamente\(\)[\s\S]*?buscar\(\)/.test(busca))
  assert.ok(!/catch \(e\) \{[\s\S]{0,120}nome\.value = ''/.test(busca))
})

test('O/P. erro de registro preserva o item (inclusive VIP) para retry', () => {
  assert.ok(busca.includes('itemParaRetry.value = ingresso'))
  assert.ok(busca.includes("contextoErro.value = 'REGISTRO'"))
  assert.ok(busca.includes('function tentarRegistrarNovamente()'))
  assert.ok(/tentarRegistrarNovamente\(\)[\s\S]*?registrar\(item\)/.test(busca))
})

// Q) loading impede duplo retry
test('Q. loading impede retry/registro duplicado', () => {
  assert.ok(scanner.includes('processando.value || desmontado'))
  assert.ok(busca.includes('if (!item || registrando.value) return'))
  assert.ok(busca.includes('if (buscando.value) return'))
  assert.ok(qrPanel.includes(':disabled="processando"'))
  assert.ok(nomePanel.includes(':disabled="registrando"'))
})

// R) falha ao carregar eventos != "sem eventos"
test('R. falha ao carregar eventos vira erro, nao estado vazio', () => {
  assert.ok(eventosService.includes('classificarErroGate'))
  assert.ok(eventosService.includes('mensagemErroTecnico'))
  assert.ok(pagina.includes('v-else-if="erro"'))
  assert.ok(pagina.includes('Tentar novamente'))
  assert.ok(pagina.includes('<GateApp v-else'))
})

// S/T/U) conectividade
test('S/T/U. listener offline atualiza indicador, sem retry automatico, com cleanup', () => {
  assert.ok(conectividade.includes("addEventListener('online'"))
  assert.ok(conectividade.includes("addEventListener('offline'"))
  assert.ok(conectividade.includes("removeEventListener('online'"))
  assert.ok(conectividade.includes("removeEventListener('offline'"))
  assert.ok(!conectividade.includes('tentarNovamente'))
  assert.ok(!conectividade.includes('executarRegistro'))
  assert.ok(gateApp.includes('Sem internet'))
})

// V) erro tecnico nao emite som/vibracao de resultado
test('V. erro tecnico nao emite feedback de resultado', () => {
  const idxCatch = scanner.indexOf('erro.value = e instanceof GateError')
  assert.ok(idxCatch > 0)
  const trecho = scanner.slice(idxCatch, idxCatch + 220)
  assert.ok(!trecho.includes('emitirFeedbackEntrada'))
})

// painel de QR mostra acoes de retry para erro tecnico
test('QR: painel oferece Tentar novamente e Ler outro codigo', () => {
  assert.ok(qrPanel.includes('Tentar novamente'))
  assert.ok(qrPanel.includes('Ler outro código'))
  assert.ok(qrPanel.includes('retentativaPendente'))
})
