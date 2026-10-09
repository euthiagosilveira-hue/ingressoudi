export type VipStatus = 'AGUARDANDO' | 'ENTROU'

export interface VipConvidado {
  vipId: string
  nome: string
  telefone: string | null
  observacao: string | null
  entrou: boolean
  entradaEm: string | null
  criadoEm: string
  criadoPor: string | null
}

/** Linha bruta de public.listar_lista_vip_admin. */
export interface AdminVipRow {
  vip_id: string
  nome: string
  telefone: string | null
  observacao: string | null
  entrou: boolean
  entrada_em: string | null
  criado_em: string
  criado_por: string | null
}

export interface VipFormValue {
  nome: string
  telefone: string
  observacao: string
}

export interface VipPayload {
  nome: string
  telefone: string | null
  observacao: string | null
}

export interface VipResumo {
  total: number
  aguardando: number
  entraram: number
}
