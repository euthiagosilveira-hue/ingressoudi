import { onMounted, ref } from 'vue'

import {
  ativarLoteAdmin,
  atualizarLoteAdmin,
  criarLoteAdmin,
  criarSetorAdmin,
  definirVendasEventoAdmin,
  encerrarLoteAdmin,
  excluirSetorAdmin,
  listarLotesAdmin,
  renomearSetorAdmin,
  type AtualizarLoteAdminInput,
  type CriarLoteAdminInput
} from '~/services/admin/lotes'
import type { EventListItem } from '~/types/evento'
import type { LotListItem, SetorListItem } from '~/types/lote'

/** Estado administrativo dos lotes de um evento: RPC real, loading e refresh. */
export function useAdminLots(eventoId: string) {
  const evento = ref<EventListItem | null>(null)
  const estoqueAntecipado = ref(0)
  const lotes = ref<LotListItem[]>([])
  const setores = ref<SetorListItem[]>([])
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
      setores.value = dados.setores
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os lotes.'
      evento.value = null
      lotes.value = []
      setores.value = []
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

  async function encerrar(loteId: string, ativarProximo: boolean) {
    processando.value = true
    try {
      const resultado = await encerrarLoteAdmin(loteId, ativarProximo)
      await carregar()
      return resultado
    } finally {
      processando.value = false
    }
  }

  async function executar(acao: () => Promise<void>) {
    processando.value = true
    try {
      await acao()
      await carregar()
    } finally {
      processando.value = false
    }
  }

  const criarSetor = (nome: string) => executar(() => criarSetorAdmin(eventoId, nome))
  const renomearSetor = (setorId: string, nome: string) => executar(() => renomearSetorAdmin(setorId, nome))
  const excluirSetor = (setorId: string) => executar(() => excluirSetorAdmin(setorId))

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
    setores,
    carregando,
    erro,
    processando,
    carregar,
    criar,
    atualizar,
    ativar,
    encerrar,
    abrirVendas,
    criarSetor,
    renomearSetor,
    excluirSetor,
    refresh: carregar
  }
}
