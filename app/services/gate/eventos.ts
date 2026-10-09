import type { EventoPortaria } from '~/types/gate'
import { classificarErroGate, comTimeout, mensagemErroTecnico } from '~/utils/portariaErro'

interface EventoPortariaRow {
  evento_id: string
  nome: string
  inicio_em: string
  local: string
  status: string
}

function mapear(row: EventoPortariaRow): EventoPortaria {
  return {
    eventoId: row.evento_id,
    nome: row.nome,
    inicioEm: row.inicio_em,
    local: row.local,
    status: row.status
  }
}

/** Lista eventos operacionais (AGENDADO/EM_ANDAMENTO) via RPC segura. */
export async function listarEventosPortaria(): Promise<EventoPortaria[]> {
  const client = useSupabaseClient()
  const { data, error } = await comTimeout(client.rpc('listar_eventos_portaria'))
  if (error) {
    throw new Error(mensagemErroTecnico(classificarErroGate(error)))
  }
  const rows = (data ?? []) as EventoPortariaRow[]
  return rows.map(mapear)
}
