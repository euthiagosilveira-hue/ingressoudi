import type { IngressoBuscaNome } from '~/types/gate'

/** Normaliza nome para comparacao de homonimos. */
export function normalizarNomeBusca(nome: string | null | undefined): string {
  return String(nome ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ')
}

/**
 * Hint de nome minimo: somente com 1 caractere util (apos trim).
 * Vazio/espacos -> sem hint; 2+ -> sem hint.
 */
export function precisaHintNome(nome: string | null | undefined): boolean {
  return String(nome ?? '').trim().length === 1
}

/**
 * Mascara telefone para exibicao na portaria. Nunca mostra o numero completo.
 * Sem digitos suficientes (null/vazio/curto) -> string vazia (linha oculta).
 */
export function mascararTelefone(telefone: string | null | undefined): string {
  const digitos = String(telefone ?? '').replace(/\D/g, '')
  if (digitos.length < 4) return ''
  const finais = digitos.slice(-4)
  if (digitos.length >= 10) {
    return `(${digitos.slice(0, 2)}) *****-${finais}`
  }
  return `*****-${finais}`
}

export function rotuloOrigem(origem: string | null | undefined): string {
  return origem === 'VIP' ? 'VIP' : 'Ingresso'
}

/** Nomes (normalizados) que aparecem 2+ vezes no conjunto de resultados. */
export function nomesAmbiguos(resultados: IngressoBuscaNome[]): Set<string> {
  const contagem = new Map<string, number>()
  for (const item of resultados) {
    const chave = normalizarNomeBusca(item.participanteNome)
    contagem.set(chave, (contagem.get(chave) ?? 0) + 1)
  }
  const ambiguos = new Set<string>()
  for (const [chave, total] of contagem) {
    if (total >= 2) ambiguos.add(chave)
  }
  return ambiguos
}

/** O item selecionado pertence a um grupo ambiguo (homonimos)? */
export function itemExigeConfirmacao(
  item: IngressoBuscaNome,
  resultados: IngressoBuscaNome[]
): boolean {
  return nomesAmbiguos(resultados).has(normalizarNomeBusca(item.participanteNome))
}

/** Linha compacta de confirmacao (sem dado financeiro/administrativo). */
export function descricaoConfirmacao(item: IngressoBuscaNome): string {
  const partes: string[] = [item.participanteNome, rotuloOrigem(item.origem)]
  if (item.codigo) partes.push(item.codigo)
  const tel = mascararTelefone(item.telefone)
  if (tel) partes.push(tel)
  return partes.join(' • ')
}
