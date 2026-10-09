---
applyTo: '**'
---

# Guia de Projeto — Supabase (integração + padrões de código)

⚠️ **Atenção**
Este documento é um **guia baseado em boas práticas e na documentação oficial** do Supabase.
**Sempre siga as orientações do desenvolvedor responsável pelo projeto.**
Não é uma regra imutável — serve como referência para manter consistência, segurança e escalabilidade.

---

## 1) Instalação

```bash
npx nuxt@latest module add supabase
```

Isso adiciona o módulo `@nuxtjs/supabase` e instala a dependência.

- [Passo a passo oficial](https://supabase.com/docs/guides/getting-started/tutorials/with-nuxt)
- Módulo: `@nuxtjs/supabase` (usa `@supabase/supabase-js` internamente).

> ⚠️ Nunca exponha a `SUPABASE_SERVICE_ROLE_KEY` no cliente. Use apenas a `SUPABASE_KEY` (anon public).

---

## 2) Variáveis de ambiente (`.env`)

Adicione ao `.env` local e configure no painel do Supabase / plataforma de deploy:

```
NUXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NUXT_PUBLIC_SUPABASE_KEY=<chave anon public>
SUPABASE_SERVICE_ROLE_KEY=<chave service role — somente servidor>
```

> `.env` **nunca** deve ser versionado. Mantenha apenas `.env.example` no repositório.

---

## 3) Configuração no `nuxt.config.ts`

```ts
export default defineNuxtConfig({
  modules: ['@nuxtjs/supabase'],
  supabase: {
    redirect: true,           // redireciona para /login quando não autenticado (opcional)
    cookieOptions: {
      sameSite: 'lax',
      secure: true
    }
  }
})
```

---

## 4) Regras de acesso aos dados — **Sempre RLS**

1. **Todo acesso passa pelo `server/api`** (Nitro) ou por composables que usam o client Supabase.

2. **Nunca** fazer queries pesadas ou com regras sensíveis direto no `useAsyncData` da página sem validar permissão.

3. **RLS (Row Level Security)** é a camada final de segurança. O cliente (anon key) só enxerga o que as policies permitem.
   - Configure policies para cada tabela (`select`, `insert`, `update`, `delete`).
   - Use `auth.uid()` nas policies para escopo de usuário.

4. **A service role key** fica somente no servidor (`server/api`/`server/routes`) para operações administrativas. **Nunca importar no cliente.**

5. **Sempre tipar o retorno da API.** Evite `any`.

---

## 5) Padrão de camadas (alinhado ao Nuxt)

- **UI (`components`)** → consome **composables** → acessam **`server/api`** ou **client Supabase**.
- Componentes **não** chamam o Supabase diretamente.
- Lógica de negócio vive em **composables** (`useAuth`, `useProfile`, `useEvents`, …).

---

## 6) Autenticação (Auth)

- O módulo injeta `useSupabaseUser()` (usuário reativo) e `useSupabaseClient()`.

- **Login / SignUp / Logout** → em composable `useAuth.ts`:

```ts
export function useAuth() {
  const client = useSupabaseClient()
  const user = useSupabaseUser()

  async function signIn(email: string, password: string) {
    const { error } = await client.auth.signInWithPassword({ email, password })
    if (error) throw new Error(error.message)
  }

  async function signUp(email: string, password: string) {
    const { error } = await client.auth.signUp({ email, password })
    if (error) throw new Error(error.message)
  }

  async function signOut() {
    await client.auth.signOut()
  }

  return { user, signIn, signUp, signOut }
}
```

- **Proteção de rotas** → usar middleware `app/middleware/` (ex.: `auth.ts`):

```ts
export default defineNuxtRouteMiddleware((to) => {
  const user = useSupabaseUser()
  if (!user.value) {
    return navigateTo('/login')
  }
})
```

> Para definir o middleware global ou em páginas específicas, usar `definePageMeta({ middleware: 'auth' })`.

---

## 7) Acesso a dados no servidor (`server/api`)

**Nunca** consultar o banco direto do cliente com a service role.

- **Com cliente do usuário** (`@nuxtjs/supabase` provê `serverSupabaseClient`):

```ts
// server/api/events.get.ts
export default defineEventHandler(async (event) => {
  const supabase = await serverSupabaseClient(event)
  const { data, error } = await supabase.from('events').select('*')
  if (error) throw createError({ statusCode: 500, message: error.message })
  return data
})
```

- **Operações administrativas (service role)**:

```ts
// server/api/admin/reports.get.ts
export default defineEventHandler(async (event) => {
  const supabase = await serverSupabaseUser(event)
  // validar permissão de admin antes de usar service role
  const admin = serverSupabaseServiceRole(event)
  const { data } = await admin.from('reports').select('*')
  return data
})
```

---

## 8) Tipos (contratos de dados)

- Gerar tipos do banco com o Supabase CLI:

```bash
npx supabase gen types typescript --project-id <ref> --schema public > shared/types/database.ts
```

- Criar DTOs/entidades em `shared/types` (ou `app/types` em projetos pequenos):

```ts
// shared/types/event.ts
export interface EventDTO {
  id: string
  title: string
  description: string | null
  start_at: string
  user_id: string
  created_at: string
}
```

> Certifique-se de que a comparação de tipos com a resposta do Supabase seja consistente (tipos gerados vs. DTOs).

---

## 9) Nomenclatura (Superbase → Nuxt)

- **Composables** → `use` + PascalCase → `useAuth.ts`, `useEvents.ts`
- **Server API** → arquivo com sufixo de método (`[]`) → `events.get.ts`, `events.post.ts`
- **Tipos/DTOs** → PascalCase → `EventDTO.ts`, `UserDTO.ts`
- **Components** → PascalCase → `EventCard.vue`
- **Páginas** → minúsculas, sem traços → `login.vue`, `events.vue`

---

## 10) Boas práticas de segurança

1. **RLS ativa** em todas as tabelas. Por padrão, políticas permissivas são desencorajadas.
2. **Service role key** apenas no servidor.
3. **CORS / redirect URLs** configurados no painel do Supabase para o domínio em produção.
4. **Nunca** logar chaves ou tokens no console.
5. **Validar permissões** (`isAdmin`, `isOwner`, …) em `server/api`, nunca confiar só no cliente.
6. **Migrações** versionadas (arquivos `.sql`) e aplicadas de forma controlada — não editar o schema direto no painel em produção.

---

## 11) Referência

- [Documentação Supabase (Nuxt)](https://supabase.com/docs/guides/getting-started/tutorials/with-nuxt)
- [Módulo @nuxtjs/supabase](https://supabase.com/docs/guides/getting-started/quickstarts/nuxtjs)
- [Auth no Nuxt](https://supabase.com/docs/guides/auth)
- [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Geração de tipos](https://supabase.com/docs/guides/api/rest/generating-types)
