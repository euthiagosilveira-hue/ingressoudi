/**
 * Marca central da plataforma. Nada de nome de casa fixo no codigo: a marca
 * da organizacao vem do banco (organizacoes.nome / logo_url).
 */
export const PLATAFORMA_NOME = 'Ingressoudi'

/** Cor de destaque padrao (ambar) quando a casa nao define uma. */
export const COR_PADRAO = '#fbbf24'

/**
 * E-mail de contato da plataforma (termos, privacidade, suporte ao produtor).
 * Vazio = as paginas legais exibem um texto generico no lugar.
 */
export const CONTATO_EMAIL = ''

/** Normaliza #RRGGBB; retorna null se invalida. */
export function normalizarCor(cor: string | null | undefined): string | null {
  const valor = String(cor ?? '').trim().toLowerCase()
  return /^#[0-9a-f]{6}$/.test(valor) ? valor : null
}

/** Texto legivel sobre a cor (escuro em cores claras, branco em cores escuras). */
export function corTextoContraste(cor: string | null | undefined): string {
  const hex = normalizarCor(cor) ?? COR_PADRAO
  const r = parseInt(hex.slice(1, 3), 16) / 255
  const g = parseInt(hex.slice(3, 5), 16) / 255
  const b = parseInt(hex.slice(5, 7), 16) / 255
  const lin = (c: number) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
  const luminancia = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
  return luminancia > 0.4 ? '#09090b' : '#ffffff'
}

/** Iniciais para avatar (ex.: "Galeria Teste" -> "GT"). */
export function iniciais(nome: string | null | undefined): string {
  const partes = String(nome ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return '?'
  const letras = partes.length === 1 ? partes[0]!.slice(0, 2) : partes[0]![0]! + partes[partes.length - 1]![0]!
  return letras.toUpperCase()
}

/** Titulo de pagina publica: "<parte> | <casa ou plataforma>". */
export function tituloPublico(parte?: string | null, casa?: string | null): string {
  const final = (casa ?? '').trim() || PLATAFORMA_NOME
  const inicio = (parte ?? '').trim()
  return inicio ? `${inicio} | ${final}` : final
}
