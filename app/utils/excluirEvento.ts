/** Resumo do que some ao excluir um evento (RPC resumo_exclusao_evento). */
export type ResumoExclusaoEvento = {
  eventoId: string
  nome: string
  organizacaoNome: string
  pedidos: number
  pedidosPagos: number
  pedidosPagosOnline: number
  valorPago: number
  pixPendentes: number
  ingressos: number
  entradas: number
  listaVip: number
  lotes: number
  setores: number
}

function num(v: unknown): number {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

export function mapearResumoExclusao(r: Record<string, unknown>): ResumoExclusaoEvento {
  return {
    eventoId: String(r.evento_id ?? ''),
    nome: String(r.nome ?? ''),
    organizacaoNome: String(r.organizacao_nome ?? ''),
    pedidos: num(r.pedidos),
    pedidosPagos: num(r.pedidos_pagos),
    pedidosPagosOnline: num(r.pedidos_pagos_online),
    valorPago: num(r.valor_pago),
    pixPendentes: num(r.pix_pendentes),
    ingressos: num(r.ingressos),
    entradas: num(r.entradas),
    listaVip: num(r.lista_vip),
    lotes: num(r.lotes),
    setores: num(r.setores)
  }
}

export function temVendasPagas(r: ResumoExclusaoEvento): boolean {
  return r.pedidosPagos > 0
}

function normalizar(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toLowerCase()
}

/** O super admin digita o nome do evento para confirmar (sem diferenciar acento/maiúscula). */
export function nomeConfere(digitado: string, nomeEvento: string): boolean {
  const alvo = normalizar(nomeEvento)
  return alvo.length > 0 && normalizar(digitado) === alvo
}

/** Linhas "o que será apagado", só com o que existe. */
export function itensExclusao(r: ResumoExclusaoEvento): string[] {
  const itens: Array<[number, string, string]> = [
    [r.pedidos, 'pedido', 'pedidos'],
    [r.ingressos, 'ingresso', 'ingressos'],
    [r.entradas, 'entrada registrada na portaria', 'entradas registradas na portaria'],
    [r.listaVip, 'nome na lista VIP', 'nomes na lista VIP'],
    [r.lotes, 'lote', 'lotes'],
    [r.setores, 'setor', 'setores']
  ]
  return itens.filter(([n]) => n > 0).map(([n, um, varios]) => `${n} ${n === 1 ? um : varios}`)
}

/** Converte o erro do banco numa frase para a tela. */
export function mensagemErroExclusao(mensagem: string | undefined | null): string {
  const m = (mensagem ?? '').toLowerCase()
  if (m.includes('permiss') || m.includes('super administrador')) return 'Apenas o super administrador pode excluir eventos.'
  if (m.includes('evento_com_vendas_pagas')) return 'Este evento tem vendas pagas. Marque a confirmação para apagar mesmo assim.'
  if (m.includes('nao encontrado') || m.includes('não encontrado')) return 'Este evento já foi excluído.'
  return 'Não foi possível excluir o evento.'
}
