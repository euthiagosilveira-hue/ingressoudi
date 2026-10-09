import type { RegistrarEntradaQrResult, TipoErroGate } from '~/types/gate'
import { mapearResultadoEntradaRpc } from '~/utils/gate'
import { classificarErroGate, comTimeout } from '~/utils/portariaErro'

export class GateError extends Error {
  code: TipoErroGate

  constructor(code: TipoErroGate, message: string) {
    super(message)
    this.name = 'GateError'
    this.code = code
  }
}

function mapearErro(error: unknown): GateError {
  return new GateError(classificarErroGate(error), 'Falha na comunicação com o sistema.')
}

/**
 * Registra a entrada pelo QR (unica via de mutacao de portaria).
 * Nenhuma regra de negocio e decidida no frontend: o resultado vem da RPC.
 */
export async function registrarEntradaQr(input: {
  eventoId: string
  qrToken: string
}): Promise<RegistrarEntradaQrResult> {
  const client = useSupabaseClient()
  const { data, error } = await comTimeout(
    client.rpc('registrar_entrada_qr', {
      p_evento_id: input.eventoId,
      p_qr_token: input.qrToken
    })
  )

  if (error) throw mapearErro(error)

  return mapearResultadoEntradaRpc(data as Record<string, unknown>)
}
