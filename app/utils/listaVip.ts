import type { AdminEventListItem, EventStatus } from '~/types/evento'

export interface EventoVipHub {
  eventoId: string
  nome: string
  inicioEm: string
  local: string
  status: EventStatus
}

export interface EventosVipClassificados {
  /** EM_ANDAMENTO primeiro; depois AGENDADOS por data mais proxima. */
  operacionais: EventoVipHub[]
  /** REALIZADOS (consulta historica), do mais recente para o mais antigo. */
  historicos: EventoVipHub[]
}

function mapear(evento: AdminEventListItem): EventoVipHub {
  return {
    eventoId: evento.eventoId,
    nome: evento.nome,
    inicioEm: evento.inicioEm,
    local: evento.local,
    status: evento.status
  }
}

/**
 * Classifica/ordena os eventos para o hub da Lista VIP.
 *   * EM_ANDAMENTO primeiro, depois AGENDADOS futuros (mais proximos primeiro);
 *   * REALIZADOS vao para consulta historica (mais recentes primeiro);
 *   * CANCELADOS nao aparecem.
 */
export function classificarEventosVip(eventos: AdminEventListItem[]): EventosVipClassificados {
  const operacionais = eventos
    .filter((e) => e.status === 'EM_ANDAMENTO' || e.status === 'AGENDADO')
    .map(mapear)
    .sort((a, b) => {
      const pesoA = a.status === 'EM_ANDAMENTO' ? 0 : 1
      const pesoB = b.status === 'EM_ANDAMENTO' ? 0 : 1
      if (pesoA !== pesoB) return pesoA - pesoB
      return new Date(a.inicioEm).getTime() - new Date(b.inicioEm).getTime()
    })

  const historicos = eventos
    .filter((e) => e.status === 'REALIZADO')
    .map(mapear)
    .sort((a, b) => new Date(b.inicioEm).getTime() - new Date(a.inicioEm).getTime())

  return { operacionais, historicos }
}

/** Rota canonica da gestao VIP de um evento. */
export function rotaVipEvento(eventoId: string): string {
  return `/eventos/${eventoId}/vip`
}
