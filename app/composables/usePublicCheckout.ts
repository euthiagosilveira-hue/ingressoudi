import { computed, reactive, ref, watch } from 'vue'

import { criarReserva as criarReservaSupabase, ReservaError } from '~/services/public/reservas'
import type {
  CheckoutBuyer,
  CheckoutDraft,
  CheckoutParticipant,
  CheckoutReservation,
  CheckoutStep,
  EventoOrigem
} from '~/types/checkout'
import type { PublicEventDetail } from '~/types/publicEvento'
import {
  CHECKOUT_MIN,
  criarReservaMock,
  emailValido,
  limiteQuantidade,
  mensagemErroReserva,
  nomeValido,
  telefoneValido
} from '~/utils/checkout'

export function usePublicCheckout(
  evento: PublicEventDetail,
  options: { origem?: EventoOrigem } = {}
) {
  const origem: EventoOrigem = options.origem ?? 'SUPABASE'

  const step = ref<CheckoutStep>('QUANTIDADE')

  const quantidade = ref(CHECKOUT_MIN)
  const participantes = ref<CheckoutParticipant[]>([{ nome: '' }])
  const comprador = reactive<CheckoutBuyer>({ nome: '', telefone: '', email: '' })

  const reserva = ref<CheckoutReservation | null>(null)
  const criando = ref(false)
  const erroReserva = ref('')

  const errosParticipantes = ref<string[]>([])
  const erroCompradorNome = ref('')
  const erroCompradorTelefone = ref('')
  const erroCompradorEmail = ref('')

  const preco = computed(() => evento.preco)
  const disponiveis = computed(() => evento.disponiveis)
  const maximo = computed(() => limiteQuantidade(disponiveis.value))
  const total = computed(() => (preco.value ?? 0) * quantidade.value)

  watch(quantidade, (valor) => {
    sincronizarParticipantes(valor)
  })

  function sincronizarParticipantes(valor: number) {
    const atual = participantes.value
    if (valor > atual.length) {
      const extras = Array.from({ length: valor - atual.length }, () => ({ nome: '' }))
      participantes.value = [...atual, ...extras]
      return
    }
    if (valor < atual.length) {
      participantes.value = atual.slice(0, valor)
      errosParticipantes.value = errosParticipantes.value.slice(0, valor)
    }
  }

  function definirQuantidade(valor: number) {
    quantidade.value = Math.min(Math.max(valor, CHECKOUT_MIN), maximo.value)
  }

  function atualizarParticipante(indice: number, nome: string) {
    const lista = [...participantes.value]
    lista[indice] = { nome }
    participantes.value = lista
  }

  function validarQuantidade(): boolean {
    return quantidade.value >= CHECKOUT_MIN && quantidade.value <= maximo.value
  }

  function validarParticipantes(): boolean {
    const erros = participantes.value.map((participante) =>
      nomeValido(participante.nome) ? '' : 'Informe o nome do participante.'
    )
    errosParticipantes.value = erros
    return erros.every((erro) => erro === '')
  }

  function validarComprador(): boolean {
    erroCompradorNome.value = nomeValido(comprador.nome) ? '' : 'Informe o nome completo.'
    erroCompradorTelefone.value = telefoneValido(comprador.telefone)
      ? ''
      : 'Informe um telefone válido com DDD.'
    if (comprador.email.trim() === '') {
      erroCompradorEmail.value = 'E-mail é obrigatório.'
    } else if (!emailValido(comprador.email)) {
      erroCompradorEmail.value = 'Informe um e-mail válido.'
    } else {
      erroCompradorEmail.value = ''
    }
    return !erroCompradorNome.value && !erroCompradorTelefone.value && !erroCompradorEmail.value
  }

  function montarDraft(): CheckoutDraft {
    return {
      quantidade: quantidade.value,
      participantes: participantes.value.map((participante) => ({ ...participante })),
      comprador: { ...comprador }
    }
  }

  function proximo() {
    if (step.value === 'QUANTIDADE') {
      if (!validarQuantidade()) return
      step.value = 'PARTICIPANTES'
      return
    }
    if (step.value === 'PARTICIPANTES') {
      if (!validarParticipantes()) return
      step.value = 'COMPRADOR'
      return
    }
    if (step.value === 'COMPRADOR') {
      if (!validarComprador()) return
      step.value = 'REVISAO'
      return
    }
    if (step.value === 'REVISAO') {
      void criarReserva()
    }
  }

  function voltar() {
    if (step.value === 'PARTICIPANTES') step.value = 'QUANTIDADE'
    else if (step.value === 'COMPRADOR') step.value = 'PARTICIPANTES'
    else if (step.value === 'REVISAO') step.value = 'COMPRADOR'
  }

  function irPara(destino: CheckoutStep) {
    step.value = destino
  }

  async function criarReserva() {
    if (criando.value) return
    erroReserva.value = ''
    criando.value = true
    try {
      const draft = montarDraft()
      // Reserva mock apenas em desenvolvimento e para eventos de demonstracao.
      if (import.meta.dev && origem === 'MOCK') {
        await new Promise((resolve) => setTimeout(resolve, 600))
        reserva.value = criarReservaMock(evento, draft)
      } else {
        reserva.value = await criarReservaSupabase(evento.eventoId, draft)
      }
      step.value = 'RESERVA_CRIADA'
    } catch (erro) {
      const codigo = erro instanceof ReservaError ? erro.code : 'ERRO_INESPERADO'
      erroReserva.value = mensagemErroReserva(codigo)
    } finally {
      criando.value = false
    }
  }

  return {
    origem,
    step,
    quantidade,
    participantes,
    comprador,
    reserva,
    criando,
    erroReserva,
    errosParticipantes,
    erroCompradorNome,
    erroCompradorTelefone,
    erroCompradorEmail,
    preco,
    disponiveis,
    maximo,
    total,
    definirQuantidade,
    atualizarParticipante,
    proximo,
    voltar,
    irPara,
    criarReserva
  }
}
