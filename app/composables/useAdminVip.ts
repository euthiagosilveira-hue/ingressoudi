import { onMounted, ref } from 'vue'

import { obterEventoAdmin } from '~/services/admin/eventos'
import {
  atualizarListaVipAdmin,
  criarListaVipAdmin,
  criarListaVipEmLoteAdmin,
  listarListaVipAdmin,
  removerListaVipAdmin
} from '~/services/admin/vip'
import type { VipConvidado, VipPayload } from '~/types/vip'

/**
 * Estado da gestao administrativa da Lista VIP de um evento.
 * Nenhuma regra de negocio aqui: apenas orquestra as RPCs.
 */
export function useAdminVip(eventoId: string) {
  const vips = ref<VipConvidado[]>([])
  const eventoNome = ref('')
  const carregando = ref(true)
  const erro = ref('')
  const processando = ref(false)

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      const [lista, evento] = await Promise.all([
        listarListaVipAdmin(eventoId),
        obterEventoAdmin(eventoId)
      ])
      vips.value = lista
      eventoNome.value = evento.nome
    } catch (e) {
      erro.value = e instanceof Error ? e.message : 'Não foi possível carregar a lista VIP.'
      vips.value = []
    } finally {
      carregando.value = false
    }
  }

  async function criar(payload: VipPayload): Promise<void> {
    processando.value = true
    try {
      await criarListaVipAdmin(eventoId, payload)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  async function criarLote(nomes: string[]): Promise<number> {
    processando.value = true
    try {
      const quantidade = await criarListaVipEmLoteAdmin(eventoId, nomes)
      await carregar()
      return quantidade
    } finally {
      processando.value = false
    }
  }

  async function atualizar(vipId: string, payload: VipPayload): Promise<void> {
    processando.value = true
    try {
      await atualizarListaVipAdmin(vipId, payload)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  async function remover(vipId: string): Promise<void> {
    processando.value = true
    try {
      await removerListaVipAdmin(vipId)
      await carregar()
    } finally {
      processando.value = false
    }
  }

  onMounted(carregar)

  return {
    vips,
    eventoNome,
    carregando,
    erro,
    processando,
    carregar,
    refresh: carregar,
    criar,
    criarLote,
    atualizar,
    remover
  }
}
