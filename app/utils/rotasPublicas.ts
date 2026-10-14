/**
 * Rotas publicas por organizacao: /{casa}/{evento}.
 * Sem a casa (dado antigo), cai no formato legado /eventos/{evento}, que
 * redireciona para o novo endereco quando o slug e unico.
 */
export const ROTA_PAINEL = '/painel'

function seg(valor: string | null | undefined): string {
  return encodeURIComponent(String(valor ?? '').trim())
}

export function rotaOrganizacao(organizacaoSlug: string | null | undefined): string {
  const org = String(organizacaoSlug ?? '').trim()
  return org ? `/${seg(org)}` : '/'
}

export function rotaEvento(organizacaoSlug: string | null | undefined, eventoSlug: string): string {
  const org = String(organizacaoSlug ?? '').trim()
  return org ? `/${seg(org)}/${seg(eventoSlug)}` : `/eventos/${seg(eventoSlug)}`
}

export function rotaCheckout(organizacaoSlug: string | null | undefined, eventoSlug: string): string {
  return `${rotaEvento(organizacaoSlug, eventoSlug)}/comprar`
}

export function rotaPagamento(
  organizacaoSlug: string | null | undefined,
  eventoSlug: string,
  checkoutToken: string
): string {
  return `${rotaCheckout(organizacaoSlug, eventoSlug)}/pagamento?token=${seg(checkoutToken)}`
}

export function rotaIngressosPedido(
  organizacaoSlug: string | null | undefined,
  eventoSlug: string,
  checkoutToken: string
): string {
  return `${rotaCheckout(organizacaoSlug, eventoSlug)}/ingressos?token=${seg(checkoutToken)}`
}

/** URL absoluta para divulgacao (ex.: https://ingressoudi.com/casa/evento). */
export function urlPublicaAbsoluta(siteUrl: string | null | undefined, caminho: string): string {
  const base = String(siteUrl ?? '').trim().replace(/\/+$/, '')
  return base ? `${base}${caminho}` : caminho
}
