// Video de apresentacao da plataforma, exibido na pagina inicial.
// Cole aqui o link do YouTube (publico ou nao listado). Vazio = bloco escondido.
export const VIDEO_APRESENTACAO_URL = 'https://youtu.be/URZ9zDLiaWM'

const ID_YOUTUBE = /^[A-Za-z0-9_-]{11}$/

// Aceita os formatos comuns de link do YouTube (watch, youtu.be, shorts, embed)
// ou o proprio ID. Devolve null se nao reconhecer.
export function idVideoYoutube(link: string | null | undefined): string | null {
  const texto = String(link ?? '').trim()
  if (!texto) return null
  if (ID_YOUTUBE.test(texto)) return texto

  let url: URL
  try {
    url = new URL(texto.startsWith('http') ? texto : `https://${texto}`)
  } catch {
    return null
  }

  const host = url.hostname.replace(/^(www\.|m\.)/, '')
  let id: string | null = null
  if (host === 'youtu.be') {
    id = url.pathname.split('/')[1] ?? null
  } else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    if (url.pathname === '/watch') id = url.searchParams.get('v')
    else {
      const [, tipo, valor] = url.pathname.split('/')
      if (tipo === 'embed' || tipo === 'shorts' || tipo === 'live') id = valor ?? null
    }
  }
  return id && ID_YOUTUBE.test(id) ? id : null
}

// Player sem cookies de rastreamento, iniciado pelo clique do visitante.
export function urlEmbedYoutube(id: string): string {
  const params = new URLSearchParams({ autoplay: '1', rel: '0', modestbranding: '1', playsinline: '1' })
  return `https://www.youtube-nocookie.com/embed/${id}?${params.toString()}`
}
