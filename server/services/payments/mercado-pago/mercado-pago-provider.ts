import type { CreatePixChargeInput, PaymentProvider, PixCharge } from '../payment-provider'
import { MercadoPagoClient } from './mercado-pago-client'
import { mapMpOrderToCharge, montarPayloadOrderPix } from './mercado-pago-mapper'

export class MercadoPagoProvider implements PaymentProvider {
  readonly name = 'MERCADO_PAGO' as const
  private readonly client: MercadoPagoClient

  constructor(accessToken: string) {
    this.client = new MercadoPagoClient(accessToken)
  }

  async createPixCharge(input: CreatePixChargeInput): Promise<PixCharge> {
    const payload = montarPayloadOrderPix(input)
    const order = await this.client.createOrder(payload, input.idempotencyKey)
    return mapMpOrderToCharge(order)
  }

  async getCharge(chargeId: string): Promise<PixCharge> {
    const order = await this.client.getOrder(chargeId)
    return mapMpOrderToCharge(order)
  }
}
