import { mapearEventoPlataforma, type EventoPlataforma } from '~/utils/eventosPlataforma'
import {
  mapearResumoExclusao,
  mensagemErroExclusao,
  type ResumoExclusaoEvento
} from '~/utils/excluirEvento'

/** Todos os eventos de todas as casas (somente super admin). */
export async function listarEventosPlataforma(): Promise<EventoPlataforma[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_plataforma')
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê os eventos de todas as casas.')
    throw new Error('Não foi possível carregar os eventos.')
  }
  return ((data ?? []) as Array<Record<string, unknown>>).map(mapearEventoPlataforma)
}

/** O que será apagado junto com o evento (somente super admin). */
export async function obterResumoExclusaoEvento(eventoId: string): Promise<ResumoExclusaoEvento> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('resumo_exclusao_evento', { p_evento_id: eventoId })
  if (error) throw new Error(mensagemErroExclusao(error.message))
  return mapearResumoExclusao((data ?? {}) as Record<string, unknown>)
}

/** Exclui o evento e tudo que depende dele (somente super admin). */
export async function excluirEventoPlataforma(eventoId: string, apagarVendasPagas: boolean): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('excluir_evento_plataforma', {
    p_evento_id: eventoId,
    p_apagar_vendas_pagas: apagarVendasPagas
  })
  if (error) throw new Error(mensagemErroExclusao(error.message))
}
