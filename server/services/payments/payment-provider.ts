export type ProviderName = 'MERCADO_PAGO' | 'STONE'

export type Gz1PaymentStatus =
  | 'PENDENTE'
  | 'APROVADO'
  | 'REJEITADO'
  | 'CANCELADO'
  | 'EXPIRADO'
  | 'REEMBOLSADO'

/** Cobranca Pix normalizada (independente do provider). */
export interface PixCharge {
  provider: ProviderName
  transactionId: string | null
  chargeId: string | null
  externalReference: string
  status: Gz1PaymentStatus
  pixCopyPaste: string | null
  pixQrCode: string | null
  expiresAt: string | null
}

export interface CreatePixChargeInput {
  /** Valor em reais (derivado do banco). */
  amount: number
  externalReference: string
  payerEmail: string
  /** Duracao minima respeitando o minimo do provider (30 min). */
  expirationMinutes: number
  /** Chave estavel por pagamento logico. */
  idempotencyKey: string
  /**
   * Somente em ambiente de teste e com credencial de teste confirmada.
   * Quando true, aplica o mecanismo oficial de auto-aprovacao (first_name=APRO).
   * Nunca deve ser true em producao.
   */
  autoApproveTestPix?: boolean
}

export interface PaymentProvider {
  readonly name: ProviderName
  createPixCharge(input: CreatePixChargeInput): Promise<PixCharge>
  getCharge(chargeId: string): Promise<PixCharge>
}
