import type {
  AdminEventoVendaManualRow,
  CriarVendaManualInput,
  EventoStatusVendaManual,
  EventoVendaManual,
  TipoVendaManual,
  VendaManualForm,
  VendaManualLoteAtivo
} from '~/types/vendaManual'

export const VENDA_MANUAL_QUANTIDADE_MIN = 1
export const VENDA_MANUAL_QUANTIDADE_MAX = 10

/** Arredonda para 2 casas decimais (mesma precisao de numeric(10,2)). */
function arredondarMoeda(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** Converte string monetaria (aceita virgula) em numero. */
export function normalizarValorMonetario(valor: string | number | null | undefined): number {
  if (typeof valor === 'number') return Number.isFinite(valor) ? valor : 0
  let texto = String(valor ?? '').trim()
  if (texto.includes(',')) {
    // virgula como separador decimal; pontos como milhar
    texto = texto.replace(/\./g, '').replace(',', '.')
  }
  const numero = Number(texto)
  return Number.isFinite(numero) ? numero : 0
}

/** Total sempre derivado do preco unitario x quantidade. */
export function calcularTotalVendaManual(preco: number, quantidade: number): number {
  const p = Number(preco) || 0
  const q = Number(quantidade) || 0
  if (p <= 0 || q <= 0) return 0
  return arredondarMoeda(p * q)
}

/** Converte a linha bruta da RPC no view-model da tela. */
export function mapearEventoVendaManual(row: AdminEventoVendaManualRow): EventoVendaManual {
  const lotesAtivos: VendaManualLoteAtivo[] = (row.lotes_ativos ?? []).map((lote) => ({
    id: lote.id,
    nome: lote.nome,
    preco: Number(lote.preco ?? 0),
    disponiveis: Number(lote.disponiveis ?? 0)
  }))

  return {
    id: row.evento_id,
    nome: row.nome,
    inicioEm: row.inicio_em,
    local: row.local,
    status: row.status as EventoStatusVendaManual,
    disponiveisEvento: Number(row.disponiveis_evento ?? 0),
    lotesAtivos,
    loteAtivo: lotesAtivos[0] ?? null
  }
}

/** Lote atualmente selecionado no formulario (modo LOTE). */
export function loteSelecionado(
  form: VendaManualForm,
  evento: EventoVendaManual | null
): VendaManualLoteAtivo | null {
  if (!evento) return null
  return evento.lotesAtivos.find((lote) => lote.id === form.loteId) ?? null
}

/** Preco unitario efetivo conforme o modo da venda. */
export function valorUnitarioEfetivo(
  form: VendaManualForm,
  evento: EventoVendaManual | null
): number {
  if (form.tipo === 'AVULSO') {
    return arredondarMoeda(normalizarValorMonetario(form.valorUnitario))
  }
  return loteSelecionado(form, evento)?.preco ?? 0
}

/** Garante que a lista de participantes tenha exatamente `quantidade` itens. */
export function ajustarParticipantes(
  participantes: string[],
  quantidade: number,
  compradorNome = ''
): string[] {
  const total = Math.min(
    Math.max(Number(quantidade) || VENDA_MANUAL_QUANTIDADE_MIN, VENDA_MANUAL_QUANTIDADE_MIN),
    VENDA_MANUAL_QUANTIDADE_MAX
  )
  const base = participantes.slice(0, total)
  while (base.length < total) {
    base.push(base.length === 0 ? compradorNome : '')
  }
  return base
}

export type VendaManualErrors = Partial<
  Record<
    'eventoId' | 'tipo' | 'loteId' | 'valorUnitario' | 'compradorNome' | 'quantidade' | 'participantes',
    string
  >
>

export function validarVendaManual(
  form: VendaManualForm,
  evento: EventoVendaManual | null
): VendaManualErrors {
  const erros: VendaManualErrors = {}

  if (!form.eventoId || !evento) erros.eventoId = 'Selecione o evento.'

  // telefone e opcional: nao entra na validacao

  if (!form.compradorNome.trim()) erros.compradorNome = 'Informe o nome do comprador.'

  const quantidade = Number(form.quantidade)
  if (
    !Number.isInteger(quantidade) ||
    quantidade < VENDA_MANUAL_QUANTIDADE_MIN ||
    quantidade > VENDA_MANUAL_QUANTIDADE_MAX
  ) {
    erros.quantidade = `Quantidade entre ${VENDA_MANUAL_QUANTIDADE_MIN} e ${VENDA_MANUAL_QUANTIDADE_MAX}.`
  }

  const participantes = form.participantes.slice(0, Math.max(quantidade, 0))
  if (participantes.length !== quantidade) {
    erros.participantes = 'Informe o nome de todos os participantes.'
  } else if (participantes.some((nome) => !nome.trim())) {
    erros.participantes = 'O nome do participante não pode ser vazio.'
  }

  if (form.tipo === 'AVULSO') {
    const valor = normalizarValorMonetario(form.valorUnitario)
    if (!Number.isFinite(valor) || valor <= 0) {
      erros.valorUnitario = 'Informe um valor unitário maior que zero.'
    }
  } else {
    if (!evento || evento.lotesAtivos.length === 0) {
      erros.loteId = 'Este evento não possui lote ativo.'
    } else if (!loteSelecionado(form, evento)) {
      erros.loteId = 'Selecione um lote.'
    }
  }

  return erros
}

/** Monta o payload da RPC. O backend recalcula preco/total no modo LOTE. */
export function montarPayloadVendaManual(form: VendaManualForm): CriarVendaManualInput {
  const email = form.compradorEmail.trim()
  const telefone = form.compradorTelefone.trim()
  const tipo: TipoVendaManual = form.tipo === 'AVULSO' ? 'AVULSO' : 'LOTE'
  const valor = tipo === 'AVULSO' ? arredondarMoeda(normalizarValorMonetario(form.valorUnitario)) : null

  return {
    eventoId: form.eventoId,
    loteId: tipo === 'LOTE' ? (form.loteId || null) : null,
    compradorNome: form.compradorNome.trim(),
    compradorTelefone: telefone ? telefone : null,
    compradorEmail: email ? email : null,
    tipoPreco: tipo,
    valorUnitario: valor,
    participantes: form.participantes.slice(0, form.quantidade).map((nome) => nome.trim())
  }
}

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

/** Traduz erros da RPC de venda manual para mensagens ao operador. */
export function mensagemErroVendaManual(error: RpcErrorLike | null): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()

  if (e.code === '42501' || mensagem.includes('permiss')) {
    return 'Você não tem permissão para registrar vendas manuais.'
  }
  if (mensagem.includes('estoque insuficiente')) {
    return 'Estoque insuficiente no evento.'
  }
  if (mensagem.includes('limite do lote')) {
    return 'Estoque insuficiente no lote selecionado.'
  }
  if (mensagem.includes('valor unitario') || mensagem.includes('valor unitário')) {
    return 'Informe um valor unitário maior que zero.'
  }
  if (mensagem.includes('nao esta ativo') || mensagem.includes('não está ativo')) {
    return 'O lote selecionado não está ativo.'
  }
  if (mensagem.includes('lote obrigatorio') || mensagem.includes('lote obrigatório')) {
    return 'Selecione um lote.'
  }
  if (mensagem.includes('nao pode ter lote') || mensagem.includes('não pode ter lote')) {
    return 'Venda com valor especial não deve ter lote.'
  }
  if (mensagem.includes('nao permite venda manual') || mensagem.includes('não permite venda manual')) {
    return 'Este evento não permite venda manual.'
  }
  if (mensagem.includes('nao encontrado') || mensagem.includes('não encontrado')) {
    return 'Evento ou lote não encontrado.'
  }
  if (e.code === '23514' || e.code === '22004') {
    return 'Não foi possível concluir a venda. Verifique os dados informados.'
  }
  return 'Não foi possível registrar a venda manual.'
}
