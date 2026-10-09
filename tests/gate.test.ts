import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  LeituraLock,
  chaveBuscaPortaria,
  descricaoResultadoEntrada,
  ingressoRegistravel,
  mapearResultadoEntradaRpc,
  mascararToken,
  mensagemDominioSegura,
  nomeBuscaValido,
  normalizarMensagemEntrada,
  qrTokenPlausivel,
  rotuloResultadoEntrada,
  uuidValido
} from '../app/utils/gate.ts'

test('qrTokenPlausivel aceita token opaco e rejeita vazio/curto/com espaco', () => {
  assert.equal(qrTokenPlausivel('5f5d84c2-1111-2222-3333-abcdefabcdef'), true)
  assert.equal(qrTokenPlausivel('abc12345'), true)
  assert.equal(qrTokenPlausivel(''), false)
  assert.equal(qrTokenPlausivel('   '), false)
  assert.equal(qrTokenPlausivel('abc'), false)
  assert.equal(qrTokenPlausivel('token com espaco'), false)
})

test('uuidValido valida evento id', () => {
  assert.equal(uuidValido('5f5d84c2-1111-2222-3333-abcdefabcdef'), true)
  assert.equal(uuidValido('evt_001'), false)
  assert.equal(uuidValido(''), false)
})

test('mascararToken nunca expoe o token completo', () => {
  const token = '5f5d84c2-1111-2222-3333-abcdefabcdef'
  const mascarado = mascararToken(token)
  assert.equal(mascarado, '5f5d****ef')
  assert.equal(mascarado.includes(token), false)
  assert.equal(mascararToken(''), '')
  assert.equal(mascararToken('curto'), '****')
})

test('LeituraLock bloqueia leitura duplicada ate liberar', () => {
  const lock = new LeituraLock()
  assert.equal(lock.podeProcessar(), true)
  lock.bloquear()
  assert.equal(lock.podeProcessar(), false)
  lock.liberar()
  assert.equal(lock.podeProcessar(), true)
})

test('fluxo de trava: uma leitura processa, as imediatas sao ignoradas, reset libera', () => {
  const lock = new LeituraLock()
  let chamadas = 0
  // simula o composable: so chama a RPC se o lock permitir
  const aoDetectar = () => {
    if (!lock.podeProcessar()) return
    lock.bloquear()
    chamadas += 1
  }
  aoDetectar() // 1a deteccao -> processa
  aoDetectar() // deteccoes repetidas no mesmo frame -> ignoradas
  aoDetectar()
  assert.equal(chamadas, 1)
  lock.liberar() // reset para proximo
  aoDetectar()
  assert.equal(chamadas, 2)
})

test('mapearResultadoEntradaRpc normaliza jsonb real da RPC', () => {
  const r = mapearResultadoEntradaRpc({
    resultado: 'LIBERADO',
    ingresso_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    codigo: 'GZ100089-01',
    participante_nome: 'Cliente Teste',
    entrada_id: '11111111-2222-3333-4444-555555555555',
    entrada_em: '2026-09-29T12:00:00Z',
    mensagem: 'Entrada liberada'
  })
  assert.equal(r.resultado, 'LIBERADO')
  assert.equal(r.codigo, 'GZ100089-01')
  assert.equal(r.participanteNome, 'Cliente Teste')
  assert.equal(r.entradaEm, '2026-09-29T12:00:00Z')
})

test('mapearResultadoEntradaRpc lida com campos ausentes', () => {
  const r = mapearResultadoEntradaRpc({ resultado: 'NAO_ENCONTRADO' })
  assert.equal(r.resultado, 'NAO_ENCONTRADO')
  assert.equal(r.ingressoId, null)
  assert.equal(r.codigo, null)
  assert.equal(r.mensagem, '')
})

test('rotuloResultadoEntrada marca sucesso apenas para LIBERADO', () => {
  assert.equal(rotuloResultadoEntrada('LIBERADO').sucesso, true)
  assert.equal(rotuloResultadoEntrada('JA_UTILIZADO').sucesso, false)
  assert.equal(rotuloResultadoEntrada('NAO_ENCONTRADO').sucesso, false)
  assert.equal(rotuloResultadoEntrada('EVENTO_INCORRETO').sucesso, false)
  assert.equal(rotuloResultadoEntrada('CANCELADO').sucesso, false)
  assert.equal(rotuloResultadoEntrada('INVALIDO').sucesso, false)
})

// --- motivo real da RPC na descricao -----------------------------------------

test('INVALIDO + EVENTO_NAO_INICIADO usa a mensagem real normalizada', () => {
  assert.equal(
    descricaoResultadoEntrada('INVALIDO', 'Evento ainda nao iniciado'),
    'Evento ainda não iniciado.'
  )
  assert.equal(rotuloResultadoEntrada('INVALIDO').titulo, 'Ingresso inválido')
})

test('INVALIDO + evento realizado usa a mensagem real', () => {
  assert.equal(
    descricaoResultadoEntrada('INVALIDO', 'Evento ja realizado'),
    'Evento já realizado.'
  )
})

test('INVALIDO sem mensagem cai no texto generico', () => {
  assert.equal(
    descricaoResultadoEntrada('INVALIDO', null),
    'Este ingresso não pode ser utilizado.'
  )
  assert.equal(
    descricaoResultadoEntrada('INVALIDO'),
    'Este ingresso não pode ser utilizado.'
  )
})

test('JA_UTILIZADO usa mensagem real quando disponivel', () => {
  assert.equal(
    descricaoResultadoEntrada('JA_UTILIZADO', 'Ingresso ja utilizado'),
    'Ingresso já utilizado.'
  )
})

test('CANCELADO usa mensagem real quando disponivel', () => {
  assert.equal(
    descricaoResultadoEntrada('CANCELADO', 'Ingresso cancelado'),
    'Ingresso cancelado.'
  )
})

test('LIBERADO mantem descricao de sucesso (ignora mensagem crua)', () => {
  assert.equal(descricaoResultadoEntrada('LIBERADO', 'Entrada liberada'), 'Entrada registrada com sucesso.')
})

test('mensagem tecnica/ID nunca é exibida (fallback generico)', () => {
  assert.equal(mensagemDominioSegura('erro 0ba5ced9-ce32-4935-b44a-577acfe160fe'), false)
  assert.equal(mensagemDominioSegura('SQLSTATE 42501 exception'), false)
  assert.equal(mensagemDominioSegura('ok'), true)
  assert.equal(
    descricaoResultadoEntrada('INVALIDO', 'erro 0ba5ced9-ce32-4935-b44a-577acfe160fe'),
    'Este ingresso não pode ser utilizado.'
  )
})

test('normalizarMensagemEntrada cobre conhecidas e adiciona ponto', () => {
  assert.equal(normalizarMensagemEntrada('Ingresso ja utilizado'), 'Ingresso já utilizado.')
  assert.equal(normalizarMensagemEntrada('Mensagem nova sem ponto'), 'Mensagem nova sem ponto.')
  assert.equal(normalizarMensagemEntrada('Ja com ponto.'), 'Ja com ponto.')
})

test('nomeBuscaValido exige nome com pelo menos 2 caracteres', () => {
  assert.equal(nomeBuscaValido(''), false)
  assert.equal(nomeBuscaValido('   '), false)
  assert.equal(nomeBuscaValido('a'), false)
  assert.equal(nomeBuscaValido('ab'), true)
  assert.equal(nomeBuscaValido('  João Silva  '), true)
})

test('ingressoRegistravel: somente VALIDO e registravel (UTILIZADO visivel mas nao registra)', () => {
  assert.equal(ingressoRegistravel('VALIDO'), true)
  assert.equal(ingressoRegistravel('UTILIZADO'), false)
  assert.equal(ingressoRegistravel('CANCELADO'), false)
  assert.equal(ingressoRegistravel('EXPIRADO'), false)
  assert.equal(ingressoRegistravel('RESERVADO'), false)
})

test('mapearResultadoEntradaRpc expoe vip_id quando presente', () => {
  const r = mapearResultadoEntradaRpc({
    resultado: 'LIBERADO',
    vip_id: 'vvvvvvvv-1111-2222-3333-444444444444',
    participante_nome: 'Convidado VIP',
    entrada_id: 'eeeeeeee-1111-2222-3333-444444444444',
    entrada_em: '2026-10-07T22:00:00Z',
    mensagem: 'Entrada liberada'
  })
  assert.equal(r.vipId, 'vvvvvvvv-1111-2222-3333-444444444444')
  assert.equal(r.ingressoId, null)
})

test('chaveBuscaPortaria distingue ingresso e VIP', () => {
  assert.equal(
    chaveBuscaPortaria({
      origem: 'VIP',
      ingressoId: null,
      vipId: 'v1',
      codigo: null,
      participanteNome: 'VIP',
      status: 'VALIDO',
      utilizadoEm: null,
      entradaEm: null
    }),
    'VIP-v1'
  )
  assert.equal(
    chaveBuscaPortaria({
      origem: 'INGRESSO',
      ingressoId: 'i1',
      vipId: null,
      codigo: 'GZ1-01',
      participanteNome: 'Cliente',
      status: 'VALIDO',
      utilizadoEm: null,
      entradaEm: null
    }),
    'INGRESSO-i1'
  )
})
