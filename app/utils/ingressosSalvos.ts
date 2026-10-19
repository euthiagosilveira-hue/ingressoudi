/**
 * Pedidos salvos no proprio aparelho do comprador (localStorage), para ele
 * voltar aos ingressos sem precisar do codigo do pedido.
 *
 * Guarda somente o checkout_token (o mesmo que ja fica no link da compra) e
 * dados de exibicao. Os ingressos e o QR continuam vindo sempre da RPC.
 */

export const CHAVE_INGRESSOS_SALVOS = 'ingressoudi:pedidos'
export const LIMITE_INGRESSOS_SALVOS = 20

export interface PedidoSalvo {
  pedidoId: string
  checkoutToken: string
  codigoPedido: string
  organizacaoSlug: string | null
  eventoSlug: string
  eventoNome: string
  eventoInicioEm: string | null
  eventoLocal: string | null
  quantidade: number | null
  salvoEm: string
}

export interface ArmazenamentoLike {
  getItem: (chave: string) => string | null
  setItem: (chave: string, valor: string) => void
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** localStorage quando disponivel (navegador, sem modo restrito). */
export function armazenamentoPadrao(): ArmazenamentoLike | null {
  try {
    return typeof window !== 'undefined' && window.localStorage ? window.localStorage : null
  } catch {
    return null
  }
}

function valido(item: unknown): item is PedidoSalvo {
  const p = item as PedidoSalvo
  return (
    !!p &&
    typeof p.pedidoId === 'string' &&
    typeof p.checkoutToken === 'string' &&
    UUID.test(p.checkoutToken) &&
    typeof p.eventoSlug === 'string' &&
    p.eventoSlug !== '' &&
    typeof p.eventoNome === 'string'
  )
}

export function lerPedidosSalvos(armazenamento: ArmazenamentoLike | null = armazenamentoPadrao()): PedidoSalvo[] {
  if (!armazenamento) return []
  try {
    const bruto = JSON.parse(armazenamento.getItem(CHAVE_INGRESSOS_SALVOS) ?? '[]')
    return Array.isArray(bruto) ? bruto.filter(valido) : []
  } catch {
    return []
  }
}

function gravar(armazenamento: ArmazenamentoLike, itens: PedidoSalvo[]): void {
  try {
    armazenamento.setItem(CHAVE_INGRESSOS_SALVOS, JSON.stringify(itens))
  } catch {
    // armazenamento cheio ou bloqueado: segue sem salvar
  }
}

/**
 * Salva (ou atualiza) o pedido. Campos vazios na nova chamada nao apagam os
 * ja salvos. Mantem os mais recentes ate o limite.
 */
export function salvarPedido(
  dados: Omit<PedidoSalvo, 'salvoEm' | 'eventoInicioEm' | 'eventoLocal' | 'quantidade'> &
    Partial<Pick<PedidoSalvo, 'eventoInicioEm' | 'eventoLocal' | 'quantidade'>>,
  armazenamento: ArmazenamentoLike | null = armazenamentoPadrao(),
  agora: Date = new Date()
): void {
  if (!armazenamento || !UUID.test(dados.checkoutToken) || !dados.eventoSlug) return
  const atuais = lerPedidosSalvos(armazenamento)
  const anterior = atuais.find((p) => p.pedidoId === dados.pedidoId)
  const novo: PedidoSalvo = {
    pedidoId: dados.pedidoId,
    checkoutToken: dados.checkoutToken,
    codigoPedido: dados.codigoPedido || anterior?.codigoPedido || '',
    organizacaoSlug: dados.organizacaoSlug ?? anterior?.organizacaoSlug ?? null,
    eventoSlug: dados.eventoSlug,
    eventoNome: dados.eventoNome || anterior?.eventoNome || '',
    eventoInicioEm: dados.eventoInicioEm ?? anterior?.eventoInicioEm ?? null,
    eventoLocal: dados.eventoLocal ?? anterior?.eventoLocal ?? null,
    quantidade: dados.quantidade ?? anterior?.quantidade ?? null,
    salvoEm: anterior?.salvoEm ?? agora.toISOString()
  }
  const outros = atuais.filter((p) => p.pedidoId !== dados.pedidoId)
  gravar(armazenamento, [novo, ...outros].slice(0, LIMITE_INGRESSOS_SALVOS))
}

export function removerPedidoSalvo(
  pedidoId: string,
  armazenamento: ArmazenamentoLike | null = armazenamentoPadrao()
): void {
  if (!armazenamento) return
  gravar(
    armazenamento,
    lerPedidosSalvos(armazenamento).filter((p) => p.pedidoId !== pedidoId)
  )
}

/** Considera o evento passado 12h depois do inicio. */
export function eventoJaPassou(pedido: PedidoSalvo, agora: Date = new Date()): boolean {
  if (!pedido.eventoInicioEm) return false
  const inicio = Date.parse(pedido.eventoInicioEm)
  return Number.isFinite(inicio) && inicio + 12 * 3_600_000 < agora.getTime()
}

/** Proximos primeiro (do mais perto ao mais longe), depois os passados (mais recente primeiro). */
export function ordenarPedidosSalvos(itens: PedidoSalvo[], agora: Date = new Date()): PedidoSalvo[] {
  const chave = (p: PedidoSalvo) => p.eventoInicioEm ?? p.salvoEm
  const proximos = itens.filter((p) => !eventoJaPassou(p, agora)).sort((a, b) => chave(a).localeCompare(chave(b)))
  const passados = itens.filter((p) => eventoJaPassou(p, agora)).sort((a, b) => chave(b).localeCompare(chave(a)))
  return [...proximos, ...passados]
}
