export interface AdminDashboardMetrics {
  vendidos: number
  utilizados: number
  naoEntraram: number
  faturamento: number
  ticketMedio: number
}

export interface AdminDashboardEvento {
  evento_id: string
  nome: string
  slug: string
  imagem_url: string | null
  inicio_em: string
  local: string | null
  status: string
}

export interface AdminDashboardEntryByHour {
  hora: string
  entradas: number
}

export interface AdminDashboardPaymentSlice {
  key: string
  label: string
  value: number
}

export interface AdminDashboardOrder {
  pedido_id: string
  codigo: string
  buyer: string
  tickets: number
  total: number | string
  status: string
  criado_em: string
  entrance_used: number
}

export interface AdminDashboardEntry {
  id: string
  name: string
  codigo: string
  entrada_em: string
  metodo_validacao: string | null
}

export interface AdminDashboardData {
  metricas: AdminDashboardMetrics
  evento: AdminDashboardEvento | null
  entradasPorHora: AdminDashboardEntryByHour[]
  pagamentosPorStatus: AdminDashboardPaymentSlice[]
  pedidosRecentes: AdminDashboardOrder[]
  entradasRecentes: AdminDashboardEntry[]
}

/** View-models usados pelos componentes visuais do dashboard. */
export interface EntryByHour {
  hora: string
  entradas: number
}

export interface PaymentSlice {
  key: 'paid' | 'pending' | 'canceled'
  label: string
  value: number
  color: string
}

export interface RecentOrder {
  id: string
  buyer: string
  tickets: number
  total: string
  payment: 'Pago' | 'Pendente'
  entranceUsed: number
  entranceTotal: number
}

export interface RecentEntry {
  id: string
  name: string
  ticket: string
  time: string
  dateLabel: string
  ok: boolean
  statusLabel: string
}

export interface TodayEvent {
  hasEvent: boolean
  badge: string
  title: string
  date: string
  time: string
  venue: string
  imageUrl: string | null
  href: string
  poster: {
    weekday: string
    day: string
    month: string
    label: string
    name: string
  }
}
