import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const nomePanel = ler('../app/components/portaria/GateNameSearchPanel.vue')
const qrPanel = ler('../app/components/portaria/GateQrScanner.vue')
const eventSelector = ler('../app/components/portaria/GateEventSelector.vue')
const header = ler('../app/components/portaria/GateHeader.vue')
const modeTabs = ler('../app/components/portaria/GateModeTabs.vue')
const gateApp = ler('../app/components/portaria/GateApp.vue')
const adminShell = ler('../app/components/AdminShell.vue')
const mobileHeader = ler('../app/components/AdminMobileHeader.vue')
const portariaPage = ler('../app/pages/portaria/index.vue')

// A) atributos mobile do campo de busca
test('A. campo de busca tem atributos mobile adequados', () => {
  assert.ok(nomePanel.includes('enterkeyhint="search"'))
  assert.ok(nomePanel.includes('autocorrect="off"'))
  assert.ok(nomePanel.includes('autocapitalize="words"'))
  assert.ok(nomePanel.includes('spellcheck="false"'))
  assert.ok(nomePanel.includes('autocomplete="off"'))
  assert.ok(nomePanel.includes('for="gate-nome"'))
})

// B/C) Enter busca e Nova busca devolve foco
test('B/C. Enter submete a busca e Nova busca devolve foco ao input', () => {
  assert.ok(nomePanel.includes('@submit.prevent="executarBusca"'))
  assert.ok(nomePanel.includes('inputNome.value?.focus()'))
  assert.ok(nomePanel.includes('ref="inputNome"'))
})

// D/E) alvos de toque
test('D/E. controles operacionais tem alvo >= 44px (size lg)', () => {
  assert.ok(nomePanel.includes('min-h-[44px]'))
  assert.ok(nomePanel.includes('size="lg"'))
  // camera QR: botoes agora em size lg
  const semSizeLg = qrPanel.match(/<AppButton(?![^>]*size="lg")[^>]*>(?:\s*(?:Ativar câmera|Pausar leitura|Continuar leitura))/g) ?? []
  assert.equal(semSizeLg.length, 0)
  // abas com altura confortavel
  assert.ok(modeTabs.includes('py-4'))
})

// F/G) textos longos e overflow
test('F/G. textos longos tratados (min-w-0/truncate/break-words)', () => {
  assert.ok(eventSelector.includes('break-words'))
  assert.ok(eventSelector.includes('min-w-0'))
  assert.ok(header.includes('truncate'))
  assert.ok(header.includes('min-w-0'))
  assert.ok(nomePanel.includes('break-words'))
  assert.ok(qrPanel.includes('break-words'))
})

// H) dialog de homonimos mantem acoes
test('H. dialog de homonimos mantem Confirmar/Cancelar', () => {
  assert.ok(nomePanel.includes('<ConfirmDialog'))
  assert.ok(nomePanel.includes('title="Confirmar entrada"'))
  assert.ok(nomePanel.includes('confirm-label="Confirmar entrada"'))
  assert.ok(nomePanel.includes('@cancel="cancelarRegistro"'))
})

// I) safe-area aplicado
test('I. safe-area aplicado em header, drawer e pagina', () => {
  assert.ok(mobileHeader.includes('env(safe-area-inset-top)'))
  assert.ok(adminShell.includes('env(safe-area-inset-bottom)'))
  assert.ok(portariaPage.includes('env(safe-area-inset-bottom)'))
})

// J) viewport dinamica
test('J. shell usa viewport dinamica (100dvh)', () => {
  assert.ok(adminShell.includes('h-[100dvh]'))
})

// K) offline nao cobre CTA (fluxo normal, sem fixed/absolute)
test('K. indicador offline nao e overlay', () => {
  const linha = gateApp.split('\n').find((l) => l.includes('Sem internet')) ?? ''
  assert.ok(linha.length > 0)
  const bloco = gateApp.slice(Math.max(0, gateApp.indexOf('v-if="!online"')), gateApp.indexOf('v-if="!online"') + 320)
  assert.ok(!/fixed|absolute|z-\d/.test(bloco))
})

// L) legado removido
test('L. utils/portaria.ts legado removido', () => {
  const caminho = fileURLToPath(new URL('../app/utils/portaria.ts', import.meta.url))
  assert.equal(existsSync(caminho), false)
  // types/portaria.ts permanece (GateMode em uso)
  assert.equal(existsSync(fileURLToPath(new URL('../app/types/portaria.ts', import.meta.url))), true)
})

// N/O/P/Q) fases anteriores preservadas
test('N/O/P/Q. QR/sessao/homonimos/retry preservados', () => {
  const scanner = ler('../app/composables/useGateScanner.ts')
  assert.ok(scanner.includes('AUTO_RESUME_DELAY_MS'))
  assert.ok(scanner.includes('deveIgnorarPorCooldown'))
  assert.ok(scanner.includes('tokenPendente'))
  assert.ok(ler('../app/utils/portariaSessao.ts').includes('registrarNaSessao'))
  assert.ok(ler('../app/utils/portariaBusca.ts').includes('itemExigeConfirmacao'))
  assert.ok(ler('../app/utils/portariaErro.ts').includes('classificarErroGate'))
})

// sem debug "Ultimo codigo"
test('debug "Ultimo codigo" removido', () => {
  assert.ok(!qrPanel.includes('Último código'))
  assert.ok(!qrPanel.includes('ultimoToken'))
})
