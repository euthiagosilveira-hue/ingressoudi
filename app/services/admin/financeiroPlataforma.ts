export interface FinanceiroTotais {
  pedidosOnline: number
  ingressosOnline: number
  brutoOnline: number
  taxaPlataforma: number
  repasseProdutores: number
  pedidosDinheiro: number
  ingressosDinheiro: number
  brutoDinheiro: number
  casasComVendas: number
}

export interface FinanceiroCasa {
  organizacaoId: string
  nome: string
  slug: string
  pedidosOnline: number
  ingressosOnline: number
  brutoOnline: number
  taxaPlataforma: number
  repasseProdutor: number
  pedidosDinheiro: number
  ingressosDinheiro: number
  brutoDinheiro: number
}

export interface FinanceiroDia {
  dia: string
  taxaPlataforma: number
  brutoOnline: number
}

export interface FinanceiroPlataforma {
  totais: FinanceiroTotais
  casas: FinanceiroCasa[]
  porDia: FinanceiroDia[]
}

const n = (v: unknown) => Number(v ?? 0) || 0

/** Resumo financeiro da plataforma no periodo (somente super admin). */
export async function obterFinanceiroPlataforma(inicio: string, fim: string): Promise<FinanceiroPlataforma> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('financeiro_plataforma', { p_inicio: inicio, p_fim: fim })
  if (error) {
    const m = (error.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador acessa o financeiro da plataforma.')
    if (m.includes('periodo invalido')) throw new Error('Período inválido: escolha até 1 ano.')
    throw new Error('Não foi possível carregar o financeiro.')
  }
  const r = (data ?? {}) as Record<string, any>
  const t = (r.totais ?? {}) as Record<string, unknown>
  return {
    totais: {
      pedidosOnline: n(t.pedidos_online),
      ingressosOnline: n(t.ingressos_online),
      brutoOnline: n(t.bruto_online),
      taxaPlataforma: n(t.taxa_plataforma),
      repasseProdutores: n(t.repasse_produtores),
      pedidosDinheiro: n(t.pedidos_dinheiro),
      ingressosDinheiro: n(t.ingressos_dinheiro),
      brutoDinheiro: n(t.bruto_dinheiro),
      casasComVendas: n(t.casas_com_vendas)
    },
    casas: ((r.organizacoes ?? []) as Array<Record<string, unknown>>).map((o) => ({
      organizacaoId: String(o.organizacao_id),
      nome: String(o.nome ?? ''),
      slug: String(o.slug ?? ''),
      pedidosOnline: n(o.pedidos_online),
      ingressosOnline: n(o.ingressos_online),
      brutoOnline: n(o.bruto_online),
      taxaPlataforma: n(o.taxa_plataforma),
      repasseProdutor: n(o.repasse_produtor),
      pedidosDinheiro: n(o.pedidos_dinheiro),
      ingressosDinheiro: n(o.ingressos_dinheiro),
      brutoDinheiro: n(o.bruto_dinheiro)
    })),
    porDia: ((r.por_dia ?? []) as Array<Record<string, unknown>>).map((d) => ({
      dia: String(d.dia),
      taxaPlataforma: n(d.taxa_plataforma),
      brutoOnline: n(d.bruto_online)
    }))
  }
}
