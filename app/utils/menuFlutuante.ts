/**
 * Posicao de um menu flutuante (position: fixed) ancorado em um botao.
 * Abre abaixo e alinhado a direita do botao; se nao couber abaixo e houver
 * mais espaco acima, abre para cima. Nunca sai da janela.
 */
export interface RetanguloAncora {
  top: number
  bottom: number
  left: number
  right: number
}

export function calcularPosicaoMenu(
  ancora: RetanguloAncora,
  menu: { largura: number; altura: number },
  janela: { largura: number; altura: number },
  margem = 8
): { top: number; left: number } {
  const espacoAbaixo = janela.altura - ancora.bottom - margem
  const espacoAcima = ancora.top - margem
  const abrirAcima = menu.altura + margem > espacoAbaixo && espacoAcima > espacoAbaixo

  let top = abrirAcima ? ancora.top - margem - menu.altura : ancora.bottom + margem
  top = Math.max(margem, Math.min(top, janela.altura - margem - menu.altura))

  let left = ancora.right - menu.largura
  left = Math.max(margem, Math.min(left, janela.largura - margem - menu.largura))

  return { top: Math.round(top), left: Math.round(left) }
}
