/**
 * Marca central da plataforma. Nada de nome de casa fixo no codigo: a marca
 * da organizacao vem do banco (organizacoes.nome / logo_url).
 */
export const PLATAFORMA_NOME = 'Ingressoudi'

/** Titulo de pagina publica: "<parte> | <casa ou plataforma>". */
export function tituloPublico(parte?: string | null, casa?: string | null): string {
  const final = (casa ?? '').trim() || PLATAFORMA_NOME
  const inicio = (parte ?? '').trim()
  return inicio ? `${inicio} | ${final}` : final
}
