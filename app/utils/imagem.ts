/**
 * Retorna a URL apenas se for persistente e exibivel.
 * Rejeita blob:/data:/caminhos relativos invalidos (nao persistem apos reload)
 * e vazios, para nunca renderizar uma imagem quebrada.
 */
export function imagemValida(url: string | null | undefined): string | null {
  if (!url) return null
  const valor = url.trim()
  if (!valor) return null
  if (/^(blob:|data:)/i.test(valor)) return null
  if (/^https?:\/\//i.test(valor)) return valor
  if (valor.startsWith('/')) return valor
  return null
}
