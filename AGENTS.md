# Contexto do projeto: Ingressoudi, a plataforma multiempresa criada a partir do GZ1 Ingresso

> Documento de contexto para o Claude Code. Resume as decisões de negócio e o plano técnico definidos em conversa com o dono do produto.
> **Antes de alterar qualquer coisa, leia o código, confirme o entendimento e proponha um plano.**

---

## 1. O que é o produto hoje

O **GZ1 Ingresso** é um app de venda de ingressos com controle de portaria. Foi criado pelo dono para os próprios eventos de **pagode**: casa pequena, cerca de **250 ingressos por evento**, ingresso médio de **R$ 25**.

Ele substituiu o processo manual: Pix no WhatsApp → comprovante → nome numa lista → lista na portaria.

**Stack:** Nuxt 4, Vue 3, TypeScript, Tailwind, Supabase (Postgres, Auth, Storage, RPCs), Vercel e Mercado Pago (Pix).

**O que já existe e funciona bem (preservar):**

- **Eventos**
  - Slug, capa, data, local e capacidade.
  - Status operacional: `AGENDADO`, `EM_ANDAMENTO`, `REALIZADO`, `CANCELADO`. O status de vendas é separado.
- **Lotes**
  - Um lote vigente por vez.
  - Ativação manual, por esgotamento ou por data/hora.
  - Preço histórico preservado no pedido e no ingresso.
- **Checkout público**
  - De 1 a 10 ingressos, com nome e telefone.
  - Reserva com expiração.
  - Token de checkout.
  - Reconciliação quando o pagamento chega no limite do prazo.
- **Pagamento**
  - Pix via Mercado Pago, hoje numa **conta única**.
  - Venda manual em dinheiro pelo backoffice.
- **Ingressos individuais**
  - QR com token único.
  - Status `VALIDO` / `UTILIZADO`.
  - Validação atômica no backend (`JA_UTILIZADO`).
  - Recuperação pelo comprador (código do pedido + telefone).
  - Compartilhamento por token.
- **Portaria (mobile-first)**
  - Leitura de QR com cooldown.
  - Busca por nome tolerante a acentos, com tratamento de homônimos.
  - Tratamento de rede instável. **Sem fila offline**: a liberação exige o backend online.
- **Lista VIP**
  - Separada das vendas: não gera pedido, pagamento nem ingresso.
- **Perfis**
  - `ADMINISTRADOR` e `PORTARIA`, validados também nas rotas e RPCs.
  - Convite por e-mail via Supabase Auth.
- **Segurança**
  - RLS, locks na reserva, auditoria, service role só no servidor e mensagens sanitizadas.

---

## 2. Objetivo

Criar o **Ingressoudi**, um **produto novo e independente**, a partir de uma cópia do código do GZ1 Ingresso.

- O GZ1 Ingresso **continua existindo como está**, com o próprio banco e a própria operação. Ele **não** será migrado para o Ingressoudi nem desligado.
- O Ingressoudi tem **banco de dados novo, vazio, desde o início**.

O Ingressoudi é uma **plataforma multiempresa (multi-tenant)**: vários produtores e casas de show usando o mesmo sistema, cada um com seus eventos, equipe, Mercado Pago e dados **totalmente isolados**.

Nome comercial em avaliação: **"Entrô"**. Ainda não está confirmado, por uma possível semelhança com a marca "EntrouPIX" no INPI. Por isso, **não deixe o nome da marca fixo no código**: use uma configuração central (nome, logo, cores).

---

## 3. Repositório (decidido)

- Repositório do Ingressoudi: `https://github.com/euthiagosilveira-hue/ingressoudi.git`.
- O código foi **copiado** do GZ1 **sem o histórico** do git. O Ingressoudi começa um histórico próprio e não tem remote apontando para o GZ1.
- Branch principal: `main`. O trabalho grande é feito na branch `feature/multiempresa`.
- O **repositório do GZ1 nunca é alterado**.

**Infraestrutura separada (nunca reaproveitar a do original):**

- **Supabase:** um projeto **novo e vazio**.
  - Criado **a partir das migrations**, não de cópia do banco.
  - **Nenhum dado do GZ1 é copiado.** Usar seeds fictícios para desenvolvimento.
  - Rodar `supabase link --project-ref <NOVO>` antes de qualquer `db push`.
- **Mercado Pago:** uma aplicação nova, configurada como **marketplace com OAuth**.
- **Vercel:** um projeto novo, com variáveis de ambiente novas.
- **Webhook do Pix:** deve apontar para a URL do app novo.
- **Arquivos `.env`:** nunca versionar.

---

## 4. Modelo de negócio (direção recomendada, a confirmar com o dono)

- **Base:** uma **taxa de serviço fixa por ingresso**, sugerida em **R$ 2,00**. O produtor escolhe, por evento:
  - **repassar** a taxa ao comprador (o cliente paga ingresso + taxa); ou
  - **absorver** a taxa (o cliente paga só o ingresso e a taxa sai do valor do produtor).
- A taxa é cobrada automaticamente pela **`marketplace_fee` do Mercado Pago**. O dinheiro do ingresso cai direto na conta do produtor e a plataforma **nunca guarda dinheiro de terceiros**.
- **Plano Pro**, mais para frente: mensalidade + taxa menor, para casas com muitos eventos.
- A mensalidade pura foi descartada como modelo principal, porque é uma barreira para o produtor pequeno com eventos irregulares.

**Implicação técnica:** o valor da taxa e o modo (repassa/absorve) precisam ficar **gravados no pedido**, do mesmo jeito que o preço histórico. Assim, mudar a configuração depois não altera o que já foi vendido.

---

## 5. Plano técnico da versão multiempresa (em ordem)

### Fase 1: Base multi-tenant (a mais crítica)

1. **`organizations`**: id, nome, slug único, status, configurações de taxa, timestamps.
2. **`organization_members`**: `organization_id`, `user_id`, `role` (`ADMINISTRADOR` | `PORTARIA`), ativo. Os perfis passam a valer **por organização**. Um usuário pode pertencer a mais de uma.
3. **`organization_id`** em eventos e também, de forma desnormalizada, em lotes, pedidos, ingressos, pagamentos, lista VIP e entradas. Isso simplifica e acelera as políticas de RLS.
4. **Funções auxiliares** como `is_org_member(org_id)` e `has_org_role(org_id, role)`, com `SECURITY DEFINER` e `search_path` fixo.
5. **Reescrever todas as políticas de RLS e as RPCs.** A pergunta deixa de ser "é admin?" e passa a ser "é admin **desta** organização?". As RPCs da portaria precisam validar que o ingresso pertence a um evento da organização do operador.
6. **Papel de super-admin da plataforma**, para suporte e métricas gerais.
7. **Testes de isolamento:** um membro da organização A nunca lê nem altera nada da organização B, nem via RPC nem digitando a URL direto. Isso é **critério de aceite**.

### Fase 2: Pagamento por organização

8. **OAuth do Mercado Pago por organização.** Guardar `access_token`, `refresh_token`, `user_id` do MP e validade, **criptografados** (por exemplo, com o Supabase Vault). Implementar a renovação automática do token.
9. **Checkout:** criar o pagamento Pix com o token **da organização dona do evento** e com a `marketplace_fee`.
10. **Webhook:** identificar a organização e conciliar o pedido. Revisar a idempotência.
11. **Taxa de serviço no checkout:** configuração repassa/absorve por evento, com o valor e o modo gravados no pedido.

### Fase 3: Produto para terceiros

12. **URL pública** `/{org-slug}/{evento-slug}`, com o slug do evento único **por organização**.
13. **Cadastro self-service do produtor:** criar conta → criar organização → conectar o Mercado Pago → publicar o primeiro evento.
14. **Configuração central de marca** (nome, logo, cores), sem o nome fixo no código.
15. **Termos de uso, política de reembolso/cancelamento e aviso de privacidade** (LGPD).

### Fase 4: Diferenciais (depois)

- **Promoters/vendedores:** link rastreável, comissão e ranking.
- **Cupons** e **meia-entrada** (Lei 12.933/2013).
- **Lista VIP feita pelo promoter**, com limite de nomes.
- **Base de clientes por organização**, para remarketing.
- **Modo offline opcional na portaria** (lista baixada antes do evento), para o plano Pro.

---

## 6. Regras para o trabalho

- **Nunca** fazer push, migration ou deploy no repositório, no Supabase ou no Mercado Pago do **GZ1**.
- Manter as garantias herdadas do GZ1:
  - atomicidade da validação na portaria;
  - preço histórico;
  - reserva com expiração;
  - VIP separado das vendas;
  - mensagens sanitizadas.
- Mudanças no banco **sempre via migrations versionadas**.
- Para cada fase:
  - propor o plano antes de implementar;
  - fazer commits pequenos;
  - escrever testes de RLS e isolamento.
- Comunicação com o dono **em português**.

---

## 7. Primeira tarefa sugerida

1. Ler o repositório e mapear tabelas, RPCs, políticas de RLS e as rotas de admin e portaria.
2. Listar tudo o que depende da suposição de "organizador único".
3. Propor as migrations da **Fase 1** (passos 1 a 5) e o plano de testes de isolamento, **antes de escrever código**.
