export type LotStatus = 'INATIVO' | 'ATIVO' | 'ENCERRADO'

export type LotActivationType = 'MANUAL' | 'ESGOTAMENTO' | 'DATA_HORA'

export interface LotListItem {
  id: string
  eventoId: string
  nome: string
  ordem: number
  quantidade: number
  preco: number
  tipoAtivacao: LotActivationType
  ativacaoEm: string | null
  ativadoEm: string | null
  encerradoEm: string | null
  status: LotStatus
  vendidos: number
  disponiveis: number
}

export interface LotFormValue {
  nome: string
  ordem: number | null
  quantidade: number | null
  preco: number | null
  tipoAtivacao: LotActivationType
  dataAtivacao: string
  horaAtivacao: string
  status: LotStatus
}

export type LotFormField = keyof LotFormValue

export type LotFormErrors = Partial<Record<LotFormField, string>>

export type LotFormMode = 'create' | 'edit'

export interface LotPayload {
  nome: string
  ordem: number
  quantidade: number
  preco: number
  tipoAtivacao: LotActivationType
  ativacaoEm: string | null
}

export interface LotOrdemRef {
  id: string
  ordem: number
}
