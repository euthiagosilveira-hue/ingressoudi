/**
 * SEO: endereco canonico, sitemap e dados estruturados da pagina inicial.
 * Funcoes puras para rodar igual no servidor (sitemap.xml) e na pagina.
 */
import { PLATAFORMA_NOME } from './marca.ts'

/** Endereco oficial quando NUXT_PUBLIC_SITE_URL nao estiver definido. */
export const SITE_URL_PADRAO = 'https://www.ingressoudi.com.br'

export const DESCRICAO_PLATAFORMA =
  'Venda ingressos online com Pix direto na sua conta Mercado Pago, controle a entrada com QR Code no celular e gerencie lista VIP e vendas na porta.'

/** Imagem de compartilhamento padrao (1200x630, em /public). */
export const IMAGEM_SOCIAL = '/og-image.png'

/** Paginas publicas fixas que entram no sitemap. */
export const PAGINAS_SITEMAP: readonly string[] = [
  '/',
  '/cadastro',
  '/recuperar-ingressos',
  '/termos',
  '/privacidade',
  '/reembolso'
]

/**
 * Origem sem barra final; cai no endereco oficial se vier vazia, invalida ou
 * for um endereco temporario da Vercel (o Google deve indexar so o dominio).
 */
export function origemSite(siteUrl: string | null | undefined): string {
  const valor = String(siteUrl ?? '').trim().replace(/\/+$/, '')
  if (!/^https?:\/\/[^/\s]+$/i.test(valor)) return SITE_URL_PADRAO
  if (/\.vercel\.app$/i.test(valor) || /\/\/localhost(:\d+)?$/i.test(valor)) return SITE_URL_PADRAO
  return valor
}

/** URL canonica: origem + caminho, sem query nem hash e sem barra final (exceto a raiz). */
export function urlCanonica(siteUrl: string | null | undefined, caminho: string): string {
  let path = String(caminho ?? '/').split(/[?#]/)[0] || '/'
  if (!path.startsWith('/')) path = `/${path}`
  if (path.length > 1) path = path.replace(/\/+$/, '')
  return origemSite(siteUrl) + (path === '/' ? '/' : path)
}

/** URL absoluta para um arquivo publico (ex.: imagem de compartilhamento). */
export function urlAbsoluta(siteUrl: string | null | undefined, caminhoOuUrl: string): string {
  const valor = String(caminhoOuUrl ?? '').trim()
  if (/^https?:\/\//i.test(valor)) return valor
  return origemSite(siteUrl) + (valor.startsWith('/') ? valor : `/${valor}`)
}

function escaparXml(texto: string): string {
  return texto
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

export function gerarSitemapXml(siteUrl: string | null | undefined, caminhos: readonly string[]): string {
  const vistos = new Set<string>()
  const urls: string[] = []
  for (const caminho of caminhos) {
    const loc = urlCanonica(siteUrl, caminho)
    if (vistos.has(loc)) continue
    vistos.add(loc)
    urls.push(`  <url><loc>${escaparXml(loc)}</loc></url>`)
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>\n`
}

/** JSON-LD da pagina inicial: a empresa e o site. */
export function dadosEstruturadosPlataforma(siteUrl: string | null | undefined): Record<string, unknown> {
  const origem = origemSite(siteUrl)
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Organization',
        '@id': `${origem}/#organizacao`,
        name: PLATAFORMA_NOME,
        url: `${origem}/`,
        logo: `${origem}/icon-512.png`
      },
      {
        '@type': 'WebSite',
        '@id': `${origem}/#site`,
        name: PLATAFORMA_NOME,
        url: `${origem}/`,
        inLanguage: 'pt-BR',
        publisher: { '@id': `${origem}/#organizacao` }
      }
    ]
  }
}
