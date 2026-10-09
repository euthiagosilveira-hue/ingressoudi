export interface SharedTicket {
  ingressoId: string
  codigo: string
  participanteNome: string
  status: string
  utilizadoEm: string | null
  entradaEm: string | null
  eventoNome: string
  eventoInicioEm: string | null
  eventoLocal: string | null
  eventoEndereco: string | null
}
