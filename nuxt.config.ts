// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },
  modules: ['@nuxtjs/supabase', '@nuxtjs/tailwindcss'],
  runtimeConfig: {
    // Somente backend. Nunca expor em public.
    // Legado (conta unica do GZ1). Nao e usado pelo Ingressoudi: cada organizacao
    // conecta a propria conta via OAuth.
    mercadoPagoAccessToken: process.env.MERCADO_PAGO_ACCESS_TOKEN || '',
    // Aplicacao marketplace do Ingressoudi (OAuth).
    mercadoPagoClientId: process.env.MERCADO_PAGO_CLIENT_ID || '',
    mercadoPagoClientSecret: process.env.MERCADO_PAGO_CLIENT_SECRET || '',
    // Chave para cifrar os tokens das organizacoes (32+ caracteres aleatorios).
    mercadoPagoTokenKey: process.env.MERCADO_PAGO_TOKEN_KEY || '',
    // Somente testes: pede token de teste no OAuth (test_token=true). Default false.
    mercadoPagoOauthTestToken: process.env.MERCADO_PAGO_OAUTH_TEST_TOKEN || 'false',
    mercadoPagoWebhookSecret: process.env.MERCADO_PAGO_WEBHOOK_SECRET || '',
    // Somente testes: auto-aprovacao Pix (first_name=APRO). Default false.
    mercadoPagoTestAutoApprovePix: process.env.MERCADO_PAGO_TEST_AUTO_APPROVE_PIX || 'false',
    public: {
      // URL publica canonica da aplicacao (usada em redirects de Auth, ex.: convite).
      siteUrl: process.env.NUXT_PUBLIC_SITE_URL || ''
    }
  },
  supabase: {
    // Sem tela /login ainda: não redirecionar usuários não autenticados.
    redirect: false,
    // Types do banco serão gerados depois que o schema existir.
    types: false
  }
})
