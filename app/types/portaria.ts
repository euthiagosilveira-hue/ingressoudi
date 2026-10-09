import type { TicketListItem } from '~/types/ingresso'

/**
 * Tipos de UI da Portaria (estado de tela / mock).
 *
 * IMPORTANTE: estes enums são apenas estados visuais desta tela e NÃO
 * representam nem alteram enums reais de banco (ingresso.status,
 * entradas ou tentativas_entrada).
 */

export type GateMode = 'QR' | 'NOME'

export type GateCheckinMethod = 'QR_CODE' | 'NOME'

export type GateValidationStatus =
  | 'PRONTO'
  | 'VALIDO'
  | 'LIBERADO'
  | 'JA_UTILIZADO'
  | 'INVALIDO'
  | 'CANCELADO'
  | 'EXPIRADO'
  | 'EVENTO_INCORRETO'
  | 'RESERVADO'

export interface GateValidationResultData {
  status: GateValidationStatus
  ingresso: TicketListItem | null
  eventoCorretoNome: string | null
  utilizadoEm: string | null
}

export interface GateRecentEntry {
  id: string
  ingressoId: string
  codigo: string
  participanteNome: string
  metodo: GateCheckinMethod
  registradoEm: string
}

export interface GateSimulationOption {
  id: string
  rotulo: string
  codigo: string
  valida: boolean
}
