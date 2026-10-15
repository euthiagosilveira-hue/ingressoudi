/**
 * Financeiro da plataforma (super admin): periodos e helpers puros (testaveis).
 * Datas no formato YYYY-MM-DD, no fuso do navegador (Brasil).
 */

export type PresetPeriodo = 'HOJE' | '7D' | '30D' | 'MES' | 'MES_ANTERIOR' | 'PERSONALIZADO'

export interface Periodo {
  inicio: string
  fim: string
}

export const PRESETS_PERIODO: Array<{ value: PresetPeriodo; label: string }> = [
  { value: 'HOJE', label: 'Hoje' },
  { value: '7D', label: '7 dias' },
  { value: '30D', label: '30 dias' },
  { value: 'MES', label: 'Este mês' },
  { value: 'MES_ANTERIOR', label: 'Mês passado' },
  { value: 'PERSONALIZADO', label: 'Personalizado' }
]

export function dataIso(data: Date): string {
  const a = data.getFullYear()
  const m = String(data.getMonth() + 1).padStart(2, '0')
  const d = String(data.getDate()).padStart(2, '0')
  return `${a}-${m}-${d}`
}

function somarDias(data: Date, dias: number): Date {
  const nova = new Date(data.getFullYear(), data.getMonth(), data.getDate())
  nova.setDate(nova.getDate() + dias)
  return nova
}

/** Periodo de um preset relativo a "hoje" (PERSONALIZADO devolve null). */
export function periodoDoPreset(preset: PresetPeriodo, hoje: Date = new Date()): Periodo | null {
  const dia = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate())
  switch (preset) {
    case 'HOJE':
      return { inicio: dataIso(dia), fim: dataIso(dia) }
    case '7D':
      return { inicio: dataIso(somarDias(dia, -6)), fim: dataIso(dia) }
    case '30D':
      return { inicio: dataIso(somarDias(dia, -29)), fim: dataIso(dia) }
    case 'MES':
      return { inicio: dataIso(new Date(dia.getFullYear(), dia.getMonth(), 1)), fim: dataIso(dia) }
    case 'MES_ANTERIOR': {
      const inicio = new Date(dia.getFullYear(), dia.getMonth() - 1, 1)
      const fim = new Date(dia.getFullYear(), dia.getMonth(), 0)
      return { inicio: dataIso(inicio), fim: dataIso(fim) }
    }
    default:
      return null
  }
}

/** Mensagem de erro do periodo, ou '' quando valido (mesmas regras do banco). */
export function validarPeriodo(p: Periodo): string {
  const re = /^\d{4}-\d{2}-\d{2}$/
  if (!re.test(p.inicio) || !re.test(p.fim)) return 'Informe as duas datas.'
  if (p.fim < p.inicio) return 'A data final deve ser igual ou posterior à inicial.'
  const dias = (Date.parse(`${p.fim}T00:00:00Z`) - Date.parse(`${p.inicio}T00:00:00Z`)) / 86_400_000
  if (dias > 366) return 'Escolha um período de até 1 ano.'
  return ''
}

/** "15/10/2026" a partir de "2026-10-15". */
export function formatarDiaIso(iso: string): string {
  const [a, m, d] = iso.split('-')
  return a && m && d ? `${d}/${m}/${a}` : iso
}
