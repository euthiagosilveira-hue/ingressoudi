import type { AdminVipRow, VipConvidado, VipPayload } from '~/types/vip'
import { mapearVipAdmin, mensagemErroVip, mensagemLoteVip } from '~/utils/vip'

/** Lista os convidados VIP do evento (RPC administrativa). */
export async function listarListaVipAdmin(
  eventoId: string,
  busca: string | null = null
): Promise<VipConvidado[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_lista_vip_admin', {
    p_evento_id: eventoId,
    p_busca: busca
  })
  if (error) throw new Error(mensagemErroVip(error))
  return ((data ?? []) as AdminVipRow[]).map(mapearVipAdmin)
}

export async function criarListaVipAdmin(eventoId: string, payload: VipPayload): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('criar_lista_vip_admin', {
    p_evento_id: eventoId,
    p_nome: payload.nome,
    p_telefone: payload.telefone,
    p_observacao: payload.observacao
  })
  if (error) throw new Error(mensagemErroVip(error))
}

export async function atualizarListaVipAdmin(vipId: string, payload: VipPayload): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('atualizar_lista_vip_admin', {
    p_vip_id: vipId,
    p_nome: payload.nome,
    p_telefone: payload.telefone,
    p_observacao: payload.observacao
  })
  if (error) throw new Error(mensagemErroVip(error))
}

export async function removerListaVipAdmin(vipId: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('remover_lista_vip_admin', { p_vip_id: vipId })
  if (error) throw new Error(mensagemErroVip(error))
}

/** Inclui varios convidados VIP de uma vez (RPC em lote, ADMINISTRADOR). */
export async function criarListaVipEmLoteAdmin(
  eventoId: string,
  nomes: string[]
): Promise<number> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('criar_lista_vip_em_lote_admin', {
    p_evento_id: eventoId,
    p_nomes: nomes
  })
  if (error) throw new Error(mensagemLoteVip(error))
  const r = data as { quantidade_criada?: number } | null
  return Number(r?.quantidade_criada ?? nomes.length)
}
