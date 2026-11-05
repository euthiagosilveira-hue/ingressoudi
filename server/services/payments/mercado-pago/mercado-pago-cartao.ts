/**
 * Cartao de credito via API de Payments (/v1/payments) com o token da conta
 * conectada da casa. O numero do cartao nunca passa pelo servidor: o navegador
 * (Card Payment Brick) gera um `token` de uso unico e manda so ele.
 * Modulo sem auto-imports do Nuxt (testavel com node --test).
 */

export const MAX_PARCELAS = 3
export const MAX_TENTATIVAS_CARTAO = 5

/** Dados que o navegador envia depois que o Brick tokeniza o cartao. */
export interface DadosCartaoBrick {
  token: string
  paymentMethodId: string
  issuerId?: string | number | null
  installments: number
  payerEmail?: string | null
  identificationType?: string | null
  identificationNumber?: string | null
  deviceId?: string | null
}

export interface PedidoCartao {
  pagamentoId: string
  codigoPedido: string
  valorTotal: number
  valorTaxa: number
  eventoNome: string
  quantidade: number
  compradorNome: string
  compradorTelefone: string | null
  compradorEmail: string | null
  notificationUrl?: string
}

export interface MpCardPaymentRequest {
  transaction_amount: number
  token: string
  description: string
  installments: number
  payment_method_id: string
  issuer_id?: number
  external_reference: string
  binary_mode: true
  statement_descriptor: string
  payer: {
    email: string
    first_name?: string
    last_name?: string
    identification?: { type: string; number: string }
  }
  additional_info: {
    items: Array<{ id: string; title: string; quantity: number; unit_price: number; category_id: string }>
    payer: { first_name?: string; last_name?: string; phone?: { area_code: string; number: string } }
  }
  application_fee?: number
  notification_url?: string
}

export interface MpCardPayment {
  id: number | string
  status: string
  status_detail?: string | null
  external_reference?: string | null
  transaction_amount?: number | null
  installments?: number | null
  payment_method_id?: string | null
  card?: { last_four_digits?: string | null } | null
}

function arredondar(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** Parcelas aceitas: inteiro de 1 ate MAX_PARCELAS. */
export function parcelasValidas(valor: unknown): number | null {
  const n = Number(valor)
  if (!Number.isInteger(n) || n < 1 || n > MAX_PARCELAS) return null
  return n
}

/** Separa nome e sobrenome (o antifraude do Mercado Pago usa os dois). */
export function dividirNome(nome: string | null | undefined): { first: string; last: string } {
  const partes = String(nome ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return { first: '', last: '' }
  return { first: partes[0] as string, last: partes.slice(1).join(' ') }
}

/** Telefone BR em DDD + numero (somente digitos). */
export function dividirTelefone(telefone: string | null | undefined): { area_code: string; number: string } | null {
  let digitos = String(telefone ?? '').replace(/\D/g, '')
  if (digitos.startsWith('55') && digitos.length >= 12) digitos = digitos.slice(2)
  if (digitos.length < 10) return null
  return { area_code: digitos.slice(0, 2), number: digitos.slice(2) }
}

function emailValido(email: string | null | undefined): string | null {
  const e = String(email ?? '').trim()
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e) ? e : null
}

/**
 * Monta o pagamento com cartao. O valor e a taxa vem SEMPRE do pedido no banco,
 * nunca do navegador. `binary_mode` faz o Mercado Pago responder na hora
 * (aprovado ou recusado), sem deixar a reserva presa em "em analise".
 */
export function montarPayloadCartao(pedido: PedidoCartao, dados: DadosCartaoBrick): MpCardPaymentRequest {
  const parcelas = parcelasValidas(dados.installments)
  if (!parcelas) throw new Error('Parcelas invalidas.')
  const token = String(dados.token ?? '').trim()
  const metodo = String(dados.paymentMethodId ?? '').trim()
  if (!token || !metodo) throw new Error('Dados do cartao incompletos.')

  const email = emailValido(dados.payerEmail) ?? emailValido(pedido.compradorEmail)
  if (!email) throw new Error('E-mail do comprador ausente.')

  const valor = arredondar(pedido.valorTotal)
  const nome = dividirNome(pedido.compradorNome)
  const telefone = dividirTelefone(pedido.compradorTelefone)
  const quantidade = Math.max(1, Math.floor(pedido.quantidade || 1))

  const payload: MpCardPaymentRequest = {
    transaction_amount: valor,
    token,
    description: `Pedido ${pedido.codigoPedido}`,
    installments: parcelas,
    payment_method_id: metodo,
    external_reference: pedido.pagamentoId,
    binary_mode: true,
    statement_descriptor: 'INGRESSOUDI',
    payer: { email },
    additional_info: {
      items: [
        {
          id: pedido.codigoPedido,
          title: `Ingresso - ${pedido.eventoNome}`.slice(0, 250),
          quantity: quantidade,
          unit_price: arredondar(valor / quantidade),
          category_id: 'tickets'
        }
      ],
      payer: {}
    }
  }

  if (nome.first) {
    payload.payer.first_name = nome.first
    payload.additional_info.payer.first_name = nome.first
  }
  if (nome.last) {
    payload.payer.last_name = nome.last
    payload.additional_info.payer.last_name = nome.last
  }
  if (telefone) payload.additional_info.payer.phone = telefone

  const docTipo = String(dados.identificationType ?? '').trim()
  const docNumero = String(dados.identificationNumber ?? '').replace(/\D/g, '')
  if (docTipo && docNumero) payload.payer.identification = { type: docTipo, number: docNumero }

  const emissor = Number(dados.issuerId)
  if (Number.isInteger(emissor) && emissor > 0) payload.issuer_id = emissor

  const taxa = arredondar(pedido.valorTaxa)
  if (taxa > 0) {
    if (taxa > valor) throw new Error('Comissao maior que o valor do pagamento.')
    payload.application_fee = taxa
  }
  if (pedido.notificationUrl) payload.notification_url = pedido.notificationUrl
  return payload
}

/** Status da tentativa gravado no banco. */
export function statusTentativa(status: string | null | undefined): 'APROVADA' | 'RECUSADA' | 'PENDENTE' {
  const s = String(status ?? '').toLowerCase()
  if (s === 'approved') return 'APROVADA'
  if (s === 'in_process' || s === 'pending' || s === 'authorized') return 'PENDENTE'
  return 'RECUSADA'
}

/** Mensagem em portugues para cada motivo de recusa do Mercado Pago. */
export function mensagemRecusaCartao(statusDetail: string | null | undefined): string {
  const mapa: Record<string, string> = {
    cc_rejected_insufficient_amount: 'O cartão não tem limite suficiente. Tente outro cartão ou pague com Pix.',
    cc_rejected_bad_filled_security_code: 'O código de segurança (CVV) está incorreto. Confira e tente de novo.',
    cc_rejected_bad_filled_date: 'A data de validade está incorreta. Confira e tente de novo.',
    cc_rejected_bad_filled_card_number: 'O número do cartão está incorreto. Confira e tente de novo.',
    cc_rejected_bad_filled_other: 'Algum dado do cartão está incorreto. Confira e tente de novo.',
    cc_rejected_call_for_authorize: 'O banco pediu autorização. Ligue para o banco do cartão ou pague com Pix.',
    cc_rejected_card_disabled: 'O cartão não está ativo. Ligue para o banco ou use outro cartão.',
    cc_rejected_duplicated_payment: 'Já existe um pagamento igual. Use outro cartão ou pague com Pix.',
    cc_rejected_high_risk: 'O pagamento foi recusado por segurança. Use outro cartão ou pague com Pix.',
    cc_rejected_max_attempts: 'Limite de tentativas no cartão. Use outro cartão ou pague com Pix.',
    cc_rejected_blacklist: 'O pagamento foi recusado. Use outro cartão ou pague com Pix.',
    cc_rejected_card_type_not_allowed: 'Este tipo de cartão não é aceito. Use um cartão de crédito.',
    cc_amount_rate_limit_exceeded: 'O cartão atingiu o limite permitido. Use outro cartão ou pague com Pix.',
    rejected_by_issuer: 'O banco do cartão recusou o pagamento. Use outro cartão ou pague com Pix.'
  }
  const chave = String(statusDetail ?? '').toLowerCase()
  return mapa[chave] ?? 'O pagamento não foi aprovado pelo banco do cartão. Tente outro cartão ou pague com Pix.'
}
