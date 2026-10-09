import type { SharedTicket } from '~/types/compartilhamento'

interface SharedRpcRow {
  ingresso_id: string
  codigo: string
  participante_nome: string
  status: string
  utilizado_em: string | null
  entrada_em: string | null
  evento_nome: string
  evento_inicio_em: string | null
  evento_local: string | null
  evento_endereco: string | null
}

/** Cria (ou renova) o link de compartilhamento de um ingresso (backend). */
export async function criarCompartilhamento(input: {
  ingressoId: string
  checkoutToken?: string | null
  recoveryToken?: string | null
}): Promise<string> {
  const resposta = await $fetch<{ shareUrl?: string; error?: string }>('/api/tickets/share', {
    method: 'POST',
    body: {
      ingressoId: input.ingressoId,
      checkoutToken: input.checkoutToken ?? undefined,
      recoveryToken: input.recoveryToken ?? undefined
    }
  })
  if (!resposta?.shareUrl) {
    throw new Error('Não foi possível gerar o link de compartilhamento.')
  }
  return resposta.shareUrl
}

/** Dados publicos do ingresso compartilhado (sem qr_token, sem dados do comprador). */
export async function obterCompartilhamento(token: string): Promise<SharedTicket | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_compartilhamento_ingresso', { p_token: token })
  if (error) {
    throw new Error('Não foi possível carregar o ingresso.')
  }
  if (!data) return null

  const row = data as SharedRpcRow
  return {
    ingressoId: row.ingresso_id,
    codigo: row.codigo,
    participanteNome: row.participante_nome,
    status: row.status,
    utilizadoEm: row.utilizado_em,
    entradaEm: row.entrada_em,
    eventoNome: row.evento_nome,
    eventoInicioEm: row.evento_inicio_em,
    eventoLocal: row.evento_local,
    eventoEndereco: row.evento_endereco
  }
}
