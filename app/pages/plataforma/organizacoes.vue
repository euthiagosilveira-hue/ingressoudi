<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import { BuildingOffice2Icon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import PageHeader from '~/components/PageHeader.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  criarOrganizacao,
  definirAprovacaoOrganizacao,
  listarOrganizacoesPlataforma,
  type OrganizacaoPlataforma
} from '~/services/admin/organizacoes'
import { rotaOrganizacao } from '~/utils/rotasPublicas'
import { definirTaxaOrganizacao, obterStatusMercadoPago } from '~/services/admin/mercadoPago'

definePageMeta({
  title: 'Organizações',
  description: 'Crie e acesse as organizações (produtores e casas) da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Organizações',
  middleware: ['operator-auth']
})

const { operador, trocarOrganizacao } = useOperatorAuth()

const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))
const nome = ref('')
const slug = ref('')
const enviando = ref(false)
const erro = ref('')

async function criar() {
  if (!nome.value.trim()) {
    erro.value = 'Informe o nome da organização.'
    return
  }
  enviando.value = true
  erro.value = ''
  try {
    await criarOrganizacao(nome.value.trim(), slug.value)
    // a nova organizacao ja e a ativa: recarrega a aplicacao nela
    window.location.assign('/painel')
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível criar a organização.'
    enviando.value = false
  }
}

// Taxa de servico da organizacao ativa (somente super admin)
const taxa = ref('')
const salvandoTaxa = ref(false)

async function carregarTaxa() {
  if (!ehSuperAdmin.value || !operador.value?.organizacao?.id) return
  try {
    const status = await obterStatusMercadoPago()
    taxa.value = status.taxaServico.toFixed(2)
  } catch {
    taxa.value = ''
  }
}

async function salvarTaxa() {
  const organizacaoId = operador.value?.organizacao?.id
  const valor = Number(String(taxa.value).replace(',', '.'))
  if (!organizacaoId || String(taxa.value).trim() === '' || Number.isNaN(valor) || valor < 0 || valor > 100) {
    toast.error('Informe uma taxa entre 0 e 100.')
    return
  }
  salvandoTaxa.value = true
  try {
    await definirTaxaOrganizacao(organizacaoId, valor)
    taxa.value = valor.toFixed(2)
    toast.success('Taxa atualizada.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar a taxa.')
  } finally {
    salvandoTaxa.value = false
  }
}

// Casas da plataforma: aprovacao de cadastros (somente super admin)
const casas = ref<OrganizacaoPlataforma[]>([])
const carregandoCasas = ref(false)
const alterandoId = ref('')
const pendentes = computed(() => casas.value.filter((c) => !c.aprovada).length)

async function carregarCasas() {
  if (!ehSuperAdmin.value) return
  carregandoCasas.value = true
  try {
    casas.value = await listarOrganizacoesPlataforma()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível carregar as casas.')
  } finally {
    carregandoCasas.value = false
  }
}

async function alterarAprovacao(casa: OrganizacaoPlataforma, aprovada: boolean) {
  alterandoId.value = casa.id
  try {
    await definirAprovacaoOrganizacao(casa.id, aprovada)
    casa.aprovada = aprovada
    toast.success(aprovada ? `${casa.nome} aprovada.` : `${casa.nome} voltou para análise.`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar a aprovação.')
  } finally {
    alterandoId.value = ''
  }
}

function dataCurta(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('pt-BR')
}

onMounted(() => {
  void carregarTaxa()
  void carregarCasas()
})

async function acessar(id: string) {
  erro.value = ''
  try {
    const perfil = await trocarOrganizacao(id)
    window.location.assign(perfil?.perfil === 'PORTARIA' ? '/portaria' : '/painel')
  } catch {
    erro.value = 'Não foi possível acessar a organização.'
  }
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Organizações"
      subtitle="Cada produtor ou casa de eventos é uma organização com dados separados."
    />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <BaseCard>
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold text-white">Casas da plataforma</h2>
          <span
            v-if="pendentes > 0"
            class="rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
          >
            {{ pendentes }} em análise
          </span>
        </div>
        <p class="mt-1 text-xs text-zinc-500">
          Casas cadastradas pelo site entram em análise: não publicam eventos nem aparecem no site até a aprovação.
        </p>
        <p v-if="carregandoCasas" class="mt-4 text-sm text-zinc-500">Carregando...</p>
        <ul v-else class="mt-4 divide-y divide-zinc-800">
          <li
            v-for="casa in casas"
            :key="casa.id"
            class="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="min-w-0">
              <p class="flex items-center gap-2 truncate text-sm font-semibold text-white">
                {{ casa.nome }}
                <span
                  :class="
                    casa.aprovada
                      ? 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300'
                      : 'border-amber-400/30 bg-amber-400/10 text-amber-300'
                  "
                  class="rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
                >
                  {{ casa.aprovada ? 'Aprovada' : 'Em análise' }}
                </span>
                <span
                  v-if="!casa.ativo"
                  class="rounded-full border border-zinc-600 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-400"
                >
                  Inativa
                </span>
              </p>
              <p class="truncate text-xs text-zinc-500">
                <a :href="rotaOrganizacao(casa.slug)" target="_blank" class="hover:text-amber-400">/{{ casa.slug }}</a>
                · {{ casa.administradores || 'sem administrador' }}
              </p>
              <p class="text-xs text-zinc-600">
                Cadastro {{ dataCurta(casa.criadoEm) }} · {{ casa.eventos }} evento(s) · Mercado Pago
                {{ casa.mercadoPagoConectado ? 'conectado' : 'não conectado' }}
              </p>
            </div>
            <AppButton
              v-if="!casa.aprovada"
              size="sm"
              variant="primary"
              :disabled="alterandoId === casa.id"
              @click="alterarAprovacao(casa, true)"
            >
              Aprovar
            </AppButton>
            <AppButton
              v-else
              size="sm"
              variant="ghost"
              :disabled="alterandoId === casa.id"
              @click="alterarAprovacao(casa, false)"
            >
              Voltar para análise
            </AppButton>
          </li>
        </ul>
      </BaseCard>

      <BaseCard>
        <h2 class="text-sm font-semibold text-white">Nova organização</h2>
        <p class="mt-1 text-xs text-zinc-500">
          Você será administrador da nova organização e poderá convidar a equipe do produtor em
          Configurações → Usuários.
        </p>
        <form class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2" @submit.prevent="criar">
          <BaseInput v-model="nome" label="Nome" placeholder="Ex.: Casa do Pagode" required />
          <BaseInput
            v-model="slug"
            label="Endereço (opcional)"
            placeholder="gerado a partir do nome"
          />
          <div class="sm:col-span-2 flex items-center gap-3">
            <AppButton type="submit" variant="primary" :disabled="enviando">
              {{ enviando ? 'Criando...' : 'Criar organização' }}
            </AppButton>
            <p v-if="erro" class="text-xs text-red-400">{{ erro }}</p>
          </div>
        </form>
      </BaseCard>

      <BaseCard v-if="operador?.organizacao">
        <h2 class="text-sm font-semibold text-white">
          Taxa de serviço — {{ operador.organizacao.nome }}
        </h2>
        <p class="mt-1 text-xs text-zinc-500">
          Valor por ingresso vendido online nesta organização (padrão R$ 1,00). Vale para os próximos pedidos.
        </p>
        <form class="mt-4 flex flex-wrap items-end gap-3" @submit.prevent="salvarTaxa">
          <BaseInput v-model="taxa" label="Taxa (R$)" placeholder="1.00" />
          <AppButton type="submit" variant="primary" :disabled="salvandoTaxa">
            {{ salvandoTaxa ? 'Salvando...' : 'Salvar taxa' }}
          </AppButton>
        </form>
      </BaseCard>

      <BaseCard>
        <h2 class="text-sm font-semibold text-white">Minhas organizações</h2>
        <ul class="mt-4 divide-y divide-zinc-800">
          <li
            v-for="org in operador?.organizacoes ?? []"
            :key="org.id"
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="flex min-w-0 items-center gap-3">
              <BuildingOffice2Icon class="h-5 w-5 shrink-0 text-amber-400" />
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold text-white">{{ org.nome }}</p>
                <p class="truncate text-xs text-zinc-500">{{ org.slug }} · {{ org.perfil }}</p>
              </div>
            </div>
            <span
              v-if="org.id === operador?.organizacao?.id"
              class="rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
            >
              Ativa
            </span>
            <AppButton v-else size="sm" @click="acessar(org.id)">Acessar</AppButton>
          </li>
        </ul>
      </BaseCard>
    </template>
  </div>
</template>
