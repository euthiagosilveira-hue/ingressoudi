import { CONTRATO_ORGANIZADOR_VERSAO, mensagemErroContrato } from '~/utils/contratoOrganizador'
import type { DadosOrganizador, TipoDocumento } from '~/utils/documento'

export interface SituacaoOrganizador {
  nome: string
  tipoDocumento: TipoDocumento | null
  documento: string
  responsavelNome: string
  telefone: string
  versaoVigente: string
  dadosCompletos: boolean
  contratoPendente: boolean
  ultimoAceite: { versao: string; aceitoEm: string; usuarioNome: string; usuarioEmail: string } | null
}

function mapear(data: unknown): SituacaoOrganizador {
  const r = (data ?? {}) as Record<string, any>
  const a = r.ultimo_aceite as Record<string, any> | null
  return {
    nome: String(r.nome ?? ''),
    tipoDocumento: r.tipo_documento === 'CPF' || r.tipo_documento === 'CNPJ' ? r.tipo_documento : null,
    documento: String(r.documento ?? ''),
    responsavelNome: String(r.responsavel_nome ?? ''),
    telefone: String(r.telefone ?? ''),
    versaoVigente: String(r.versao_vigente ?? ''),
    dadosCompletos: Boolean(r.dados_completos),
    contratoPendente: Boolean(r.contrato_pendente),
    ultimoAceite: a
      ? {
          versao: String(a.versao ?? ''),
          aceitoEm: String(a.aceito_em ?? ''),
          usuarioNome: String(a.usuario_nome ?? ''),
          usuarioEmail: String(a.usuario_email ?? '')
        }
      : null
  }
}

/** Dados do organizador da casa ativa + situacao do contrato. */
export async function obterDadosOrganizador(): Promise<SituacaoOrganizador> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_dados_organizador')
  if (error) throw new Error(mensagemErroContrato(error.message))
  return mapear(data)
}

export async function salvarDadosOrganizador(dados: DadosOrganizador): Promise<SituacaoOrganizador> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('salvar_dados_organizador', {
    p_tipo_documento: dados.tipoDocumento,
    p_documento: dados.documento,
    p_responsavel_nome: dados.responsavelNome,
    p_telefone: dados.telefone
  })
  if (error) throw new Error(mensagemErroContrato(error.message))
  return mapear(data)
}

/** Registra o aceite pelo servidor (que grava IP e navegador). */
export async function aceitarContratoOrganizador(versao = CONTRATO_ORGANIZADOR_VERSAO): Promise<void> {
  try {
    await $fetch('/api/contrato/aceitar', { method: 'POST', body: { versao } })
  } catch (e) {
    const err = e as { data?: { error?: string; statusMessage?: string }; statusMessage?: string }
    throw new Error(mensagemErroContrato(err?.data?.error ?? err?.data?.statusMessage ?? err?.statusMessage ?? null))
  }
}
