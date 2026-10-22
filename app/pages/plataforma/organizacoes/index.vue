<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import { BuildingOffice2Icon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import PageHeader from '~/components/PageHeader.vue'
import PushNotificacoesCard from '~/components/plataforma/PushNotificacoesCard.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  criarOrganizacao,
  definirAprovacaoOrganizacao,
  definirListaVipOrganizacao,
  listarOrganizacoesPlataforma,
  type OrganizacaoPlataforma
} from '~/services/admin/organizacoes'
import { rotaOrganizacao } from '~/utils/rotasPublicas'
import { definirTaxaOrganizacao } from '~/services/admin/mercadoPago'

definePageMeta({
  title: 'Organizações',
  description: 'Crie e acesse as organizações (produtores e casas) da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Organizações',
  middleware: ['operator-auth']
})

const { operador, trocarOrganizacao, entrarNaCasa } = useOperatorAuth()

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
    taxas.value = Object.fromEntries(casas.value.map((c) => [c.id, c.taxaServico.toFixed(2)]))
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

async function alterarListaVip(casa: OrganizacaoPlataforma, ativa: boolean) {
  alterandoId.value = casa.id
  try {
    await definirListaVipOrganizacao(casa.id, ativa)
    casa.listaVip = ativa
    toast.success(ativa ? `Lista VIP liberada para ${casa.nome}.` : `Lista VIP desligada para ${casa.nome}.`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar a Lista VIP.')
  } finally {
    alterandoId.value = ''
  }
}

// Taxa de servico por casa: controle exclusivo do super admin
const taxas = ref<Record<string, string>>({})

async function salvarTaxaCasa(casa: OrganizacaoPlataforma) {
  const texto = String(taxas.value[casa.id] ?? '').trim()
  const valor = Number(texto.replace(',', '.'))
  if (texto === '' || Number.isNaN(valor) || valor < 0 || valor > 100) {
    toast.error('Informe uma taxa entre 0 e 100.')
    return
  }
  alterandoId.value = casa.id
  try {
    await definirTaxaOrganizacao(casa.id, valor)
    casa.taxaServico = valor
    taxas.value[casa.id] = valor.toFixed(2)
    toast.success(`Taxa de ${casa.nome} atualizada.`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar a taxa.')
  } finally {
    alterandoId.value = ''
  }
}

function dataCurta(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('pt-BR')
}

onMounted(() => {
  void carregarCasas()
})

/** Entra na casa (modo suporte quando nao e membro) e abre o dashboard dela. */
async function acessarCasa(id: string) {
  alterandoId.value = id
  erro.value = ''
  try {
    await entrarNaCasa(id, '/painel')
  } catch {
    erro.value = 'Não foi possível acessar a organização.'
    alterandoId.value = ''
  }
}

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
      <PushNotificacoesCard />

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
          A taxa de serviço (por ingresso vendido online) só pode ser alterada por você e vale para os próximos pedidos.
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
                <span
                  v-if="casa.listaVip"
                  class="rounded-full border border-sky-400/30 bg-sky-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-sky-300"
                >
                  Lista VIP
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
            <div class="flex flex-wrap items-center gap-2">
              <AppButton size="sm" variant="outline" :to="`/plataforma/organizacoes/${casa.id}`">
                Ver detalhes
              </AppButton>
              <AppButton
                v-if="casa.ativo"
                size="sm"
                variant="outlineAccent"
                :disabled="alterandoId === casa.id"
                @click="acessarCasa(casa.id)"
              >
                Acessar
              </AppButton>
              <form class="flex items-center gap-2" @submit.prevent="salvarTaxaCasa(casa)">
                <label :for="`taxa-${casa.id}`" class="text-xs text-zinc-400">Taxa R$</label>
                <input
                  :id="`taxa-${casa.id}`"
                  v-model="taxas[casa.id]"
                  inputmode="decimal"
                  class="w-20 rounded-lg border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-sm text-white focus:border-amber-400 focus:outline-none"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  variant="ghost"
                  :disabled="alterandoId === casa.id || taxas[casa.id] === casa.taxaServico.toFixed(2)"
                >
                  Salvar
                </AppButton>
              </form>
              <AppButton
                size="sm"
                variant="ghost"
                :disabled="alterandoId === casa.id"
                @click="alterarListaVip(casa, !casa.listaVip)"
              >
                {{ casa.listaVip ? 'Desligar Lista VIP' : 'Liberar Lista VIP' }}
              </AppButton>
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
            </div>
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
