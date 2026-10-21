import { PAGINAS_SITEMAP, gerarSitemapXml } from '../../app/utils/seo'

export default defineEventHandler((event) => {
  const config = useRuntimeConfig(event)
  setHeader(event, 'content-type', 'application/xml; charset=utf-8')
  setHeader(event, 'cache-control', 'public, max-age=3600')
  return gerarSitemapXml(String(config.public.siteUrl ?? ''), PAGINAS_SITEMAP)
})
