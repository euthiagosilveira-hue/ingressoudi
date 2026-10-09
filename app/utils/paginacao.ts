export function paginar<T>(itens: T[], pagina: number, porPagina: number): T[] {
  const inicio = (pagina - 1) * porPagina
  return itens.slice(inicio, inicio + porPagina)
}

export function totalPaginas(total: number, porPagina: number): number {
  return Math.max(Math.ceil(total / porPagina), 1)
}
