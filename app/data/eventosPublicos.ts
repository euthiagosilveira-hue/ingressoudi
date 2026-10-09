import type { PublicEventDetail } from '~/types/publicEvento'
import { resolverSituacaoVenda } from '~/utils/publicEvento'

function publico(base: Omit<PublicEventDetail, 'situacaoVenda'>): PublicEventDetail {
  return { ...base, situacaoVenda: resolverSituacaoVenda(base) }
}

/**
 * FALLBACK DE DESENVOLVIMENTO (temporario).
 *
 * A fonte principal do catalogo publico e o Supabase
 * (RPCs public.listar_eventos_publicos / public.obter_evento_publico).
 * Estes mocks sao usados SOMENTE em desenvolvimento (import.meta.dev) quando
 * o banco esta vazio ou a RPC falha, via useCatalogoPublico.
 *
 * TODO: remover este arquivo quando houver eventos reais persistidos e o
 * fluxo publico validado ponta a ponta.
 */
export const eventosPublicosMock: PublicEventDetail[] = [
  publico({
    eventoId: 'evt_001',
    slug: 'banda-conexao',
    nome: 'Banda Conexão',
    descricao:
      'A Banda Conexão volta à Galeria Zero 1 para uma noite de rock autoral e clássicos que marcaram geração.\n\nCom uma formação de seis músicos, o show mistura composições próprias do novo álbum com releituras de clássicos brasileiros, em um set de cerca de duas horas.\n\nPorta abre às 21h. Espaço com bar completo, área externa e guarda-volumes.',
    imagemUrl: '/mock/evento-1.svg',
    inicioEm: '2026-08-29T22:00:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ABERTAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: 'lote_001',
    loteNome: 'Lote 1',
    preco: 40,
    disponiveis: 18
  }),
  publico({
    eventoId: 'evt_002',
    slug: 'noite-do-rock',
    nome: 'Noite do Rock',
    descricao:
      'Uma noite inteira dedicada ao rock em todas as suas vertentes.\n\nTrês bandas se apresentam em sequência, com DJ set entre os shows. Venha cedo para aproveitar o espaço e o happy hour da casa.',
    imagemUrl: '/mock/evento-2.svg',
    inicioEm: '2026-09-12T21:30:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ABERTAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: 'lote_005',
    loteNome: 'Lote 2',
    preco: 80,
    disponiveis: 96
  }),
  publico({
    eventoId: 'evt_008',
    slug: 'acustico-no-terraco',
    nome: 'Acústico no Terraço',
    descricao:
      'Formato intimista no terraço da Galeria Zero 1, com vista aberta da cidade.\n\nRepertório acústico, mesas limitadas e serviço de bar no local. O lote de ingressos será divulgado em breve.',
    imagemUrl: null,
    inicioEm: '2026-09-27T20:30:00-03:00',
    local: 'Terraço Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ABERTAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: null,
    loteNome: null,
    preco: null,
    disponiveis: 120
  }),
  publico({
    eventoId: 'evt_005',
    slug: 'samba-do-zero',
    nome: 'Samba do Zero',
    descricao:
      'Roda de samba tradicional da casa, com convidados especiais e participação do público.\n\nEvento em andamento — a venda antecipada está encerrada.',
    imagemUrl: '/mock/evento-3.svg',
    inicioEm: '2026-09-20T19:00:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'EM_ANDAMENTO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: null,
    loteNome: null,
    preco: null,
    disponiveis: 0
  }),
  publico({
    eventoId: 'evt_006',
    slug: 'exposicao-urbana',
    nome: 'Exposição Urbana',
    descricao:
      'Mostra coletiva de arte urbana que ocupou a Galeria Zero 1 durante o mês de julho.\n\nPágina mantida como registro histórico do evento.',
    imagemUrl: null,
    inicioEm: '2026-07-10T19:00:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'REALIZADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: null,
    loteNome: null,
    preco: null,
    disponiveis: 0
  }),
  publico({
    eventoId: 'evt_007',
    slug: 'baile-de-mascaras',
    nome: 'Baile de Máscaras',
    descricao:
      'O tradicional baile de máscaras da casa. Evento cancelado pela produção.',
    imagemUrl: null,
    inicioEm: '2026-10-31T23:00:00-03:00',
    local: 'Salão Nobre',
    endereco: 'Rua das Flores, 200 — Centro, São Paulo',
    status: 'CANCELADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: 'lote_007',
    loteNome: 'Lote 1',
    preco: 45,
    disponiveis: 88
  }),
  publico({
    eventoId: 'pub_001',
    slug: 'festival-zero-sunset',
    nome: 'Festival Zero Sunset',
    descricao:
      'Festival de um dia inteiro com quatro palcos, gastronomia e intervenções artísticas.\n\nTodos os ingressos da venda antecipada foram esgotados.',
    imagemUrl: '/mock/evento-3.svg',
    inicioEm: '2026-12-20T18:00:00-03:00',
    local: 'Arena Central',
    endereco: 'Rod. dos Bandeirantes, km 20 — São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ABERTAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: 'lote_pub_001',
    loteNome: 'Lote Final',
    preco: 90,
    disponiveis: 0
  }),
  publico({
    eventoId: 'pub_002',
    slug: 'mostra-noturna',
    nome: 'Mostra Noturna',
    descricao:
      'Sessão única de cinema e performance audiovisual na Galeria Zero 1.\n\nA venda antecipada foi encerrada.',
    imagemUrl: null,
    inicioEm: '2026-11-15T23:30:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    loteId: 'lote_pub_002',
    loteNome: 'Lote 1',
    preco: 50,
    disponiveis: 30
  }),
  // RASCUNHOS: existem no mock apenas para validar que a resolucao publica
  // os trata como nao encontrados (espelhando a futura RPC).
  publico({
    eventoId: 'evt_003',
    slug: 'festival-verao',
    nome: 'Festival Verão',
    descricao: 'Evento em rascunho.',
    imagemUrl: null,
    inicioEm: '2026-12-20T18:00:00-03:00',
    local: 'Arena Central',
    endereco: 'Rod. dos Bandeirantes, km 20 — São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'RASCUNHO',
    loteId: null,
    loteNome: null,
    preco: null,
    disponiveis: 0
  }),
  publico({
    eventoId: 'evt_009',
    slug: 'techno-night',
    nome: 'Techno Night',
    descricao: 'Evento em rascunho.',
    imagemUrl: '/mock/evento-2.svg',
    inicioEm: '2026-11-15T23:30:00-03:00',
    local: 'Galeria Zero 1',
    endereco: 'Av. Paulista, 1000 — Bela Vista, São Paulo',
    status: 'AGENDADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'RASCUNHO',
    loteId: null,
    loteNome: null,
    preco: null,
    disponiveis: 0
  })
]

export function buscarEventoPublico(slug: string): PublicEventDetail | null {
  const evento = eventosPublicosMock.find((item) => item.slug === slug)
  if (!evento || evento.publicacaoStatus !== 'PUBLICADO') return null
  return evento
}

export function listarEventosPublicos(): PublicEventDetail[] {
  return eventosPublicosMock.filter((item) => item.publicacaoStatus === 'PUBLICADO')
}
