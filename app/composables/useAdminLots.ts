import { onMounted, ref } from 'vue'

import {
  ativarLoteAdmin,
  atualizarLoteAdmin,
  criarLoteAdmin,
  definirVendasEventoAdmin,
  listarLotesAdmin,
  type AtualizarLoteAdminInput,
  type CriarLoteAdminInput
} from '~/services/admin/lotes'
import type { EventListItem } from '~/types/evento'
import type { LotListItem } from '~/types/lote'

/** Estado administrativo dos lotes de um evento: RPC real, loading e refresh. */
export function useAdminLots(eventoId: string) {
  const evento = ref<EventListItem | null>(null)
  const estoqueAntecipado = ref(0)
  const lotes = ref<LotListItem[]>([])
  const carregando = ref(true)
  const erro = ref('')
  const processando = ref(false)

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      const dados = await listarLotesAdmin(eventoId)
      evento.value = dados.evento
      estoqueAntecipado.value = dados.estoqueAntecipado
      lotes.value = dados.lotes
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os lotes.'
      evento.value = null
      lotes.value = []
    } finally {
      carregando.value = false
    }
  }

  async function criar(input: CriarLoteAdminInput) {
    processando.value = true
    try {
      await criarLoteAdmin(eventoId, input)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  async function atualizar(loteId: string, input: AtualizarLoteAdminInput) {
    processando.value = true
    try {
      await atualizarLoteAdmin(loteId, input)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  async function ativar(loteId: string) {
    processando.value = true
    try {
      await ativarLoteAdmin(loteId)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  async function abrirVendas() {
    processando.value = true
    try {
      await definirVendasEventoAdmin(eventoId, 'ABERTAS')
      await carregar()
    } finally {
      processando.value = false
    }
  }

  onMounted(() => {
    void carregar()
  })

  return {
    evento,
    estoqueAntecipado,
    lotes,
    carregando,
    erro,
    processando,
    carregar,
    criar,
    atualizar,
    ativar,
    abrirVendas,
    refresh: carregar
  }
}
