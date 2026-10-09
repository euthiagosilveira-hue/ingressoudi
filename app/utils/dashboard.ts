import type {
  AdminDashboardData,
  AdminDashboardEvento,
  AdminDashboardOrder,
  EntryByHour,
  PaymentSlice,
  RecentEntry,
  RecentOrder,
  TodayEvent
} from '~/types/dashboard'
import { imagemValida } from './imagem.ts'

const moedaBRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })

function formatMoeda(valor: number): string {
  return moedaBRL.format(valor)
}

function formatHora(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

function formatData(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

const CORES: Record<string, string> = {
  paid: '#22c55e',
  pending: '#fbbf24',
  canceled: '#ef4444'
}

function nomeDiaSemana(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

function diaMes(iso: string): { dia: string; mes: string } {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return { dia: '', mes: '' }
  const dia = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
  const mes = new Intl.DateTimeFormat('pt-BR', {
    month: 'short',
    timeZone: 'America/Sao_Paulo'
  })
    .format(data)
    .replace('.', '')
    .toUpperCase()
  return { dia, mes }
}

/**
 * Converte o evento real (EM_ANDAMENTO ou proximo AGENDADO) no view-model do
 * card. A capa usa imagem_url real validada; sem imagem, usa o fallback atual.
 */
export function mapearDashboardEvento(evento: AdminDashboardEvento | null): TodayEvent {
  if (!evento) {
    return {
      hasEvent: false,
      badge: '',
      title: 'Nenhum próximo evento agendado.',
      date: '—',
      time: '—',
      venue: '—',
      imageUrl: null,
      href: '',
      poster: { weekday: '', day: '--', month: '', label: 'EVENTO', name: '—' }
    }
  }

  const { dia, mes } = diaMes(evento.inicio_em)
  const semana = nomeDiaSemana(evento.inicio_em)
  return {
    hasEvent: true,
    badge: evento.status === 'EM_ANDAMENTO' ? 'AO VIVO' : 'PRÓXIMO',
    title: evento.nome,
    date: formatData(evento.inicio_em),
    time: formatHora(evento.inicio_em),
    venue: evento.local ?? '—',
    imageUrl: imagemValida(evento.imagem_url),
    href: `/eventos/${evento.slug}`,
    poster: {
      weekday: semana ? semana.slice(0, 3).toUpperCase() : '',
      day: dia,
      month: mes,
      label: 'EVENTO',
      name: evento.nome
    }
  }
}

export function mapearEntradasPorHora(
  dados: { hora: string; entradas: number }[]
): EntryByHour[] {
  return dados.map((item) => ({ hora: item.hora, entradas: Number(item.entradas) }))
}

export function mapearPagamentosPorStatus(
  dados: { key: string; label: string; value: number }[]
): PaymentSlice[] {
  return dados.map((item) => ({
    key: item.key as PaymentSlice['key'],
    label: item.label,
    value: Number(item.value),
    color: CORES[item.key] ?? '#71717a'
  }))
}

export function mapearPedidosRecentes(orders: AdminDashboardOrder[]): RecentOrder[] {
  return orders.map((order) => ({
    id: `#${order.codigo}`,
    buyer: order.buyer,
    tickets: Number(order.tickets),
    total: formatMoeda(Number(order.total)),
    payment: order.status === 'PAGO' ? 'Pago' : 'Pendente',
    entranceUsed: Number(order.entrance_used),
    entranceTotal: Number(order.tickets)
  }))
}

export function mapearEntradasRecentes(
  entries: { id: string; name: string; codigo: string; entrada_em: string; metodo_validacao: string | null }[]
): RecentEntry[] {
  return entries.map((entry) => ({
    id: entry.id,
    name: entry.name,
    ticket: `Ingresso ${entry.codigo}`,
    time: formatHora(entry.entrada_em),
    dateLabel: 'Hoje',
    ok: true,
    statusLabel: 'Hoje'
  }))
}

export interface AdminDashboardViewModel {
  metrics: AdminDashboardData['metricas']
  evento: TodayEvent
  entriesByHour: EntryByHour[]
  paymentStatus: PaymentSlice[]
  recentOrders: RecentOrder[]
  recentEntries: RecentEntry[]
}

/** Mapeia o retorno da RPC para as props exatas dos componentes atuais. */
export function mapearDashboard(data: AdminDashboardData): AdminDashboardViewModel {
  return {
    metrics: data.metricas,
    evento: mapearDashboardEvento(data.evento),
    entriesByHour: mapearEntradasPorHora(data.entradasPorHora),
    paymentStatus: mapearPagamentosPorStatus(data.pagamentosPorStatus),
    recentOrders: mapearPedidosRecentes(data.pedidosRecentes),
    recentEntries: mapearEntradasRecentes(data.entradasRecentes)
  }
}
