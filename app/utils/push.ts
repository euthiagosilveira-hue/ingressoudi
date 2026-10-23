/** Chave publica VAPID (base64url) no formato que o PushManager espera. */
export function chaveVapidParaBytes(base64url: string): Uint8Array {
  const preenchimento = '='.repeat((4 - (base64url.length % 4)) % 4)
  const base64 = (base64url + preenchimento).replace(/-/g, '+').replace(/_/g, '/')
  const bruto = atob(base64)
  const bytes = new Uint8Array(bruto.length)
  for (let i = 0; i < bruto.length; i += 1) bytes[i] = bruto.charCodeAt(i)
  return bytes
}

export type SituacaoPush = 'sem-suporte' | 'instalar-iphone' | 'bloqueado' | 'desativado' | 'ativado'

/** iPhone/iPad so recebem push com o app instalado na tela de inicio. */
export function precisaInstalarNoIphone(userAgent: string, standalone: boolean): boolean {
  const ios = /iPhone|iPad|iPod/i.test(userAgent)
  return ios && !standalone
}

export function textoSituacaoPush(situacao: SituacaoPush): string {
  switch (situacao) {
    case 'ativado':
      return 'Este aparelho recebe um aviso quando uma casa nova se cadastrar ou houver erro em pagamentos.'
    case 'desativado':
      return 'Ative para receber um aviso neste aparelho quando uma casa nova se cadastrar ou houver erro em pagamentos.'
    case 'bloqueado':
      return 'As notificações estão bloqueadas para este site. Libere nas configurações do navegador e tente de novo.'
    case 'instalar-iphone':
      return 'No iPhone, instale o app primeiro: no Safari, toque em Compartilhar e depois em "Adicionar à Tela de Início".'
    default:
      return 'Este navegador não recebe notificações. Use o Chrome no Android ou no computador.'
  }
}
