import type {
  AdminUsuarioRow,
  ConviteUsuarioInput,
  EdicaoUsuarioInput,
  PerfilUsuario,
  UsuarioListItem
} from '~/types/usuario'

export const PERFIS_USUARIO: PerfilUsuario[] = ['ADMINISTRADOR', 'PORTARIA']

const PERFIL_LABEL: Record<PerfilUsuario, string> = {
  ADMINISTRADOR: 'Administrador',
  PORTARIA: 'Portaria'
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function rotuloPerfil(perfil: PerfilUsuario): string {
  return PERFIL_LABEL[perfil] ?? perfil
}

export function emailValido(email: string): boolean {
  return EMAIL_RE.test((email ?? '').trim())
}

function formatarDataHora(iso: string | null): string {
  if (!iso) return 'Sem registro'
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return 'Sem registro'
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

function mapearBase(row: AdminUsuarioRow): Omit<UsuarioListItem, 'ehUltimoAdminAtivo'> {
  return {
    id: row.id,
    nome: row.nome,
    email: row.email,
    perfil: row.perfil,
    ativo: row.ativo,
    ultimoAcesso: formatarDataHora(row.ultimo_acesso_em),
    criadoEm: formatarDataHora(row.criado_em)
  }
}

export function contarAdminsAtivos(rows: AdminUsuarioRow[]): number {
  return rows.filter((u) => u.perfil === 'ADMINISTRADOR' && u.ativo).length
}

export function mapearUsuarioAdmin(row: AdminUsuarioRow): UsuarioListItem {
  return { ...mapearBase(row), ehUltimoAdminAtivo: false }
}

/** Mapeia a lista e marca quem e o unico ADMINISTRADOR ativo (protecao de UI). */
export function mapearUsuariosAdmin(rows: AdminUsuarioRow[]): UsuarioListItem[] {
  const adminsAtivos = contarAdminsAtivos(rows)
  return rows.map((row) => ({
    ...mapearBase(row),
    ehUltimoAdminAtivo: row.perfil === 'ADMINISTRADOR' && row.ativo && adminsAtivos === 1
  }))
}

export interface ErrosFormularioUsuario {
  nome?: string
  email?: string
  perfil?: string
}

export function validarConvite(input: ConviteUsuarioInput): ErrosFormularioUsuario {
  const erros: ErrosFormularioUsuario = {}
  if (!input.nome?.trim()) erros.nome = 'Informe o nome.'
  if (!emailValido(input.email)) erros.email = 'Informe um e-mail válido.'
  if (!PERFIS_USUARIO.includes(input.perfil)) erros.perfil = 'Selecione um perfil.'
  return erros
}

export function validarEdicao(input: EdicaoUsuarioInput): ErrosFormularioUsuario {
  const erros: ErrosFormularioUsuario = {}
  if (!input.nome?.trim()) erros.nome = 'Informe o nome.'
  if (!PERFIS_USUARIO.includes(input.perfil)) erros.perfil = 'Selecione um perfil.'
  return erros
}

export function formularioValido(erros: ErrosFormularioUsuario): boolean {
  return Object.keys(erros).length === 0
}

export function montarPayloadAtualizacao(input: EdicaoUsuarioInput) {
  return {
    p_usuario_id: input.id,
    p_nome: input.nome.trim(),
    p_perfil: input.perfil,
    p_ativo: input.ativo
  }
}

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

export function mensagemErroUsuario(error: RpcErrorLike | null, padrao: string): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()
  if (e.code === '42501' || mensagem.includes('permiss')) {
    if (mensagem.includes('proprio')) {
      return 'Você não pode desativar o seu próprio usuário.'
    }
    return 'Você não tem permissão para gerenciar usuários.'
  }
  if (mensagem.includes('pelo menos um administrador')) {
    return 'É necessário manter pelo menos um administrador ativo.'
  }
  if (
    e.code === '23505' ||
    mensagem.includes('duplicate') ||
    mensagem.includes('unique') ||
    mensagem.includes('unico')
  ) {
    return 'Já existe um usuário com este e-mail.'
  }
  if (e.code === '23514') return 'Verifique os dados informados.'
  if (e.code === '23503' || mensagem.includes('nao encontrado')) return 'Usuário não encontrado.'
  return padrao
}

export function mensagemErroConvite(codigo?: string): string {
  switch (codigo) {
    case 'EMAIL_DUPLICADO':
      return 'Já existe um usuário com este e-mail.'
    case 'SEM_PERMISSAO':
      return 'Você não tem permissão para convidar usuários.'
    case 'DADOS_INVALIDOS':
      return 'Verifique o nome, o e-mail e o perfil informados.'
    case 'FALHA_CONVITE':
      return 'Não foi possível enviar o convite. Tente novamente.'
    case 'NAO_AUTENTICADO':
      return 'Sua sessão expirou. Entre novamente.'
    default:
      return 'Não foi possível concluir a operação.'
  }
}
