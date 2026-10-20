/** Liga o aviso push neste aparelho (RPC segura, somente super admin). */
export async function registrarAssinaturaPush(assinatura: PushSubscription): Promise<void> {
  const client = useSupabaseClient()
  const json = assinatura.toJSON()
  const { error } = await client.rpc('registrar_push_assinatura', {
    p_endpoint: assinatura.endpoint,
    p_p256dh: json.keys?.p256dh ?? '',
    p_auth: json.keys?.auth ?? '',
    p_user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null
  })
  if (error) throw new Error('Não foi possível ativar as notificações neste aparelho.')
}

/** Desliga o aviso push deste aparelho. */
export async function removerAssinaturaPush(endpoint: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('remover_push_assinatura', { p_endpoint: endpoint })
  if (error) throw new Error('Não foi possível desativar as notificações neste aparelho.')
}

/** Avisa os super admins que uma casa nova foi criada (falha silenciosa). */
export async function avisarNovaOrganizacao(organizacaoId: string): Promise<void> {
  try {
    await $fetch('/api/notificacoes/nova-organizacao', {
      method: 'POST',
      body: { organizacaoId },
      timeout: 5000
    })
  } catch {
    // O aviso e um extra: o cadastro segue mesmo se ele falhar.
  }
}
