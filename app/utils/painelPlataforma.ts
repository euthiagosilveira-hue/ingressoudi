import type { EventStatus, SalesStatus } from '../types/evento.ts'
import { imagemValida } from './imagem.ts'

/** Painel da plataforma (RPC obter_painel_plataforma, somente super admin). */

export type PeriodoPainel = 'HOJE' | '7_DIAS' | 'MES' | 'TUDO'

export const OPCOES_PERIODO: { value: PeriodoPainel; label: string }[] = [
  { value: 'HOJE', label: 'Hoje' },
  { value: '7_DIAS', label: '7 dias' },
  { value: 'MES', label: '30 dias' },
  { value: 'TUDO', label: 'Tudo' }
]

export interface NumerosPeriodo {
  ingressos: number
  valor: number
  taxa: number
  pedidos: number
}

export interface MetricasPainel extends NumerosPeriodo {
  casasAtivas: number
  casasEmAnalise: number
  casasNovas: number
  eventosVendasAbertas: number
  casasVendasAbertas: number
}

export interface EventoPainel {
  id: string
  nome: string
  imagemUrl: string | null
  inicioEm: string
  local: string
  status: EventStatus
  vendasStatus: SalesStatus
  capacidade: number
  vendidos: number
  utilizados: number
  organizacaoId: string
  organizacaoNome: string
}

export interface CasaRanking {
  organizacaoId: string
  nome: string
  ingressos: number
  pedidos: number
  valor: number
  taxa: number
}

export interface CasaResumo {
  organizacaoId: string
  nome: string
}

export interface EventoSemVendas {
  id: string
  nome: string
  inicioEm: string
  organizacaoId: string
  organizacaoNome: string
}

export interface PixRecusados extends CasaResumo {
  quantidade: number
}

export type TipoAtividade = 'CASA_NOVA' | 'EVENTO_PUBLICADO' | 'MERCADO_PAGO_CONECTADO' | 'VENDA'

export interface AtividadePainel {
  tipo: TipoAtividade
  em: string
  organizacaoId: string
  organizacaoNome: string
  eventoNome: string
  quantidade: number
  valor: number
}

export interface PainelPlataforma {
  metricas: MetricasPainel
  anterior: NumerosPeriodo | null
  eventos: EventoPainel[]
  ranking: CasaRanking[]
  alertas: {
    casasSemMercadoPago: CasaResumo[]
    casasSemEvento: CasaResumo[]
    eventosSemVendas: EventoSemVendas[]
    pixRecusados: PixRecusados[]
  }
  atividade: AtividadePainel[]
}

type Row = Record<string, unknown>
const n = (v: unknown) => Number(v ?? 0) || 0
const s = (v: unknown) => String(v ?? '')
const lista = (v: unknown): Row[] => (Array.isArray(v) ? (v as Row[]) : [])

function numeros(row: Row): NumerosPeriodo {
  return { ingressos: n(row.ingressos), valor: n(row.valor), taxa: n(row.taxa), pedidos: n(row.pedidos) }
}

function casa(row: Row): CasaResumo {
  return { organizacaoId: s(row.organizacao_id), nome: s(row.nome) }
}

export function mapearPainelPlataforma(data: unknown): PainelPlataforma {
  const d = (data ?? {}) as Row
  const m = (d.metricas ?? {}) as Row
  const a = (d.alertas ?? {}) as Row
  return {
    metricas: {
      ...numeros(m),
      casasAtivas: n(m.casas_ativas),
      casasEmAnalise: n(m.casas_em_analise),
      casasNovas: n(m.casas_novas),
      eventosVendasAbertas: n(m.eventos_vendas_abertas),
      casasVendasAbertas: n(m.casas_vendas_abertas)
    },
    anterior: d.anterior && typeof d.anterior === 'object' ? numeros(d.anterior as Row) : null,
    eventos: lista(d.eventos).map((e) => ({
      id: s(e.evento_id),
      nome: s(e.nome),
      imagemUrl: imagemValida(e.imagem_url as string | null),
      inicioEm: s(e.inicio_em),
      local: s(e.local),
      status: e.status as EventStatus,
      vendasStatus: e.vendas_status as SalesStatus,
      capacidade: n(e.capacidade_total),
      vendidos: n(e.vendidos),
      utilizados: n(e.utilizados),
      organizacaoId: s(e.organizacao_id),
      organizacaoNome: s(e.organizacao_nome)
    })),
    ranking: lista(d.ranking).map((r) => ({ ...casa(r), ...numeros(r) })),
    alertas: {
      casasSemMercadoPago: lista(a.casas_sem_mercado_pago).map(casa),
      casasSemEvento: lista(a.casas_sem_evento).map(casa),
      eventosSemVendas: lista(a.eventos_sem_vendas).map((e) => ({
        id: s(e.evento_id),
        nome: s(e.nome),
        inicioEm: s(e.inicio_em),
        organizacaoId: s(e.organizacao_id),
        organizacaoNome: s(e.organizacao_nome)
      })),
      pixRecusados: lista(a.pix_recusados_24h).map((p) => ({ ...casa(p), quantidade: n(p.quantidade) }))
    },
    atividade: lista(d.atividade).map((x) => ({
      tipo: x.tipo as TipoAtividade,
      em: s(x.em),
      organizacaoId: s(x.organizacao_id),
      organizacaoNome: s(x.organizacao_nome),
      eventoNome: s(x.evento_nome),
      quantidade: n(x.quantidade),
      valor: n(x.valor)
    }))
  }
}

/** Inicio do periodo escolhido (null = desde sempre). "Hoje" comeca a meia-noite de Sao Paulo. */
export function inicioDoPeriodo(periodo: PeriodoPainel, agora: Date = new Date()): string | null {
  if (periodo === 'TUDO') return null
  if (periodo === 'HOJE') {
    const dia = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(agora)
    return new Date(`${dia}T00:00:00-03:00`).toISOString()
  }
  const dias = periodo === '7_DIAS' ? 7 : 30
  return new Date(agora.getTime() - dias * 24 * 60 * 60 * 1000).toISOString()
}

/** Variacao em relacao ao periodo anterior, ex.: "+18% vs. anterior". */
export function variacao(atual: number, anterior: number | null | undefined): string {
  if (anterior === null || anterior === undefined) return ''
  if (anterior <= 0) return atual > 0 ? 'Novo no período' : 'Sem vendas no período anterior'
  const pct = Math.round(((atual - anterior) / anterior) * 100)
  return `${pct > 0 ? '+' : ''}${pct}% vs. período anterior`
}

/** Percentual vendido da capacidade, de 0 a 100. */
export function ocupacao(vendidos: number, capacidade: number): number {
  if (capacidade <= 0) return 0
  return Math.min(100, Math.round((vendidos / capacidade) * 100))
}

/** Rotulo do cartao do evento. Vendendo pouco = menos de 20% com o evento a 3 dias ou menos. */
export function situacaoEvento(
  e: Pick<EventoPainel, 'status' | 'vendasStatus' | 'vendidos' | 'capacidade' | 'inicioEm'>,
  agora: Date = new Date()
): { rotulo: string; tom: 'success' | 'warning' | 'danger' | 'neutral' } {
  if (e.status === 'EM_ANDAMENTO') return { rotulo: 'Em andamento', tom: 'success' }
  if (e.vendasStatus !== 'ABERTAS') return { rotulo: 'Vendas encerradas', tom: 'neutral' }
  const faltamMs = new Date(e.inicioEm).getTime() - agora.getTime()
  if (faltamMs <= 3 * 24 * 60 * 60 * 1000 && ocupacao(e.vendidos, e.capacidade) < 20) {
    return { rotulo: 'Vendendo pouco', tom: 'danger' }
  }
  return { rotulo: 'Vendas abertas', tom: 'warning' }
}

/** Nomes de ate 3 casas, ex.: "Galpao 7, Espaco Luz e mais 2". */
export function resumirNomes(nomes: string[], limite = 3): string {
  if (nomes.length <= limite) return nomes.join(', ')
  return `${nomes.slice(0, limite).join(', ')} e mais ${nomes.length - limite}`
}
