import { mapearErroPagamento, type ErroPagamento } from '~/utils/errosPagamento'

/** Ultimos erros de pagamento de todas as casas (somente super admin). */
export async function listarErrosPagamento(limite = 200): Promise<ErroPagamento[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_erros_pagamento_plataforma', { p_limite: limite })
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê os erros de pagamento.')
    throw new Error('Não foi possível carregar os erros de pagamento.')
  }
  return ((data ?? []) as Array<Record<string, unknown>>).map(mapearErroPagamento)
}
