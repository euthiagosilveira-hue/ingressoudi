export type PlataformaInstalacao = 'ios' | 'android' | 'outra'

interface NavegadorLike {
  userAgent?: string
  maxTouchPoints?: number
  standalone?: boolean
}

/** iPhone/iPad (o iPadOS se apresenta como Mac, mas tem tela de toque). */
export function detectarPlataforma(navegador: NavegadorLike | null | undefined): PlataformaInstalacao {
  const ua = navegador?.userAgent ?? ''
  if (/iPhone|iPad|iPod/i.test(ua)) return 'ios'
  if (/Macintosh/i.test(ua) && (navegador?.maxTouchPoints ?? 0) > 1) return 'ios'
  if (/Android/i.test(ua)) return 'android'
  return 'outra'
}

/** O site ja esta aberto como app instalado (tela cheia, sem barra do navegador)? */
export function abertoComoApp(
  navegador: NavegadorLike | null | undefined,
  matchMedia?: ((consulta: string) => { matches: boolean }) | null
): boolean {
  if (navegador?.standalone === true) return true
  try {
    return Boolean(matchMedia?.('(display-mode: standalone)').matches)
  } catch {
    return false
  }
}

/**
 * Quando mostrar o botao "Instalar app": nunca dentro do app instalado; com o
 * convite nativo do navegador (Android/computador) ou com instrucoes (iPhone e
 * Android sem o convite nativo).
 */
export function deveMostrarInstalar(opcoes: {
  instalado: boolean
  conviteNativo: boolean
  plataforma: PlataformaInstalacao
}): boolean {
  if (opcoes.instalado) return false
  if (opcoes.conviteNativo) return true
  return opcoes.plataforma === 'ios' || opcoes.plataforma === 'android'
}

export interface PassoInstalacao {
  titulo: string
  texto: string
}

/** Passo a passo para instalar quando o navegador nao oferece o convite nativo. */
export function passosInstalacao(plataforma: PlataformaInstalacao): PassoInstalacao[] {
  if (plataforma === 'ios') {
    return [
      { titulo: 'Abra no Safari', texto: 'Se estiver em outro navegador, abra www.ingressoudi.com.br no Safari.' },
      { titulo: 'Toque em Compartilhar', texto: 'É o ícone do quadrado com a seta para cima, na barra do Safari.' },
      { titulo: 'Adicionar à Tela de Início', texto: 'Role a lista, toque em "Adicionar à Tela de Início" e confirme em "Adicionar".' }
    ]
  }
  return [
    { titulo: 'Abra o menu do navegador', texto: 'No Chrome, toque nos três pontinhos no canto superior direito.' },
    { titulo: 'Instalar app', texto: 'Toque em "Instalar app" ou "Adicionar à tela inicial" e confirme.' }
  ]
}

/**
 * Para onde o app instalado abre: equipe logada vai para o painel ou a
 * portaria; comprador com ingressos salvos vai para "Meus ingressos".
 */
export function destinoAoAbrirApp(opcoes: {
  perfil: string | null | undefined
  ativo?: boolean | null
  temIngressosSalvos: boolean
}): string {
  if (opcoes.perfil && opcoes.ativo !== false) {
    return opcoes.perfil === 'PORTARIA' ? '/portaria' : '/painel'
  }
  if (opcoes.temIngressosSalvos) return '/recuperar-ingressos'
  return '/'
}
