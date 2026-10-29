import { normalizarCodigoPedido, normalizarEmail, normalizarTelefone } from '~/utils/publicIngressos'

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

export interface PedidoEncontrado {
  pedidoId: string
  codigoPedido: string
  checkoutToken: string
  organizacaoSlug: string | null
  eventoSlug: string
  eventoNome: string
  eventoInicioEm: string | null
  eventoLocal: string | null
  quantidade: number | null
}

interface PedidoContatoRpc {
  pedido_id?: string
  codigo_pedido?: string
  checkout_token?: string
  organizacao_slug?: string | null
  evento_slug?: string
  evento_nome?: string
  evento_inicio_em?: string | null
  evento_local?: string | null
  quantidade?: number | null
}

/**
 * Busca os pedidos pagos do comprador por telefone + e-mail (os dois precisam
 * casar no servidor). A resposta e generica quando nada e encontrado.
 */
export async function buscarIngressosPorContato(input: {
  telefone: string
  email: string
}): Promise<PedidoEncontrado[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('buscar_ingressos_contato', {
    p_telefone: normalizarTelefone(input.telefone),
    p_email: normalizarEmail(input.email)
  })
  if (error) {
    throw new Error('Não foi possível buscar agora. Tente novamente.')
  }
  const r = (data ?? {}) as { ok?: boolean; pedidos?: PedidoContatoRpc[] }
  if (r.ok !== true || !Array.isArray(r.pedidos)) return []
  return r.pedidos
    .filter((p) => p.pedido_id && p.checkout_token && p.evento_slug)
    .map((p) => ({
      pedidoId: p.pedido_id as string,
      codigoPedido: p.codigo_pedido ?? '',
      checkoutToken: p.checkout_token as string,
      organizacaoSlug: p.organizacao_slug ?? null,
      eventoSlug: p.evento_slug as string,
      eventoNome: p.evento_nome ?? '',
      eventoInicioEm: p.evento_inicio_em ?? null,
      eventoLocal: p.evento_local ?? null,
      quantidade: p.quantidade ?? null
    }))
}
