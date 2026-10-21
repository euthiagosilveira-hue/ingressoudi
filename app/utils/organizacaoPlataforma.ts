import type { EventStatus, PublicationStatus, SalesStatus } from '../types/evento.ts'

/** Uma casa vista pelo super admin em Plataforma > Organizacoes > detalhes. */
export interface DonoCasa {
  usuarioId: string
  nome: string
  email: string
  ativo: boolean
  cadastradoEm: string | null
  ultimoAcessoEm: string | null
  emailConfirmado: boolean
  termosVersao: string | null
  termosAceitosEm: string | null
  outrasCasas: number
}

export interface MembroCasa {
  usuarioId: string
  nome: string
  email: string
  perfil: 'ADMINISTRADOR' | 'PORTARIA'
  ativo: boolean
  dono: boolean
  ultimoAcessoEm: string | null
}

export interface EventoDaCasa {
  id: string
  nome: string
  slug: string
  inicioEm: string
  local: string
  status: EventStatus
  publicacaoStatus: PublicationStatus
  vendasStatus: SalesStatus
  capacidadeTotal: number
  vendidos: number
  utilizados: number
  pedidosPagos: number
  valorVendido: number
  valorOnline: number
  valorDinheiro: number
  taxaPlataforma: number
}

export interface MetricasCasa {
  eventosTotal: number
  eventosPublicados: number
  eventosAtivos: number
  eventosVendasAbertas: number
  eventosRealizados: number
  eventosCancelados: number
  eventosRascunho: number
  ingressosVendidos: number
  ingressosUtilizados: number
  pedidosPagos: number
  valorVendido: number
  valorOnline: number
  valorDinheiro: number
  taxaPlataforma: number
  valorReembolsado: number
  proximoEventoEm: string | null
}

export interface DetalheCasa {
  organizacao: {
    id: string
    nome: string
    slug: string
    ativo: boolean
    aprovada: boolean
    listaVip: boolean
    taxaServico: number
    criadoEm: string
    mercadoPago: { conectadoEm: string | null; producao: boolean } | null
  }
  dono: DonoCasa | null
  equipe: MembroCasa[]
  metricas: MetricasCasa
  eventos: EventoDaCasa[]
}

type Linha = Record<string, unknown>
const n = (v: unknown) => Number(v ?? 0) || 0
const s = (v: unknown) => String(v ?? '')
const textoOuNulo = (v: unknown) => (v == null || v === '' ? null : String(v))
const obj = (v: unknown): Linha | null => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Linha) : null)
const lista = (v: unknown): Linha[] => (Array.isArray(v) ? (v as Linha[]) : [])

export function mapearDetalheCasa(row: Linha): DetalheCasa {
  const o = obj(row.organizacao) ?? {}
  const mp = obj(o.mercado_pago)
  const d = obj(row.dono)
  const m = obj(row.metricas) ?? {}
  return {
    organizacao: {
      id: s(o.organizacao_id),
      nome: s(o.nome),
      slug: s(o.slug),
      ativo: o.ativo !== false,
      aprovada: o.aprovada === true,
      listaVip: o.lista_vip_ativa === true,
      taxaServico: n(o.taxa_servico),
      criadoEm: s(o.criado_em),
      mercadoPago: mp ? { conectadoEm: textoOuNulo(mp.conectado_em), producao: mp.producao === true } : null
    },
    dono: d
      ? {
          usuarioId: s(d.usuario_id),
          nome: s(d.nome),
          email: s(d.email),
          ativo: d.ativo !== false,
          cadastradoEm: textoOuNulo(d.cadastrado_em),
          ultimoAcessoEm: textoOuNulo(d.ultimo_acesso_em),
          emailConfirmado: d.email_confirmado === true,
          termosVersao: textoOuNulo(d.termos_versao),
          termosAceitosEm: textoOuNulo(d.termos_aceitos_em),
          outrasCasas: n(d.outras_casas)
        }
      : null,
    equipe: lista(row.equipe).map((u) => ({
      usuarioId: s(u.usuario_id),
      nome: s(u.nome),
      email: s(u.email),
      perfil: u.perfil === 'PORTARIA' ? 'PORTARIA' : 'ADMINISTRADOR',
      ativo: u.ativo !== false,
      dono: u.dono === true,
      ultimoAcessoEm: textoOuNulo(u.ultimo_acesso_em)
    })),
    metricas: {
      eventosTotal: n(m.eventos_total),
      eventosPublicados: n(m.eventos_publicados),
      eventosAtivos: n(m.eventos_ativos),
      eventosVendasAbertas: n(m.eventos_vendas_abertas),
      eventosRealizados: n(m.eventos_realizados),
      eventosCancelados: n(m.eventos_cancelados),
      eventosRascunho: n(m.eventos_rascunho),
      ingressosVendidos: n(m.ingressos_vendidos),
      ingressosUtilizados: n(m.ingressos_utilizados),
      pedidosPagos: n(m.pedidos_pagos),
      valorVendido: n(m.valor_vendido),
      valorOnline: n(m.valor_online),
      valorDinheiro: n(m.valor_dinheiro),
      taxaPlataforma: n(m.taxa_plataforma),
      valorReembolsado: n(m.valor_reembolsado),
      proximoEventoEm: textoOuNulo(m.proximo_evento_em)
    },
    eventos: lista(row.eventos).map((e) => ({
      id: s(e.evento_id),
      nome: s(e.nome),
      slug: s(e.slug),
      inicioEm: s(e.inicio_em),
      local: s(e.local),
      status: e.status as EventStatus,
      publicacaoStatus: e.publicacao_status as PublicationStatus,
      vendasStatus: e.vendas_status as SalesStatus,
      capacidadeTotal: n(e.capacidade_total),
      vendidos: n(e.vendidos),
      utilizados: n(e.utilizados),
      pedidosPagos: n(e.pedidos_pagos),
      valorVendido: n(e.valor_vendido),
      valorOnline: n(e.valor_online),
      valorDinheiro: n(e.valor_dinheiro),
      taxaPlataforma: n(e.taxa_plataforma)
    }))
  }
}

/** Percentual inteiro (0 a 100) ou null quando nao ha base. */
export function percentual(parte: number, total: number): number | null {
  if (!total || total <= 0) return null
  return Math.round((parte / total) * 100)
}

/** Ticket medio por ingresso vendido (valor pago / ingressos), em centavos arredondados. */
export function ticketMedio(valor: number, ingressos: number): number {
  if (!ingressos || ingressos <= 0) return 0
  return Math.round((valor / ingressos) * 100) / 100
}

/** Valor que fica com o produtor nas vendas online (antes da tarifa do Mercado Pago). */
export function repasseOnline(m: Pick<MetricasCasa, 'valorOnline' | 'taxaPlataforma'>): number {
  return Math.round((m.valorOnline - m.taxaPlataforma) * 100) / 100
}

export type FiltroEventosCasa = 'TODOS' | 'ATIVOS' | 'REALIZADOS' | 'RASCUNHOS'

export function eventoAtivo(e: Pick<EventoDaCasa, 'publicacaoStatus' | 'status'>): boolean {
  return e.publicacaoStatus === 'PUBLICADO' && (e.status === 'AGENDADO' || e.status === 'EM_ANDAMENTO')
}

export function filtrarEventosCasa(eventos: EventoDaCasa[], filtro: FiltroEventosCasa): EventoDaCasa[] {
  if (filtro === 'ATIVOS') return eventos.filter(eventoAtivo)
  if (filtro === 'REALIZADOS') return eventos.filter((e) => e.status === 'REALIZADO')
  if (filtro === 'RASCUNHOS') return eventos.filter((e) => e.publicacaoStatus === 'RASCUNHO')
  return eventos
}
