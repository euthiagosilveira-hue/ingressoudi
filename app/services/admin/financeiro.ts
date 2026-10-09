import type {
  AdminFinanceResponse,
  FinancialSummaryData,
  PaymentListItem,
  PaymentProvider,
  PaymentStatus
} from '~/types/pagamento'
import { mapearFinanceiroResumo, mapearMovimentacaoParaListItem } from '~/utils/financeiro'

export interface AdminFinanceFiltros {
  eventoId?: string | null
  busca?: string | null
  de?: string | null
  ate?: string | null
  status?: PaymentStatus | null
  provedor?: PaymentProvider | null
}

export interface AdminFinanceResultado {
  resumo: FinancialSummaryData
  movimentacoes: PaymentListItem[]
}

/** Resumo + movimentacoes financeiras reais (RPC segura, ADMINISTRADOR). */
export async function obterFinanceiroAdmin(
  filtros: AdminFinanceFiltros = {}
): Promise<AdminFinanceResultado> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_financeiro_admin', {
    p_evento_id: filtros.eventoId ?? null,
    p_busca: filtros.busca?.trim() ? filtros.busca.trim() : null,
    p_de: filtros.de ?? null,
    p_ate: filtros.ate ?? null,
    p_status_pagamento: filtros.status ?? null,
    p_provedor: filtros.provedor ?? null
  })
  if (error) {
    throw new Error('Não foi possível carregar o financeiro.')
  }

  const resposta = (data ?? {}) as AdminFinanceResponse
  return {
    resumo: mapearFinanceiroResumo(resposta.resumo),
    movimentacoes: (resposta.movimentacoes ?? []).map(mapearMovimentacaoParaListItem)
  }
}
