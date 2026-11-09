import {
  mapearEventosSocio,
  mapearVendasEventoSocio,
  mensagemErroSocio,
  type EventoSocio,
  type VendasEventoSocio
} from '~/utils/socio'

/** Eventos que o Socio do Evento logado acompanha, com o resumo de vendas. */
export async function listarEventosSocio(): Promise<EventoSocio[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_socio')
  if (error) throw new Error(mensagemErroSocio(error))
  return mapearEventosSocio(data)
}

/** Numeros de venda de um evento do socio (sem dados de compradores). */
export async function obterVendasEventoSocio(eventoId: string): Promise<VendasEventoSocio> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_vendas_evento_socio', { p_evento_id: eventoId })
  if (error) throw new Error(mensagemErroSocio(error))
  return mapearVendasEventoSocio(data)
}
