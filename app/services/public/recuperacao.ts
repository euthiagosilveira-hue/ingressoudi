import { normalizarCodigoPedido, normalizarTelefone } from '~/utils/publicIngressos'

export interface RecuperacaoResultado {
  ok: boolean
  token: string | null
  expiraEm: string | null
}

interface RecuperacaoRpc {
  ok?: boolean
  token?: string | null
  expira_em?: string | null
}

/**
 * Gera um token temporario de recuperacao a partir de codigo do pedido +
 * telefone. A validacao e 100% server-side; a resposta e sempre generica.
 */
export async function recuperarIngressos(input: {
  codigo: string
  telefone: string
}): Promise<RecuperacaoResultado> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('recuperar_ingressos', {
    p_codigo: normalizarCodigoPedido(input.codigo),
    p_telefone: normalizarTelefone(input.telefone)
  })
  if (error) {
    throw new Error('Não foi possível recuperar agora. Tente novamente.')
  }
  const r = (data ?? {}) as RecuperacaoRpc
  return {
    ok: r.ok === true,
    token: r.token ?? null,
    expiraEm: r.expira_em ?? null
  }
}
