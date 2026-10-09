import { reactive } from 'vue'

import type {
  LotFormErrors,
  LotFormValue,
  LotOrdemRef,
  LotPayload
} from '~/types/lote'
import { montarAtivacaoEm, ordemDuplicada } from '~/utils/lotes'

export function criarValorInicialLote(): LotFormValue {
  return {
    nome: '',
    ordem: null,
    quantidade: null,
    preco: null,
    tipoAtivacao: 'MANUAL',
    dataAtivacao: '',
    horaAtivacao: '',
    status: 'INATIVO'
  }
}

export function useLotForm(
  options: {
    initialValue?: Partial<LotFormValue>
    ordens?: LotOrdemRef[]
    idAtual?: string
  } = {}
) {
  const valor = reactive<LotFormValue>({
    ...criarValorInicialLote(),
    ...options.initialValue
  })

  const erros = reactive<LotFormErrors>({})
  const ordens = options.ordens ?? []
  const idAtual = options.idAtual

  function limparErros() {
    ;(Object.keys(erros) as Array<keyof LotFormErrors>).forEach((chave) => {
      delete erros[chave]
    })
  }

  function validar(): boolean {
    limparErros()

    if (!valor.nome.trim()) erros.nome = 'Informe o nome do lote.'

    if (
      valor.ordem === null ||
      Number.isNaN(valor.ordem) ||
      !Number.isInteger(valor.ordem) ||
      valor.ordem <= 0
    ) {
      erros.ordem = 'A ordem deve ser um número inteiro maior que zero.'
    } else if (ordemDuplicada(ordens, valor.ordem, idAtual)) {
      erros.ordem = 'Já existe um lote com esta ordem.'
    }

    if (
      valor.quantidade === null ||
      Number.isNaN(valor.quantidade) ||
      !Number.isInteger(valor.quantidade) ||
      valor.quantidade <= 0
    ) {
      erros.quantidade = 'A quantidade deve ser um número inteiro maior que zero.'
    }

    if (valor.preco === null || Number.isNaN(valor.preco) || valor.preco < 0) {
      erros.preco = 'O preço deve ser maior ou igual a zero.'
    }

    if (!valor.tipoAtivacao) {
      erros.tipoAtivacao = 'Selecione o tipo de ativação.'
    }

    if (valor.tipoAtivacao === 'DATA_HORA') {
      if (!valor.dataAtivacao) erros.dataAtivacao = 'Informe a data de ativação.'
      if (!valor.horaAtivacao) erros.horaAtivacao = 'Informe o horário de ativação.'
    }

    return Object.keys(erros).length === 0
  }

  function montarPayload(): LotPayload {
    return {
      nome: valor.nome.trim(),
      ordem: valor.ordem as number,
      quantidade: valor.quantidade as number,
      preco: valor.preco as number,
      tipoAtivacao: valor.tipoAtivacao,
      ativacaoEm:
        valor.tipoAtivacao === 'DATA_HORA'
          ? montarAtivacaoEm(valor.dataAtivacao, valor.horaAtivacao)
          : null
    }
  }

  return {
    valor,
    erros,
    validar,
    montarPayload
  }
}
