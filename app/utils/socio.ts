/**
 * Socio do Evento: mapeia o retorno das RPCs listar_eventos_socio e
 * obter_vendas_evento_socio. So numeros de venda; nenhum dado de comprador.
 */
import { imagemValida } from './imagem.ts'

export interface ResumoVendasSocio {
  vendidos: number
  utilizados: number
  naoEntraram: number
  meias: number
  capacidade: number
  pedidos: number
  bruto: number
  taxa: number
  reembolsado: number
  liquido: number
  ticketMedio: number
}

export interface EventoSocio {
  eventoId: string
  nome: string
  imagemUrl: string | null
  inicioEm: string
  local: string
  status: string
  vendasAbertas: boolean
  resumo: ResumoVendasSocio
}

export type FormaVenda = 'PIX' | 'CARTAO' | 'PORTA' | 'OUTRO'

export interface VendaPorForma {
  forma: FormaVenda
  rotulo: string
  pedidos: number
  ingressos: number
  valor: number
}

export interface VendaPorLote {
  lote: string
  setor: string | null
  status: string
  preco: number
  quantidade: number
  vendidos: number
  valor: number
}

export interface VendaPorDia {
  dia: string
  ingressos: number
  valor: number
}

export interface VendasEventoSocio {
  evento: EventoSocio
  porForma: VendaPorForma[]
  porLote: VendaPorLote[]
  porDia: VendaPorDia[]
  entradasPorHora: Array<{ hora: string; entradas: number }>
}

const ROTULO_FORMA: Record<FormaVenda, string> = {
  PIX: 'Pix',
  CARTAO: 'Cartão de crédito',
  PORTA: 'Na porta (dinheiro)',
  OUTRO: 'Outros'
}

type Obj = Record<string, unknown>

function num(v: unknown): number {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

function texto(v: unknown): string {
  return typeof v === 'string' ? v : ''
}

function obj(v: unknown): Obj {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Obj) : {}
}

function lista(v: unknown): Obj[] {
  return Array.isArray(v) ? v.map(obj) : []
}

export function mapearResumoSocio(raw: unknown): ResumoVendasSocio {
  const r = obj(raw)
  return {
    vendidos: num(r.vendidos),
    utilizados: num(r.utilizados),
    naoEntraram: num(r.naoEntraram),
    meias: num(r.meias),
    capacidade: num(r.capacidade),
    pedidos: num(r.pedidos),
    bruto: num(r.bruto),
    taxa: num(r.taxa),
    reembolsado: num(r.reembolsado),
    liquido: num(r.liquido),
    ticketMedio: num(r.ticketMedio)
  }
}

export function mapearEventoSocio(raw: unknown, resumoRaw?: unknown): EventoSocio {
  const e = obj(raw)
  return {
    eventoId: texto(e.evento_id),
    nome: texto(e.nome),
    imagemUrl: imagemValida(texto(e.imagem_url)),
    inicioEm: texto(e.inicio_em),
    local: texto(e.local),
    status: texto(e.status),
    vendasAbertas: e.vendas_status === 'ABERTAS',
    resumo: mapearResumoSocio(resumoRaw ?? e.resumo)
  }
}

export function mapearEventosSocio(raw: unknown): EventoSocio[] {
  return lista(raw).map((e) => mapearEventoSocio(e))
}

function formaValida(v: unknown): FormaVenda {
  return v === 'PIX' || v === 'CARTAO' || v === 'PORTA' ? v : 'OUTRO'
}

export function mapearVendasEventoSocio(raw: unknown): VendasEventoSocio {
  const r = obj(raw)
  return {
    evento: mapearEventoSocio(r.evento, r.resumo),
    porForma: lista(r.porForma).map((f) => {
      const forma = formaValida(f.forma)
      return {
        forma,
        rotulo: ROTULO_FORMA[forma],
        pedidos: num(f.pedidos),
        ingressos: num(f.ingressos),
        valor: num(f.valor)
      }
    }),
    porLote: lista(r.porLote).map((l) => ({
      lote: texto(l.lote),
      setor: texto(l.setor) || null,
      status: texto(l.status),
      preco: num(l.preco),
      quantidade: num(l.quantidade),
      vendidos: num(l.vendidos),
      valor: num(l.valor)
    })),
    porDia: lista(r.porDia).map((d) => ({
      dia: texto(d.dia),
      ingressos: num(d.ingressos),
      valor: num(d.valor)
    })),
    entradasPorHora: lista(r.entradasPorHora).map((h) => ({
      hora: texto(h.hora),
      entradas: num(h.entradas)
    }))
  }
}

/** Percentual da capacidade vendida (0 a 100, sem casas decimais). */
export function percentualVendido(resumo: Pick<ResumoVendasSocio, 'vendidos' | 'capacidade'>): number {
  if (resumo.capacidade <= 0) return 0
  return Math.min(100, Math.round((resumo.vendidos / resumo.capacidade) * 100))
}

/** "2026-11-01" -> "01/11" (dia do pagamento, ja no horario de Sao Paulo). */
export function rotuloDia(dia: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dia)
  return m ? `${m[3]}/${m[2]}` : dia
}

/** Mensagem amigavel para falhas das RPCs do socio. */
export function mensagemErroSocio(error: { code?: string | null; message?: string | null } | null): string {
  const mensagem = (error?.message ?? '').toLowerCase()
  if (error?.code === '42501' || mensagem.includes('permiss')) {
    return 'Seu acesso de sócio não está ativo nesta organização.'
  }
  if (error?.code === '23503' || mensagem.includes('nao encontrado')) {
    return 'Este evento não está liberado para você.'
  }
  return 'Não foi possível carregar as vendas agora. Tente novamente.'
}
