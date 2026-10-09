import type { IngressoBuscaNome, RegistrarEntradaQrResult, TipoErroGate } from '~/types/gate'
import { mapearResultadoEntradaRpc } from '~/utils/gate'
import { classificarErroGate, comTimeout } from '~/utils/portariaErro'

export class GateError extends Error {
  code: TipoErroGate

  constructor(code: TipoErroGate, message: string) {
    super(message)
    this.name = 'GateError'
    this.code = code
  }
}

/** Classifica erro tecnico de transporte (nunca resultado de negocio). */
function mapearErro(error: unknown): GateError {
  return new GateError(classificarErroGate(error), 'Falha na comunicação com o sistema.')
}

interface BuscaRow {
  origem?: string | null
  ingresso_id?: string | null
  vip_id?: string | null
  codigo?: string | null
  participante_nome: string
  status: string
  utilizado_em?: string | null
  entrada_em?: string | null
  telefone?: string | null
}

/**
 * Busca por nome no evento (ingressos + Lista VIP) via RPC unificada.
 * Campo `origem` discrimina INGRESSO | VIP. Sem merge improvisado no frontend.
 */
export async function buscarIngressosPorNome(input: {
  eventoId: string
  nome: string
}): Promise<IngressoBuscaNome[]> {
  const client = useSupabaseClient()
  const { data, error } = await comTimeout(
    client.rpc('buscar_ingressos_por_nome', {
      p_evento_id: input.eventoId,
      p_nome: input.nome
    })
  )
  if (error) throw mapearErro(error)

  const rows = (data ?? []) as BuscaRow[]
  return rows.map((row) => ({
    origem: row.origem === 'VIP' ? 'VIP' : 'INGRESSO',
    ingressoId: row.ingresso_id ?? null,
    vipId: row.vip_id ?? null,
    codigo: row.codigo ?? null,
    participanteNome: row.participante_nome,
    status: row.status,
    utilizadoEm: row.utilizado_em ?? null,
    entradaEm: row.entrada_em ?? null,
    telefone: row.telefone ?? null
  }))
}

/** Registra entrada pelo ingresso selecionado (RPC registrar_entrada_nome). */
export async function registrarEntradaNome(input: {
  eventoId: string
  ingressoId: string
}): Promise<RegistrarEntradaQrResult> {
  const client = useSupabaseClient()
  const { data, error } = await comTimeout(
    client.rpc('registrar_entrada_nome', {
      p_evento_id: input.eventoId,
      p_ingresso_id: input.ingressoId
    })
  )
  if (error) throw mapearErro(error)
  return mapearResultadoEntradaRpc(data as Record<string, unknown>)
}

/** Registra entrada de convidado VIP (RPC registrar_entrada_vip). */
export async function registrarEntradaVip(input: {
  eventoId: string
  vipId: string
}): Promise<RegistrarEntradaQrResult> {
  const client = useSupabaseClient()
  const { data, error } = await comTimeout(
    client.rpc('registrar_entrada_vip', {
      p_evento_id: input.eventoId,
      p_vip_id: input.vipId
    })
  )
  if (error) throw mapearErro(error)
  return mapearResultadoEntradaRpc(data as Record<string, unknown>)
}
