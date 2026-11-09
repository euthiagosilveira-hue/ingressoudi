/**
 * Central de ajuda: artigos passo a passo com prints das telas.
 * As imagens ficam em public/ajuda/<nome>.webp e foram geradas com dados ficticios.
 */

export type PublicoAjuda = 'produtor' | 'equipe' | 'comprador'

export interface PassoAjuda {
  texto: string
  /** Nome do arquivo em public/ajuda, sem extensao. */
  imagem?: string
  /** Descricao da imagem para leitores de tela. */
  alt?: string
  /** Prints feitos no celular aparecem mais estreitos. */
  celular?: boolean
}

export interface ArtigoAjuda {
  slug: string
  titulo: string
  resumo: string
  categoria: CategoriaAjudaId
  publico: PublicoAjuda[]
  /** Palavras extras que ajudam a busca (sinonimos, duvidas comuns). */
  palavras: string[]
  antes?: string
  passos: PassoAjuda[]
  problemas?: { pergunta: string; resposta: string }[]
}

export type CategoriaAjudaId = 'primeiros-passos' | 'equipe' | 'eventos' | 'dia-do-evento' | 'acompanhar' | 'comprador'

export interface CategoriaAjuda {
  id: CategoriaAjudaId
  titulo: string
  descricao: string
}

export const CATEGORIAS_AJUDA: readonly CategoriaAjuda[] = [
  { id: 'primeiros-passos', titulo: 'Primeiros passos', descricao: 'Cadastro, liberação e Mercado Pago.' },
  { id: 'equipe', titulo: 'Equipe', descricao: 'Convidar pessoas e ativar o acesso.' },
  { id: 'eventos', titulo: 'Eventos e vendas', descricao: 'Criar o evento, lotes, meia-entrada e divulgação.' },
  { id: 'dia-do-evento', titulo: 'Dia do evento', descricao: 'Portaria, venda na porta e Lista VIP.' },
  { id: 'acompanhar', titulo: 'Acompanhar resultados', descricao: 'Vendas, entradas e valores.' },
  { id: 'comprador', titulo: 'Para quem compra', descricao: 'Como comprar e onde achar o ingresso.' }
]

export const ROTULO_PUBLICO: Record<PublicoAjuda, string> = {
  produtor: 'Produtor',
  equipe: 'Equipe da portaria',
  comprador: 'Comprador'
}

export const ARTIGOS_AJUDA: readonly ArtigoAjuda[] = [
  {
    slug: 'criar-conta',
    titulo: 'Como criar sua conta de produtor',
    resumo: 'Crie seu acesso e a página da sua casa ou produtora em poucos minutos.',
    categoria: 'primeiros-passos',
    publico: ['produtor'],
    palavras: ['cadastro', 'cadastrar', 'registrar', 'conta', 'começar', 'casa', 'produtora', 'endereço', 'senha', 'e-mail'],
    antes: 'Você só precisa de um e-mail. Não tem mensalidade: você paga apenas uma taxa por ingresso vendido online.',
    passos: [
      {
        texto: 'Entre em www.ingressoudi.com.br e clique em **Começar grátis**.',
        imagem: 'home-comecar',
        alt: 'Página inicial do Ingressoudi com o botão Começar grátis'
      },
      {
        texto:
          'Preencha **Seu nome**, **E-mail**, **Senha** e **Confirmar senha** (mínimo de 8 caracteres). Depois, o **Nome** da sua casa ou produtora. O **Endereço da sua página** é criado sozinho; quando aparecer **Endereço disponível** em verde, ele é seu. Marque que aceita os Termos de uso e clique em **Criar conta**.',
        imagem: 'cadastro-formulario',
        alt: 'Formulário Crie sua conta de produtor preenchido'
      },
      {
        texto:
          'Abra o seu e-mail e clique no link de confirmação. O link abre o Ingressoudi, cria a sua casa e leva você direto ao painel.',
        imagem: 'cadastro-confirme-email',
        alt: 'Aviso de que o link de confirmação foi enviado por e-mail'
      }
    ],
    problemas: [
      { pergunta: 'Apareceu "Este e-mail já tem conta".', resposta: 'Você já se cadastrou antes. Clique em Entrar e use a senha que criou.' },
      { pergunta: 'Apareceu "Esse endereço já está em uso".', resposta: 'Outra casa já usa esse endereço. Escolha outro, por exemplo acrescentando a cidade.' },
      { pergunta: 'O e-mail de confirmação não chegou.', resposta: 'Olhe a caixa de spam e as abas Promoções ou Atualizações do seu e-mail.' },
      { pergunta: 'Apareceu "Este link expirou ou já foi utilizado".', resposta: 'Entre com o e-mail e a senha que você cadastrou para concluir o cadastro.' }
    ]
  },
  {
    slug: 'cadastro-em-analise',
    titulo: 'Cadastro em análise: o que já dá para fazer',
    resumo: 'Enquanto a equipe Ingressoudi aprova a sua casa, você já pode deixar tudo pronto.',
    categoria: 'primeiros-passos',
    publico: ['produtor'],
    palavras: ['análise', 'aprovação', 'aprovar', 'liberação', 'liberar', 'liberado', 'publicar', 'bloqueado', 'aguardando'],
    passos: [
      {
        texto:
          'Todo cadastro novo passa por uma análise rápida. Enquanto isso, o topo do painel mostra o aviso **Sua casa está em análise.**',
        imagem: 'casa-em-analise',
        alt: 'Aviso Sua casa está em análise no topo do painel'
      },
      {
        texto:
          'Durante a análise você já pode conectar o Mercado Pago, convidar a equipe, escolher a cor da sua página e criar os eventos como rascunho.'
      },
      {
        texto:
          'Quando o aviso some do painel, a casa está aprovada e você já pode publicar eventos e vender. Pagamento com cartão e Lista VIP são liberados por casa: peça à equipe Ingressoudi se quiser usar.'
      }
    ]
  },
  {
    slug: 'conectar-mercado-pago',
    titulo: 'Como conectar o Mercado Pago',
    resumo: 'O dinheiro das vendas online cai direto na sua conta do Mercado Pago.',
    categoria: 'primeiros-passos',
    publico: ['produtor'],
    palavras: ['mercado pago', 'pix', 'receber', 'dinheiro', 'conta', 'pagamento', 'taxa', 'conectar', 'reconectar', 'desconectar', 'repasse'],
    antes:
      'Tenha uma conta no Mercado Pago com uma chave Pix cadastrada. Só quem tem o perfil Administrador consegue conectar.',
    passos: [
      {
        texto: 'No menu lateral, abra **Configurações** e clique no card **Mercado Pago**.',
        imagem: 'configuracoes-cards',
        alt: 'Tela Configurações com os cards Usuários, Sua página de eventos e Mercado Pago'
      },
      {
        texto:
          'Sem conta conectada, seus clientes não conseguem pagar. Clique em **Conectar Mercado Pago**, entre com a sua conta no site do Mercado Pago e autorize o Ingressoudi. Sua senha fica só com o Mercado Pago.',
        imagem: 'mp-taxa',
        alt: 'Tela Mercado Pago com Nenhuma conta conectada e o botão Conectar Mercado Pago'
      },
      {
        texto:
          'Pronto: aparece **Conta conectada** com a data da conexão. Logo abaixo está a **Taxa de serviço** por ingresso, descontada automaticamente em cada venda online. Vendas em dinheiro registradas no painel não têm taxa.',
        imagem: 'mp-conectado',
        alt: 'Tela Mercado Pago com a conta conectada e os botões Reconectar e Desconectar'
      }
    ],
    problemas: [
      { pergunta: 'Troquei de conta no Mercado Pago.', resposta: 'Use Reconectar e entre com a conta nova.' },
      { pergunta: 'O que acontece se eu clicar em Desconectar?', resposta: 'As vendas online ficam suspensas até você conectar uma conta de novo.' },
      { pergunta: 'Apareceu "A autorização demorou demais".', resposta: 'Clique em Conectar Mercado Pago outra vez.' },
      { pergunta: 'Quem paga a taxa do cartão?', resposta: 'A taxa da operadora fica com a casa. Os juros do parcelamento são pagos pelo comprador.' }
    ]
  },
  {
    slug: 'convidar-equipe',
    titulo: 'Como convidar sua equipe',
    resumo: 'Cada pessoa entra com o próprio login, e o perfil define o que ela vê.',
    categoria: 'equipe',
    publico: ['produtor'],
    palavras: ['usuário', 'usuários', 'convite', 'convidar', 'porteiro', 'portaria', 'perfil', 'administrador', 'equipe', 'acesso', 'whatsapp', 'link', 'inativo', 'sócio', 'socio', 'parceiro', 'vendas'],
    antes:
      'Perfil Administrador vê tudo: eventos, pedidos, financeiro e configurações. Perfil Portaria vê só a tela de validação de ingressos. Perfil Sócio do Evento vê só os números de venda dos eventos que você marcar, sem nomes de compradores e sem poder alterar nada.',
    passos: [
      {
        texto:
          'Abra **Configurações** e clique em **Usuários**. Aqui estão todas as pessoas com acesso ao painel e à portaria. Clique em **Convidar usuário**.',
        imagem: 'usuarios-lista',
        alt: 'Lista de usuários com nome, e-mail, perfil e status'
      },
      {
        texto: 'Preencha **Nome** e **E-mail**, escolha o **Perfil** e clique em **Gerar convite**. Para um sócio, escolha **Sócio do Evento** e marque os eventos que ele vai acompanhar.',
        imagem: 'convite-formulario',
        alt: 'Janela Convidar usuário com nome, e-mail e perfil Portaria'
      },
      {
        texto:
          'Aparece um link só para essa pessoa. Clique em **Enviar no WhatsApp** (a mensagem já vai pronta) ou em **Copiar link** para mandar por onde quiser.',
        imagem: 'convite-criado',
        alt: 'Janela Convite criado com o link e os botões Copiar link e Enviar no WhatsApp'
      },
      {
        texto:
          'Enquanto a pessoa não aceitar, ela aparece na lista como **Convite pendente**. O link vale uma vez só e expira em 24 horas. Se ela perder o link, clique em **Novo link**; o anterior para de funcionar.'
      }
    ],
    problemas: [
      { pergunta: 'Como tiro alguém da equipe?', resposta: 'Na lista de usuários, clique em Editar e mude o Status para Inativo.' },
      { pergunta: 'A pessoa já tem conta no Ingressoudi.', resposta: 'Ela é adicionada direto à sua equipe e entra com a senha de sempre.' },
      { pergunta: 'Como libero outro evento para o sócio?', resposta: 'Na lista de usuários, clique em Editar no sócio, marque o evento e salve. Desmarcar tira o acesso àquele evento na hora.' }
    ]
  },
  {
    slug: 'aceitar-convite',
    titulo: 'Recebi um convite: como ativar meu acesso',
    resumo: 'Para quem foi convidado pela casa: aceite o convite e crie sua senha.',
    categoria: 'equipe',
    publico: ['equipe'],
    palavras: ['convite', 'aceitar', 'senha', 'criar senha', 'porteiro', 'primeiro acesso', 'link expirou'],
    passos: [
      {
        texto: 'Toque no link que você recebeu e depois em **Aceitar convite**.',
        imagem: 'aceitar-convite',
        alt: 'Tela Você foi convidado com o botão Aceitar convite',
        celular: true
      },
      {
        texto:
          'Crie uma senha com pelo menos 8 caracteres em **Nova senha** e **Confirmar senha** e toque em **Definir senha e entrar**. Quem tem perfil Portaria cai direto na tela da portaria.',
        imagem: 'definir-senha',
        alt: 'Tela Definir senha com os campos Nova senha e Confirmar senha',
        celular: true
      },
      {
        texto:
          'Nas próximas vezes, entre em www.ingressoudi.com.br/login com o seu e-mail e a senha que você criou.'
      }
    ],
    problemas: [
      { pergunta: 'Apareceu "Este convite expirou ou já foi utilizado".', resposta: 'Peça ao responsável da casa um Novo link em Configurações, Usuários.' }
    ]
  },
  {
    slug: 'criar-evento',
    titulo: 'Como criar um evento',
    resumo: 'Dados do evento, imagem de divulgação e capacidade.',
    categoria: 'eventos',
    publico: ['produtor'],
    palavras: ['evento', 'criar', 'novo evento', 'data', 'horário', 'local', 'imagem', 'capa', 'banner', 'descrição', 'capacidade', 'rascunho'],
    antes: 'Tenha à mão uma imagem de divulgação na horizontal, de 1200 × 628 pixels (PNG, JPG ou WEBP, até 5 MB).',
    passos: [
      {
        texto: 'No menu, clique em **Eventos** e depois em **Criar evento**.',
        imagem: 'eventos-lista',
        alt: 'Tela Eventos com o botão Criar evento e os cards dos eventos'
      },
      {
        texto:
          'Preencha **Nome do evento**, **Data do evento**, **Horário de início**, **Local** e **Endereço**. O link do evento é criado sozinho a partir do nome; para encurtar, use **Editar URL**.',
        imagem: 'evento-informacoes',
        alt: 'Bloco Informações básicas do evento preenchido'
      },
      {
        texto: 'Envie a imagem de divulgação em **Escolher imagem** e escreva a descrição com atrações e regras.',
        imagem: 'evento-imagem',
        alt: 'Bloco Imagem do evento com o botão Escolher imagem'
      },
      {
        texto:
          'Informe a **Capacidade total** do local e os **Ingressos disponíveis na pré-venda**. Cada pedido pode ter até 10 ingressos.',
        imagem: 'evento-capacidade',
        alt: 'Bloco Capacidade com Capacidade total e Ingressos disponíveis na pré-venda'
      },
      {
        texto:
          'Em **Publicação e vendas**, deixe por enquanto **Rascunho** e vendas **Encerradas**, para ninguém comprar antes de você terminar. Clique em **Salvar evento**: o sistema leva você para a tela de lotes.',
        imagem: 'evento-publicacao',
        alt: 'Bloco Publicação e vendas com Rascunho e Encerradas selecionados'
      }
    ]
  },
  {
    slug: 'setores-e-lotes',
    titulo: 'Setores e lotes: preços do seu evento',
    resumo: 'Crie áreas como Pista e Camarote e as faixas de preço de cada uma.',
    categoria: 'eventos',
    publico: ['produtor'],
    palavras: ['lote', 'lotes', 'preço', 'valor', 'setor', 'setores', 'pista', 'camarote', 'área vip', 'virada de lote', 'esgotamento', 'ativar', 'encerrar'],
    passos: [
      {
        texto:
          'Na tela **Lotes** do evento você vê os setores, os lotes de cada setor e quantos ingressos foram vendidos.',
        imagem: 'lotes-tela',
        alt: 'Tela Lotes com os setores Pista e Camarote e seus lotes'
      },
      {
        texto:
          'Setor é cada área com preço próprio. Todo evento nasce com um setor chamado Ingresso. Para criar outro, digite o nome em **Novo setor** e clique em **Adicionar setor**. Use **Renomear** para trocar Ingresso por Pista, por exemplo. Se o evento tem uma área só, pule esta parte.',
        imagem: 'setores',
        alt: 'Card Setores com Pista, Camarote e o campo Novo setor'
      },
      {
        texto:
          'Clique em **Novo lote**, escolha o **Setor** e preencha **Nome do lote**, **Ordem**, **Quantidade** e **Preço**. Em **Tipo de ativação**: **Manual** (você ativa quando quiser), **Após esgotamento** (começa sozinho quando o lote anterior acabar) ou **Data e hora** (começa sozinho no horário escolhido). Clique em **Salvar lote**.',
        imagem: 'lote-novo',
        alt: 'Janela Novo lote com setor, nome, ordem, quantidade, preço e tipo de ativação'
      },
      {
        texto:
          'Um jeito comum: 1º lote manual e os seguintes em Após esgotamento. Para encerrar um lote antes de esgotar, use **Encerrar**; o sistema oferece ativar o próximo na mesma hora.'
      }
    ],
    problemas: [
      { pergunta: 'O botão Ativar lote não funciona.', resposta: 'O lote só pode ser ativado com as vendas do evento abertas. Veja "Publicar o evento e abrir as vendas".' },
      { pergunta: 'O cliente pode comprar Pista e Camarote no mesmo pedido?', resposta: 'Não. Cada pedido é de um setor só; ele faz um pedido para cada setor.' }
    ]
  },
  {
    slug: 'meia-entrada-e-taxa',
    titulo: 'Meia-entrada e taxa de serviço',
    resumo: 'Ative a meia-entrada e escolha quem paga a taxa por ingresso.',
    categoria: 'eventos',
    publico: ['produtor'],
    palavras: ['meia', 'meia-entrada', 'estudante', 'desconto', 'taxa', 'taxa de serviço', 'repassar', 'absorver', 'conveniência'],
    passos: [
      {
        texto:
          'Em **Eventos**, abra **Mais ações** no card do evento e clique em **Editar evento**. No card **Meia-entrada**, clique em **Ativar meia-entrada**. A meia custa metade do preço do lote, em todos os setores.',
        imagem: 'meia-entrada',
        alt: 'Card Meia-entrada com as opções Ativar meia-entrada e Sem meia-entrada'
      },
      {
        texto:
          'No card **Taxa de serviço**, escolha **Repassar ao comprador** (a taxa é somada ao ingresso) ou **Absorver a taxa** (o comprador paga só o ingresso e a taxa sai do valor que você recebe). Salve o evento.',
        imagem: 'taxa-servico',
        alt: 'Card Taxa de serviço com as opções Repassar ao comprador e Absorver a taxa'
      },
      {
        texto: 'Quem compra meia precisa apresentar na entrada um documento que comprove o direito. A portaria recebe esse aviso na hora da leitura.'
      }
    ]
  },
  {
    slug: 'publicar-e-abrir-vendas',
    titulo: 'Publicar o evento e abrir as vendas',
    resumo: 'Deixe o evento visível e comece a vender.',
    categoria: 'eventos',
    publico: ['produtor'],
    palavras: ['publicar', 'publicado', 'abrir vendas', 'vendas abertas', 'ativar lote', 'começar a vender', 'encerrar vendas', 'mais ações'],
    antes: 'A sua casa precisa estar aprovada e o Mercado Pago conectado.',
    passos: [
      {
        texto:
          'Em **Editar evento**, no bloco **Publicação e vendas**, escolha **Publicado** e vendas **Abertas**. Salve.',
        imagem: 'evento-publicado',
        alt: 'Bloco Publicação e vendas com Publicado e Abertas selecionados'
      },
      {
        texto:
          'Em **Eventos**, abra **Mais ações** no card do evento e clique em **Gerenciar lotes**. Clique em **Ativar lote** no 1º lote. Pronto: o evento já está vendendo.',
        imagem: 'eventos-mais-acoes',
        alt: 'Menu Mais ações do evento com Visualizar página pública, Copiar link, Ver dashboard, Gerenciar lotes, Lista VIP e Editar evento'
      },
      {
        texto:
          'As vendas online continuam abertas até 3 horas depois do horário de início e fecham sozinhas. A venda em dinheiro no painel continua disponível na porta.'
      }
    ]
  },
  {
    slug: 'divulgar-links',
    titulo: 'Como divulgar seus links de venda',
    resumo: 'O link de cada evento e a página com toda a agenda da sua casa.',
    categoria: 'eventos',
    publico: ['produtor'],
    palavras: ['link', 'divulgar', 'compartilhar', 'instagram', 'whatsapp', 'bio', 'página', 'vitrine', 'agenda', 'cor', 'copiar link'],
    passos: [
      {
        texto:
          'O link de venda de cada evento fica no card do evento, em **Eventos** (**Mais ações**, **Copiar link**), e no card **Próximo evento** do **Dashboard**, com o botão **Copiar**.',
        imagem: 'painel-link-venda',
        alt: 'Card Próximo evento com o Link de venda e o botão Copiar'
      },
      {
        texto:
          'A **Página com todos os seus eventos** mostra a agenda da casa, mês a mês. Ela fica no topo da tela **Eventos**, com **Copiar** e **Abrir**. Coloque esse link na bio do Instagram.',
        imagem: 'eventos-link-vitrine',
        alt: 'Campo Página com todos os seus eventos com os botões Abrir e Copiar'
      },
      {
        texto: 'É assim que o seu público vê a página da casa no celular.',
        imagem: 'vitrine',
        alt: 'Página pública da casa no celular com a agenda de eventos',
        celular: true
      },
      {
        texto:
          'Em **Configurações**, **Sua página de eventos**, você escolhe a **Cor de destaque** usada no topo, nos preços e no botão de comprar.',
        imagem: 'pagina-publica-cor',
        alt: 'Card Cor de destaque com a prévia do botão Comprar ingresso'
      }
    ]
  },
  {
    slug: 'validar-ingressos',
    titulo: 'Portaria: como validar os ingressos',
    resumo: 'Leia o QR Code com a câmera do celular ou busque pelo nome.',
    categoria: 'dia-do-evento',
    publico: ['equipe', 'produtor'],
    palavras: ['portaria', 'porteiro', 'validar', 'ler', 'qr code', 'câmera', 'entrada', 'liberada', 'já utilizado', 'buscar por nome', 'check-in', 'instalar app', 'aplicativo'],
    antes:
      'Cada porteiro entra com o próprio login. Dica: no menu, toque em Instalar app para deixar o Ingressoudi na tela inicial do celular (no iPhone: abra no Safari, toque em Compartilhar e em Adicionar à Tela de Início). Teste a câmera antes de abrir a porta.',
    passos: [
      {
        texto: 'Abra **Portaria** e escolha o evento em **Evento em operação**.',
        imagem: 'portaria-evento',
        alt: 'Tela Portaria com o evento selecionado e as abas QR Code e Buscar por nome',
        celular: true
      },
      {
        texto:
          'Na aba **QR Code**, toque em **Ativar câmera** e permita o uso da câmera. Aponte para o QR Code do ingresso. Verde, **Entrada liberada**: pode entrar. O nome do participante aparece na tela.',
        imagem: 'portaria-liberada',
        alt: 'Resultado Entrada liberada com o nome do participante',
        celular: true
      },
      {
        texto:
          'Se o mesmo ingresso for lido de novo, aparece **Ingresso já utilizado** com o horário da primeira entrada. Não libere. A leitura continua sozinha para o próximo.',
        imagem: 'portaria-ja-utilizado',
        alt: 'Resultado Ingresso já utilizado com o horário da entrada',
        celular: true
      },
      {
        texto:
          'Cliente sem o celular? Use a aba **Buscar por nome**: digite o nome, toque em **Buscar** e depois em **Registrar**. Se o sistema pedir, toque em **Confirmar entrada**.',
        imagem: 'portaria-busca',
        alt: 'Busca por nome com o resultado e o botão Registrar',
        celular: true
      }
    ],
    problemas: [
      { pergunta: 'Apareceu "Meia-entrada · conferir documento".', resposta: 'Peça o documento que comprova o direito à meia antes de liberar.' },
      { pergunta: 'Apareceu "Evento incorreto".', resposta: 'O ingresso é de outro evento. Confira se o evento certo está selecionado.' },
      { pergunta: 'Apareceu "Ingresso não encontrado" ou "Ingresso cancelado".', resposta: 'Não libere e chame o responsável pelo evento.' },
      { pergunta: 'A câmera não abre.', resposta: 'O navegador bloqueou a câmera. Libere a permissão nas configurações do site e tente de novo.' }
    ]
  },
  {
    slug: 'venda-na-porta',
    titulo: 'Venda na porta em dinheiro',
    resumo: 'Registre vendas em dinheiro no painel; o ingresso sai com QR Code e sem taxa.',
    categoria: 'dia-do-evento',
    publico: ['produtor'],
    palavras: ['venda manual', 'dinheiro', 'porta', 'bilheteria', 'nova venda', 'espécie', 'sem taxa'],
    passos: [
      {
        texto:
          'Um Administrador abre **Pedidos** e clica em **Nova venda manual**. Escolha o **Evento**, o **Lote** e preencha o nome do comprador e dos participantes.',
        imagem: 'venda-manual',
        alt: 'Tela Nova venda manual com evento, lote e comprador'
      },
      {
        texto:
          'Confira o resumo e clique em **Confirmar venda**. A venda entra como paga em dinheiro, o ingresso sai com QR Code e não tem taxa de serviço. Funciona mesmo depois do início do evento.'
      }
    ]
  },
  {
    slug: 'lista-vip',
    titulo: 'Lista VIP: convidados e cortesias',
    resumo: 'Cadastre convidados sem pagamento e libere a entrada pelo nome.',
    categoria: 'dia-do-evento',
    publico: ['produtor', 'equipe'],
    palavras: ['lista vip', 'vip', 'convidado', 'convidados', 'cortesia', 'lista', 'nome na lista', 'grátis'],
    antes: 'A Lista VIP é liberada por casa. Se ela não aparece no seu menu, peça a liberação à equipe Ingressoudi.',
    passos: [
      {
        texto:
          'Em **Eventos**, abra **Mais ações** e clique em **Lista VIP** (ou use **Lista VIP** no menu). Clique em **Adicionar à lista VIP** para um nome, ou **Adicionar vários** para colar uma lista.',
        imagem: 'lista-vip',
        alt: 'Tela Lista VIP com os convidados do evento'
      },
      {
        texto:
          'Na portaria, os convidados aparecem na aba **Buscar por nome** com o selo VIP. Toque em **Registrar** para liberar a entrada.',
        imagem: 'portaria-busca-vip',
        alt: 'Busca por nome na portaria com um convidado da Lista VIP',
        celular: true
      }
    ]
  },
  {
    slug: 'acompanhar-vendas',
    titulo: 'Acompanhar vendas, entradas e valores',
    resumo: 'Onde ver quanto vendeu, quem entrou e quanto recebeu.',
    categoria: 'acompanhar',
    publico: ['produtor'],
    palavras: ['dashboard', 'relatório', 'relatórios', 'vendas', 'pedidos', 'financeiro', 'faturamento', 'entradas', 'quanto vendi', 'reserva', 'expirado', 'pago'],
    antes:
      'O dinheiro das vendas online já cai na sua conta do Mercado Pago, com a taxa de serviço descontada. Não há repasse para pedir.',
    passos: [
      {
        texto: 'O **Dashboard** mostra o resumo da casa: vendidos, quem já entrou, faturamento, o próximo evento e os últimos pedidos.',
        imagem: 'painel-visao-geral',
        alt: 'Dashboard com os números de vendas e entradas'
      },
      {
        texto:
          'Para um evento só, abra **Mais ações** e **Ver dashboard**: vendas por setor, lote atual, reservas em aberto e entradas por hora.',
        imagem: 'evento-dashboard',
        alt: 'Dashboard do evento com vendas por setor'
      },
      {
        texto:
          'Em **Pedidos** ficam todas as compras. **Reservado** é quem ainda não pagou; depois de 30 minutos sem pagamento a reserva expira e os ingressos voltam para a venda.',
        imagem: 'pedidos',
        alt: 'Tela Pedidos com a lista de compras e os filtros'
      },
      {
        texto: 'Em **Entradas** você vê quem entrou, a que horas, por qual forma (QR Code ou nome) e qual porteiro registrou.',
        imagem: 'entradas',
        alt: 'Tela Entradas com a lista de entradas registradas'
      },
      {
        texto: 'Em **Financeiro** estão os pagamentos aprovados, o valor líquido e os reembolsos.',
        imagem: 'financeiro',
        alt: 'Tela Financeiro com os pagamentos aprovados'
      }
    ]
  },
  {
    slug: 'como-comprar',
    titulo: 'Como comprar seu ingresso',
    resumo: 'Compra pelo celular, sem aplicativo e sem criar conta. O ingresso chega na hora.',
    categoria: 'comprador',
    publico: ['comprador'],
    palavras: ['comprar', 'compra', 'ingresso', 'pix', 'cartão', 'crédito', 'parcelar', 'pagar', 'pagamento', 'paguei', 'qr code', 'reserva', 'meia', 'não confirmou', 'não caiu', 'expirou'],
    passos: [
      {
        texto: 'Abra o link do evento e escolha o setor. Toque em **Comprar**.',
        imagem: 'compra-setores',
        alt: 'Página do evento com os setores e os botões de compra',
        celular: true
      },
      {
        texto: 'Escolha quantos ingressos quer e toque em **Continuar**.',
        imagem: 'compra-1-quantidade',
        alt: 'Etapa Quantidade com os botões de mais e menos',
        celular: true
      },
      {
        texto:
          'Coloque o nome de quem vai usar cada ingresso e, se houver meia, escolha **Inteira** ou **Meia-entrada** para cada um.',
        imagem: 'compra-2-participantes',
        alt: 'Etapa Participantes com o nome de cada ingresso',
        celular: true
      },
      {
        texto: 'Informe **Nome completo**, **Telefone** e **E-mail**. Eles servem para recuperar os ingressos depois.',
        imagem: 'compra-3-comprador',
        alt: 'Etapa Comprador com nome, telefone e e-mail',
        celular: true
      },
      {
        texto: 'Confira o resumo e toque em **Confirmar pedido**.',
        imagem: 'compra-4-revisao',
        alt: 'Etapa Revisão com evento, participantes e valores',
        celular: true
      },
      {
        texto: 'Seus ingressos ficam reservados por 30 minutos. Toque em **Continuar para pagamento**.',
        imagem: 'compra-5-reserva',
        alt: 'Aviso Reserva criada com o código do pedido',
        celular: true
      },
      {
        texto: 'Escolha **Pix** (aprovação na hora) ou **Cartão** (crédito em até 3x, quando a casa aceita).',
        imagem: 'pagamento-formas',
        alt: 'Opções de pagamento Pix e Cartão',
        celular: true
      },
      {
        texto:
          'No Pix, escaneie o QR Code no app do banco ou toque em **Copiar código Pix** e use o Pix copia e cola. No cartão, preencha os dados e escolha as parcelas; alguns bancos pedem uma confirmação no app.',
        imagem: 'pagamento-pix',
        alt: 'Pagamento via Pix com QR Code e o botão Copiar código Pix',
        celular: true
      },
      {
        texto:
          'Quando o pagamento é aprovado, a tela mostra **Seus ingressos**, um para cada participante, com QR Code. Toque em **Enviar para meu WhatsApp** para guardar o link.',
        imagem: 'ingressos-comprador',
        alt: 'Tela Seus ingressos com o botão Enviar para meu WhatsApp e o ingresso com QR Code',
        celular: true
      }
    ],
    problemas: [
      { pergunta: 'Passaram os 30 minutos e eu não paguei.', resposta: 'A reserva expira e os ingressos voltam para a venda. É só fazer o pedido de novo.' },
      { pergunta: 'Paguei e a tela não mudou.', resposta: 'A página confere sozinha a cada poucos segundos. Se demorar, toque em Atualizar status.' },
      { pergunta: 'Comprei meia-entrada.', resposta: 'Leve um documento que comprove o direito à meia. Ele será pedido na entrada.' }
    ]
  },
  {
    slug: 'encontrar-ingressos',
    titulo: 'Onde encontrar meus ingressos',
    resumo: 'Ache os ingressos no mesmo celular ou recupere em outro aparelho.',
    categoria: 'comprador',
    publico: ['comprador'],
    palavras: ['meus ingressos', 'perdi', 'recuperar', 'achar', 'onde está', 'qr code', 'troquei de celular', 'compartilhar', 'não recebi'],
    passos: [
      {
        texto:
          'No topo do site, toque em **Meus ingressos**. Os pedidos feitos neste aparelho aparecem em **Salvos neste aparelho**.',
        imagem: 'recuperar-ingressos',
        alt: 'Tela Meus ingressos com os pedidos salvos e a busca por telefone e e-mail',
        celular: true
      },
      {
        texto:
          'Comprou em outro aparelho? Na mesma tela, informe o **telefone** e o **e-mail** usados na compra e toque em **Buscar meus ingressos**. Também dá para buscar pelo código do pedido.'
      },
      {
        texto:
          'Na entrada, apresente o QR Code de cada ingresso. Vai com amigos? Use **Compartilhar ingresso** para mandar o ingresso de cada um.',
        imagem: 'ingresso-qr',
        alt: 'Ingresso com QR Code e o botão Compartilhar ingresso',
        celular: true
      }
    ]
  }
]

/** Remove acentos e caixa para comparar textos. */
export function normalizarTextoAjuda(texto: string): string {
  return String(texto ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

/** Remove a marcacao de negrito (**texto**). */
export function textoSemMarcacao(texto: string): string {
  return String(texto ?? '').replace(/\*\*/g, '')
}

/** Divide um texto com **negrito** em partes para renderizar sem v-html. */
export function partesTexto(texto: string): { texto: string; negrito: boolean }[] {
  return String(texto ?? '')
    .split(/(\*\*[^*]+\*\*)/g)
    .filter((parte) => parte !== '')
    .map((parte) =>
      parte.startsWith('**') && parte.endsWith('**') && parte.length > 4
        ? { texto: parte.slice(2, -2), negrito: true }
        : { texto: parte, negrito: false }
    )
}

export function obterArtigoAjuda(slug: string): ArtigoAjuda | null {
  return ARTIGOS_AJUDA.find((artigo) => artigo.slug === slug) ?? null
}

export function artigosDaCategoria(categoria: CategoriaAjudaId): ArtigoAjuda[] {
  return ARTIGOS_AJUDA.filter((artigo) => artigo.categoria === categoria)
}

const PALAVRAS_VAZIAS = new Set([
  'a', 'o', 'as', 'os', 'de', 'do', 'da', 'dos', 'das', 'e', 'em', 'no', 'na', 'nos', 'nas', 'um', 'uma',
  'para', 'pra', 'por', 'com', 'que', 'se', 'eu', 'meu', 'minha', 'meus', 'minhas', 'como', 'nao', 'ja', 'ou', 'ao'
])

/** Termos uteis da consulta: sem acento, sem palavras vazias. */
export function termosBuscaAjuda(consulta: string): string[] {
  return normalizarTextoAjuda(consulta)
    .split(' ')
    .filter((termo) => termo.length >= 2 && !PALAVRAS_VAZIAS.has(termo))
}

/** Casa a palavra inteira ou o comeco dela (confirmou -> confirmacao). */
function contemTermo(texto: string, termo: string): boolean {
  if (texto.includes(termo)) return true
  if (termo.length < 6) return false
  return texto.includes(termo.slice(0, Math.max(5, termo.length - 3)))
}

/**
 * Busca por palavras. Titulo e palavras-chave pesam mais que o texto dos passos;
 * artigos que casam mais termos vem primeiro.
 */
export function buscarArtigosAjuda(consulta: string): ArtigoAjuda[] {
  const termos = termosBuscaAjuda(consulta)
  if (termos.length === 0) return []

  const pontuados = ARTIGOS_AJUDA.map((artigo, ordem) => {
    const titulo = normalizarTextoAjuda(artigo.titulo)
    const chaves = normalizarTextoAjuda([artigo.resumo, ...artigo.palavras].join(' '))
    const corpo = normalizarTextoAjuda(
      [
        artigo.antes ?? '',
        ...artigo.passos.map((passo) => textoSemMarcacao(passo.texto)),
        ...(artigo.problemas ?? []).flatMap((p) => [p.pergunta, p.resposta])
      ].join(' ')
    )
    let pontos = 0
    let casados = 0
    for (const termo of termos) {
      if (contemTermo(titulo, termo)) pontos += 5
      else if (contemTermo(chaves, termo)) pontos += 3
      else if (contemTermo(corpo, termo)) pontos += 1
      else continue
      casados += 1
    }
    return { artigo, pontos, casados, ordem }
  })

  return pontuados
    .filter((item) => item.casados > 0)
    .sort((a, b) => b.casados - a.casados || b.pontos - a.pontos || a.ordem - b.ordem)
    .map((item) => item.artigo)
}

/** Outros artigos da mesma categoria, para o fim de cada artigo. */
export function artigosRelacionados(slug: string, limite = 3): ArtigoAjuda[] {
  const artigo = obterArtigoAjuda(slug)
  if (!artigo) return []
  const mesmos = ARTIGOS_AJUDA.filter((a) => a.slug !== slug && a.categoria === artigo.categoria)
  const outros = ARTIGOS_AJUDA.filter(
    (a) => a.slug !== slug && a.categoria !== artigo.categoria && a.publico.some((p) => artigo.publico.includes(p))
  )
  return [...mesmos, ...outros].slice(0, limite)
}

export function caminhoArtigoAjuda(slug: string): string {
  return `/ajuda/${slug}`
}

export function imagemAjuda(nome: string): string {
  return `/ajuda/${nome}.webp`
}
