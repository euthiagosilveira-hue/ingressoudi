export function formatDataHora(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''

  const dia = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    timeZone: 'America/Sao_Paulo'
  }).format(data)

  const mes = new Intl.DateTimeFormat('pt-BR', {
    month: 'short',
    timeZone: 'America/Sao_Paulo'
  })
    .format(data)
    .replace('.', '')
    .toUpperCase()

  const hora = new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'America/Sao_Paulo'
  }).format(data)

  return `${dia} ${mes} • ${hora}`
}

export function formatData(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''

  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

const moedaBRL = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL'
})

export function formatMoeda(valor: number): string {
  return moedaBRL.format(valor)
}

export function formatNumero(valor: number): string {
  return new Intl.NumberFormat('pt-BR').format(valor)
}

export function formatDataNumerica(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''

  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

export function formatHora(iso: string): string {
  const data = new Date(iso)
  if (Number.isNaN(data.getTime())) return ''

  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: 'America/Sao_Paulo'
  }).format(data)
}

export function formatDataHoraCompleta(iso: string): string {
  const data = formatDataNumerica(iso)
  const hora = formatHora(iso)
  if (!data || !hora) return ''
  return `${data} às ${hora}`
}
