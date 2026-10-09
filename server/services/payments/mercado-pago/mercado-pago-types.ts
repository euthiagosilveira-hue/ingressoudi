/** Tipos minimos da Orders API do Mercado Pago (somente o que consumimos). */

export interface MpPaymentMethod {
  id: string
  type: string
  ticket_url?: string | null
  qr_code?: string | null
  qr_code_base64?: string | null
}

export interface MpTransactionPayment {
  id: string
  reference_id?: string | null
  status: string
  status_detail?: string | null
  amount?: string | null
  payment_method?: MpPaymentMethod | null
}

export interface MpOrder {
  id: string
  type?: string
  status: string
  status_detail?: string | null
  external_reference?: string | null
  total_amount?: string | null
  transactions?: {
    payments?: MpTransactionPayment[] | null
  } | null
}

export interface MpCreateOrderRequest {
  type: 'online'
  total_amount: string
  external_reference: string
  processing_mode: 'automatic'
  transactions: {
    payments: Array<{
      amount: string
      payment_method: { id: 'pix'; type: 'bank_transfer' }
      expiration_time: string
    }>
  }
  payer: { email: string; first_name?: string }
}
