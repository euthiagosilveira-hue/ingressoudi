import { reactive, ref, watch } from 'vue'

import type { EventFormErrors, EventFormValue, EventPayload } from '~/types/evento'
import { gerarSlug, montarInicioEm } from '~/utils/eventos'

export function criarValorInicial(): EventFormValue {
  return {
    nome: '',
    slug: '',
    descricao: '',
    imagemUrl: null,
    dataInicio: '',
    horaInicio: '',
    local: '',
    endereco: '',
    capacidadeTotal: null,
    estoqueAntecipado: null,
    publicacaoStatus: 'RASCUNHO',
    vendasStatus: 'ENCERRADAS',
    status: 'AGENDADO'
  }
}

export function useEventForm(options: { initialValue?: Partial<EventFormValue> } = {}) {
  const valor = reactive<EventFormValue>({
    ...criarValorInicial(),
    ...options.initialValue
  })

  const erros = reactive<EventFormErrors>({})
  const enviando = ref(false)
  const slugEditadoManualmente = ref(false)

  watch(
    () => valor.nome,
    (nome) => {
      if (!slugEditadoManualmente.value) {
        valor.slug = gerarSlug(nome)
      }
    }
  )

  function marcarSlugManual() {
    slugEditadoManualmente.value = true
  }

  function usarUrlAutomatica() {
    slugEditadoManualmente.value = false
    valor.slug = gerarSlug(valor.nome)
  }

  function limparErros() {
    ;(Object.keys(erros) as Array<keyof EventFormErrors>).forEach((chave) => {
      delete erros[chave]
    })
  }

  function validar(): boolean {
    limparErros()

    const slugValido = /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(valor.slug)

    if (!valor.nome.trim()) erros.nome = 'Informe o nome do evento.'

    if (!valor.slug.trim()) erros.slug = 'Informe o slug.'
    else if (!slugValido) erros.slug = 'Use apenas letras minúsculas, números e hífens.'

    if (!valor.dataInicio) erros.dataInicio = 'Informe a data do evento.'
    if (!valor.horaInicio) erros.horaInicio = 'Informe o horário de início.'
    if (!valor.local.trim()) erros.local = 'Informe o local.'
    if (!valor.endereco.trim()) erros.endereco = 'Informe o endereço.'

    if (
      valor.capacidadeTotal === null ||
      Number.isNaN(valor.capacidadeTotal) ||
      valor.capacidadeTotal <= 0
    ) {
      erros.capacidadeTotal = 'A capacidade deve ser maior que zero.'
    }

    if (
      valor.estoqueAntecipado === null ||
      Number.isNaN(valor.estoqueAntecipado) ||
      valor.estoqueAntecipado < 0
    ) {
      erros.estoqueAntecipado = 'O estoque não pode ser negativo.'
    } else if (
      valor.capacidadeTotal !== null &&
      valor.estoqueAntecipado > valor.capacidadeTotal
    ) {
      erros.estoqueAntecipado = 'O estoque não pode exceder a capacidade total.'
    }

    if ((valor.descricao || '').length > 500) {
      erros.descricao = 'A descrição deve ter no máximo 500 caracteres.'
    }

    return Object.keys(erros).length === 0
  }

  function montarPayload(): EventPayload {
    return {
      nome: valor.nome.trim(),
      slug: valor.slug.trim(),
      descricao: valor.descricao.trim(),
      imagemUrl: valor.imagemUrl,
      inicioEm: montarInicioEm(valor.dataInicio, valor.horaInicio),
      local: valor.local.trim(),
      endereco: valor.endereco.trim(),
      capacidadeTotal: valor.capacidadeTotal as number,
      estoqueAntecipado: valor.estoqueAntecipado as number,
      status: 'AGENDADO',
      vendasStatus: valor.vendasStatus,
      publicacaoStatus: valor.publicacaoStatus
    }
  }

  return {
    valor,
    erros,
    enviando,
    slugEditadoManualmente,
    marcarSlugManual,
    usarUrlAutomatica,
    validar,
    montarPayload
  }
}
