import type { RegistrarEntradaQrResult, TipoErroGate } from '~/types/gate'
import { mapearResultadoEntradaRpc, resultadoPedeConferenciaPix } from '~/utils/gate'
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

const TIMEOUT_CONFERENCIA_PIX_MS = 8000

/**
 * Ingresso barrado como expirado ou nao pago: pede ao servidor para conferir o
 * Pix no Mercado Pago. Se estava pago, o pedido e confirmado e a entrada e
 * registrada de novo. Qualquer falha devolve o resultado original.
 */
export async function conferirPixSeNecessario(
  eventoId: string,
  resultado: RegistrarEntradaQrResult,
  repetir: () => Promise<RegistrarEntradaQrResult>
): Promise<RegistrarEntradaQrResult> {
  if (!resultadoPedeConferenciaPix(resultado)) return resultado
  try {
    const r = await $fetch<{ confirmado?: boolean }>('/api/portaria/conferir-pix', {
      method: 'POST',
      body: { eventoId, ingressoId: resultado.ingressoId },
      timeout: TIMEOUT_CONFERENCIA_PIX_MS
    })
    if (!r?.confirmado) return resultado
    return await repetir()
  } catch {
    return resultado
  }
}

/**
 * Ao abrir o evento na portaria: pede ao servidor a conferencia unica dos Pix
 * do evento ainda nao aprovados (o banco limita a uma a cada 30 minutos).
 * Roda em segundo plano; falha aqui nao atrapalha a portaria.
 */
export function conferirPixDoEvento(eventoId: string): void {
  $fetch('/api/portaria/conferir-pix-evento', { method: 'POST', body: { eventoId } }).catch(() => null)
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

  return conferirPixSeNecessario(
    input.eventoId,
    mapearResultadoEntradaRpc(data as Record<string, unknown>),
    async () => {
      const novo = await comTimeout(
        client.rpc('registrar_entrada_qr', { p_evento_id: input.eventoId, p_qr_token: input.qrToken })
      )
      if (novo.error) throw mapearErro(novo.error)
      return mapearResultadoEntradaRpc(novo.data as Record<string, unknown>)
    }
  )
}
