import type { EventStatus, PublicationStatus, SalesStatus } from '../types/evento.ts'
import { imagemValida } from './imagem.ts'

/** Evento de qualquer casa, como o super admin ve em Plataforma > Todos os eventos. */
export interface EventoPlataforma {
  id: string
  nome: string
  slug: string
  imagemUrl: string | null
  inicioEm: string
  local: string
  status: EventStatus
  vendasStatus: SalesStatus
  publicacaoStatus: PublicationStatus
  criadoEm: string
  meiaEntradaAtiva: boolean
  organizacaoId: string
  organizacaoNome: string
  organizacaoSlug: string
  vendidos: number
  disponiveis: number
  pedidosPagos: number
  valorVendido: number
  taxaPlataforma: number
  loteAtual: { nome: string; preco: number } | null
}

export type SituacaoEvento = 'PROXIMOS' | 'PASSADOS' | 'TODOS'

export interface FiltroEventosPlataforma {
  busca: string
  organizacaoId: string
  situacao: SituacaoEvento
}

const n = (v: unknown) => Number(v ?? 0) || 0

export function mapearEventoPlataforma(row: Record<string, unknown>): EventoPlataforma {
  const lote = row.lote_atual as Record<string, unknown> | null | undefined
  return {
    id: String(row.evento_id ?? ''),
    nome: String(row.nome ?? ''),
    slug: String(row.slug ?? ''),
    imagemUrl: imagemValida(row.imagem_url as string | null),
    inicioEm: String(row.inicio_em ?? ''),
    local: String(row.local ?? ''),
    status: row.status as EventStatus,
    vendasStatus: row.vendas_status as SalesStatus,
    publicacaoStatus: row.publicacao_status as PublicationStatus,
    criadoEm: String(row.criado_em ?? ''),
    meiaEntradaAtiva: row.meia_entrada_ativa === true,
    organizacaoId: String(row.organizacao_id ?? ''),
    organizacaoNome: String(row.organizacao_nome ?? ''),
    organizacaoSlug: String(row.organizacao_slug ?? ''),
    vendidos: n(row.vendidos),
    disponiveis: n(row.disponiveis),
    pedidosPagos: n(row.pedidos_pagos),
    valorVendido: n(row.valor_vendido),
    taxaPlataforma: n(row.taxa_plataforma),
    loteAtual: lote ? { nome: String(lote.nome ?? ''), preco: n(lote.preco) } : null
  }
}

function normalizar(texto: string): string {
  return texto.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim()
}

/** Proximo = ainda nao terminou (agendado ou em andamento). */
export function eventoEhProximo(evento: EventoPlataforma): boolean {
  return evento.status === 'AGENDADO' || evento.status === 'EM_ANDAMENTO'
}

/**
 * Filtra por casa, situacao e busca (nome do evento, casa ou local).
 * Proximos vem do mais perto para o mais longe; os demais, do mais recente.
 */
export function filtrarEventosPlataforma(
  eventos: EventoPlataforma[],
  filtro: FiltroEventosPlataforma
): EventoPlataforma[] {
  const termo = normalizar(filtro.busca)
  const lista = eventos.filter((e) => {
    if (filtro.organizacaoId && e.organizacaoId !== filtro.organizacaoId) return false
    if (filtro.situacao === 'PROXIMOS' && !eventoEhProximo(e)) return false
    if (filtro.situacao === 'PASSADOS' && eventoEhProximo(e)) return false
    if (termo && !normalizar(`${e.nome} ${e.organizacaoNome} ${e.local}`).includes(termo)) return false
    return true
  })
  const ordem = filtro.situacao === 'PROXIMOS' ? 1 : -1
  return [...lista].sort((a, b) => ordem * a.inicioEm.localeCompare(b.inicioEm))
}

/** Casas que aparecem na lista, em ordem alfabetica, para o filtro. */
export function casasDosEventos(eventos: EventoPlataforma[]): Array<{ id: string; nome: string }> {
  const mapa = new Map<string, string>()
  for (const e of eventos) mapa.set(e.organizacaoId, e.organizacaoNome)
  return [...mapa.entries()]
    .map(([id, nome]) => ({ id, nome }))
    .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'))
}

export function resumirEventosPlataforma(eventos: EventoPlataforma[]) {
  return {
    eventos: eventos.length,
    casas: new Set(eventos.map((e) => e.organizacaoId)).size,
    ingressosVendidos: eventos.reduce((s, e) => s + e.vendidos, 0),
    valorVendido: Math.round(eventos.reduce((s, e) => s + e.valorVendido, 0) * 100) / 100,
    taxaPlataforma: Math.round(eventos.reduce((s, e) => s + e.taxaPlataforma, 0) * 100) / 100
  }
}
