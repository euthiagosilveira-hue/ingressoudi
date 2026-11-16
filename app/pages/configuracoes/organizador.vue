<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { toast } from 'vue3-toastify'
import { CheckBadgeIcon, DocumentTextIcon, ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import CamposOrganizador from '~/components/organizador/CamposOrganizador.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  aceitarContratoOrganizador,
  obterDadosOrganizador,
  salvarDadosOrganizador,
  type SituacaoOrganizador
} from '~/services/admin/organizador'
import { CONTRATO_ORGANIZADOR_URL, CONTRATO_ORGANIZADOR_VERSAO } from '~/utils/contratoOrganizador'
import {
  formatarDocumento,
  formatarTelefone,
  validarDadosOrganizador,
  type DadosOrganizador,
  type ErrosOrganizador
} from '~/utils/documento'

definePageMeta({
  title: 'Dados do organizador',
  description: 'CPF ou CNPJ, telefone e Contrato do Organizador.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth']
})

const { operador } = useOperatorAuth()
const modoSuporte = computed(() => Boolean(operador.value?.modoSuporte))

const carregando = ref(true)
const erroCarga = ref('')
const salvando = ref(false)
const situacao = ref<SituacaoOrganizador | null>(null)
const dados = ref<DadosOrganizador>({ tipoDocumento: 'CPF', documento: '', responsavelNome: '', telefone: '' })
const erros = reactive<ErrosOrganizador>({})
const aceito = ref(false)
const erroAceite = ref('')

const pendente = computed(() => Boolean(situacao.value?.contratoPendente))
const aceiteVigente = computed(
  () => situacao.value?.ultimoAceite && situacao.value.ultimoAceite.versao === situacao.value.versaoVigente
)
const precisaAceitar = computed(() => !aceiteVigente.value && !modoSuporte.value)

function formatarData(iso: string): string {
  try {
    return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return iso
  }
}

function aplicar(s: SituacaoOrganizador) {
  situacao.value = s
  if (s.tipoDocumento) {
    dados.value = {
      tipoDocumento: s.tipoDocumento,
      documento: formatarDocumento(s.tipoDocumento, s.documento),
      responsavelNome: s.responsavelNome,
      telefone: formatarTelefone(s.telefone)
    }
  } else {
    dados.value = {
      ...dados.value,
      responsavelNome: dados.value.responsavelNome || s.responsavelNome,
      telefone: dados.value.telefone || formatarTelefone(s.telefone)
    }
  }
}

async function carregar() {
  carregando.value = true
  erroCarga.value = ''
  try {
    aplicar(await obterDadosOrganizador())
  } catch (e) {
    erroCarga.value = e instanceof Error ? e.message : 'Não foi possível carregar.'
  } finally {
    carregando.value = false
  }
}

async function salvar() {
  for (const k of Object.keys(erros) as Array<keyof ErrosOrganizador>) erros[k] = undefined
  erroAceite.value = ''
  Object.assign(erros, validarDadosOrganizador(dados.value))
  if (Object.values(erros).some(Boolean)) return
  if (precisaAceitar.value && !aceito.value) {
    erroAceite.value = 'Leia e aceite o Contrato do Organizador para continuar.'
    return
  }

  salvando.value = true
  try {
    aplicar(await salvarDadosOrganizador(dados.value))
    if (precisaAceitar.value) {
      await aceitarContratoOrganizador(CONTRATO_ORGANIZADOR_VERSAO)
      toast.success('Dados salvos e contrato aceito.')
      // Recarrega a aplicacao: a sessao deixa de ter pendencia e o painel libera.
      window.location.assign('/painel')
      return
    }
    toast.success('Dados do organizador atualizados.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar.')
  } finally {
    salvando.value = false
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      ajuda="dados-organizador-contrato"
      title="Dados do organizador"
      subtitle="Quem vende os ingressos e o contrato com a plataforma."
    >
      <template v-if="!pendente" #actions>
        <AppButton to="/configuracoes" size="sm">Voltar</AppButton>
      </template>
    </PageHeader>

    <div v-if="carregando" class="h-40 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />

    <BaseCard v-else-if="erroCarga">
      <p class="text-sm text-red-300">{{ erroCarga }}</p>
      <AppButton class="mt-3" size="sm" @click="carregar">Tentar novamente</AppButton>
    </BaseCard>

    <template v-else-if="situacao">
      <p
        v-if="pendente && !modoSuporte"
        role="status"
        class="flex items-start gap-2 rounded-xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-100"
      >
        <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
        <span>
          Para continuar usando o painel, confirme os dados de quem vende os ingressos e aceite o Contrato do
          Organizador. Leva menos de um minuto. As vendas dos eventos já publicados continuam normalmente.
        </span>
      </p>
      <p
        v-else-if="pendente && modoSuporte"
        role="status"
        class="rounded-xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-100"
      >
        Modo suporte: você pode corrigir os dados, mas o aceite do contrato só pode ser feito por um administrador da
        casa.
      </p>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <BaseCard>
          <h2 class="text-sm font-semibold text-white">Quem vende os ingressos</h2>
          <p class="mt-1 text-xs text-zinc-500">
            Aparece para o comprador na página do evento. O CPF é mostrado parcialmente; o CNPJ, completo.
          </p>
          <div class="mt-4">
            <CamposOrganizador v-model="dados" :erros="erros" />
          </div>
        </BaseCard>

        <BaseCard>
          <div class="flex items-start gap-3">
            <span
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400"
            >
              <DocumentTextIcon class="h-6 w-6" />
            </span>
            <div>
              <h2 class="text-sm font-semibold text-white">Contrato do Organizador</h2>
              <p class="mt-1 text-xs text-zinc-500">
                Define as responsabilidades da casa e da plataforma: realização do evento, cancelamento, reembolso
                dos compradores e taxa de serviço.
              </p>
              <NuxtLink
                :to="CONTRATO_ORGANIZADOR_URL"
                target="_blank"
                class="mt-2 inline-block text-sm font-semibold text-amber-400 hover:text-amber-300"
              >
                Ler o contrato completo
              </NuxtLink>
            </div>
          </div>

          <div
            v-if="aceiteVigente && situacao.ultimoAceite"
            class="mt-5 flex items-start gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200"
          >
            <CheckBadgeIcon class="mt-0.5 h-5 w-5 shrink-0" />
            <span>
              Aceito em {{ formatarData(situacao.ultimoAceite.aceitoEm) }} por
              {{ situacao.ultimoAceite.usuarioNome || situacao.ultimoAceite.usuarioEmail }}
              (versão {{ situacao.ultimoAceite.versao }}).
            </span>
          </div>

          <div v-else-if="!modoSuporte" class="mt-5">
            <p v-if="situacao.ultimoAceite" class="mb-3 text-xs text-zinc-400">
              O contrato foi atualizado desde o último aceite ({{ situacao.ultimoAceite.versao }}). Leia a versão nova.
            </p>
            <label class="flex cursor-pointer items-start gap-3 text-sm text-zinc-300">
              <input
                v-model="aceito"
                type="checkbox"
                class="mt-0.5 h-4 w-4 shrink-0 rounded border-zinc-600 bg-zinc-900 accent-amber-400"
              />
              <span>
                Li e aceito o
                <NuxtLink :to="CONTRATO_ORGANIZADOR_URL" target="_blank" class="text-amber-400 hover:text-amber-300">
                  Contrato do Organizador</NuxtLink>
                em nome de {{ situacao.nome }}, e declaro que os dados informados são verdadeiros.
              </span>
            </label>
            <p v-if="erroAceite" class="mt-1.5 text-xs text-red-400">{{ erroAceite }}</p>
            <p class="mt-3 text-xs text-zinc-500">
              Registramos a data, a hora, o IP e o navegador do aceite.
            </p>
          </div>
        </BaseCard>
      </div>

      <div class="flex justify-end">
        <AppButton variant="primary" :disabled="salvando" @click="salvar">
          {{ salvando ? 'Salvando...' : precisaAceitar ? 'Salvar e aceitar o contrato' : 'Salvar dados' }}
        </AppButton>
      </div>
    </template>
  </div>
</template>
