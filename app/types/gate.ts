/** Resultados possiveis de public.registrar_entrada_qr (enum real do backend). */
export type GateRpcResultado =
  | 'LIBERADO'
  | 'JA_UTILIZADO'
  | 'NAO_ENCONTRADO'
  | 'EVENTO_INCORRETO'
  | 'CANCELADO'
  | 'INVALIDO'

/** Resposta normalizada da RPC de portaria. */
export interface RegistrarEntradaQrResult {
  resultado: GateRpcResultado
  ingressoId: string | null
  vipId: string | null
  codigo: string | null
  participanteNome: string | null
  entradaId: string | null
  entradaEm: string | null
  mensagem: string
}

/** Erros de transporte/permissao do scanner (nao sao resultados de negocio). */
export type TipoErroGate =
  | 'OFFLINE'
  | 'TIMEOUT'
  | 'SERVIDOR_INDISPONIVEL'
  | 'SEM_PERMISSAO'
  | 'DESCONHECIDO'

/** Estado de erro exibivel na portaria (taxonomia + validacoes de tela). */
export type GateScanErroCode = TipoErroGate | 'SEM_EVENTO' | 'QR_INVALIDO'

/** Estado local da camera. */
export type GateCameraStatus =
  | 'IDLE'
  | 'SOLICITANDO'
  | 'ATIVA'
  | 'NEGADA'
  | 'INDISPONIVEL'
  | 'SEM_SUPORTE'
  | 'ERRO'

/** Evento operacional listado para a portaria (public.listar_eventos_portaria). */
export interface EventoPortaria {
  eventoId: string
  nome: string
  inicioEm: string
  local: string
  status: string
}

/** Origem de um item no resultado da busca por nome da portaria. */
export type OrigemBuscaPortaria = 'INGRESSO' | 'VIP'

/** Resultado de public.buscar_ingressos_por_nome (ingressos + Lista VIP). */
export interface IngressoBuscaNome {
  origem: OrigemBuscaPortaria
  ingressoId: string | null
  vipId: string | null
  codigo: string | null
  participanteNome: string
  status: string
  utilizadoEm: string | null
  entradaEm: string | null
  /** Telefone para desambiguacao (cru; mascarar no frontend). Pode ser null. */
  telefone: string | null
}

export type TipoEntradaGate = 'INGRESSO' | 'VIP'

/** Ultima entrada LIBERADA na sessao atual da portaria (somente memoria). */
export interface UltimaEntradaGate {
  nome: string
  tipo: TipoEntradaGate
  codigo: string | null
  horario: string
}

/** Estado da sessao local da portaria (nao persistido). */
export interface SessaoPortaria {
  total: number
  ultima: UltimaEntradaGate | null
}
