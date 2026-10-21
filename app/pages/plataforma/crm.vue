<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  ArrowDownTrayIcon,
  ArrowPathIcon,
  ArrowTrendingUpIcon,
  BanknotesIcon,
  CalendarDaysIcon,
  ChatBubbleLeftRightIcon,
  ChevronDoubleRightIcon,
  ClockIcon,
  MagnifyingGlassIcon,
  MegaphoneIcon,
  PencilSquareIcon,
  PlusIcon,
  PresentationChartBarIcon,
  TicketIcon,
  TrashIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import CrmKanban from '~/components/plataforma/crm/CrmKanban.vue'
import CrmLeadHistorico from '~/components/plataforma/crm/CrmLeadHistorico.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  excluirProdutorCrm,
  importarCasasCrm,
  listarProdutoresCrm,
  moverEtapaCrm,
  obterIndicadoresCrm,
  salvarProdutorCrm
} from '~/services/admin/crm'
import { listarOrganizacoesPlataforma, type OrganizacaoPlataforma } from '~/services/admin/organizacoes'
import {
  ETAPAS_CRM,
  csvProdutores,
  diasNaEtapa,
  filtrarProdutores,
  formDoProdutor,
  formVazio,
  leadEsfriando,
  linkInstagram,
  linkWhatsapp,
  ordemEtapa,
  resumoIndicadores,
  rotuloEtapa,
  situacaoAcao,
  sugestaoAvanco,
  validarFormCrm,
  type EtapaCrm,
  type FiltroCrm,
  type FormProdutorCrm,
  type IndicadoresCrm,
  type ProdutorCrm
} from '~/utils/crm'
import { dataIso, formatarDiaIso, periodoDoPreset } from '~/utils/financeiroPlataforma'
import { formatMoeda, formatNumero } from '~/utils/format'

definePageMeta({
  title: 'CRM comercial',
  description: 'Prospecção de produtores, funil e indicadores comerciais.',
  layout: 'admin-layout',
  sidebarActive: 'CRM comercial',
  middleware: ['operator-auth']
})

const { operador } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const hoje = dataIso(new Date())

// Periodo dos indicadores ------------------------------------------------------------
type PeriodoCrm = 'MES' | 'MES_ANTERIOR' | '30D' | 'TUDO'
const periodo = ref<PeriodoCrm>('MES')
const opcoesPeriodo = [
  { value: 'MES', label: 'Este mês' },
  { value: 'MES_ANTERIOR', label: 'Mês passado' },
  { value: '30D', label: '30 dias' },
  { value: 'TUDO', label: 'Desde o início' }
]
const intervalo = computed(() => (periodo.value === 'TUDO' ? null : periodoDoPreset(periodo.value)))
const rotuloPeriodo = computed(() =>
  intervalo.value ? `${formatarDiaIso(intervalo.value.inicio)} a ${formatarDiaIso(intervalo.value.fim)}` : 'desde o início'
)

// Dados ------------------------------------------------------------------------------
const produtores = ref<ProdutorCrm[]>([])
const indicadores = ref<IndicadoresCrm | null>(null)
const casas = ref<OrganizacaoPlataforma[]>([])
const carregando = ref(false)
const erro = ref('')
const aviso = ref('')

async function carregarIndicadores() {
  indicadores.value = await obterIndicadoresCrm(intervalo.value?.inicio ?? null, intervalo.value?.fim ?? null)
}

async function carregar() {
  if (!ehSuperAdmin.value) return
  carregando.value = true
  erro.value = ''
  try {
    const [lista] = await Promise.all([listarProdutoresCrm(), carregarIndicadores()])
    produtores.value = lista
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o CRM.'
  } finally {
    carregando.value = false
  }
}

watch(periodo, async () => {
  try {
    await carregarIndicadores()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os indicadores.'
  }
})

onMounted(async () => {
  await carregar()
  if (!ehSuperAdmin.value) return
  try {
    casas.value = await listarOrganizacoesPlataforma()
  } catch {
    // Sem a lista de casas o CRM funciona; so nao da para ligar um produtor a casa.
  }
})

const resumo = computed(() => (indicadores.value ? resumoIndicadores(indicadores.value) : null))

// Filtros ----------------------------------------------------------------------------
const filtro = ref<FiltroCrm>('TODOS')
const busca = ref('')
const opcoesFiltro = [
  { value: 'TODOS', label: 'Todas as etapas' },
  { value: 'ACOES', label: 'Ações atrasadas ou para hoje' },
  ...ETAPAS_CRM.map((e) => ({ value: e.value, label: `${ordemEtapa(e.value)}. ${e.label}` }))
]
const filtrados = computed(() => filtrarProdutores(produtores.value, filtro.value, busca.value, hoje))

// Visualizacao: kanban (padrao) ou lista. Lembrada neste navegador.
type Visao = 'KANBAN' | 'LISTA'
const CHAVE_VISAO = 'crm-visao'
const visao = ref<Visao>('KANBAN')
const opcoesVisao = [
  { value: 'KANBAN', label: 'Kanban' },
  { value: 'LISTA', label: 'Lista' }
]
onMounted(() => {
  try {
    if (localStorage.getItem(CHAVE_VISAO) === 'LISTA') visao.value = 'LISTA'
  } catch {
    // sem armazenamento local: fica no kanban
  }
})
watch(visao, (v) => {
  try {
    localStorage.setItem(CHAVE_VISAO, v)
  } catch {
    // ignora
  }
})

function textoDias(p: ProdutorCrm): string {
  const d = diasNaEtapa(p.etapaDesde)
  if (d === null) return ''
  if (d === 0) return 'nesta etapa desde hoje'
  return d === 1 ? 'há 1 dia nesta etapa' : `há ${d} dias nesta etapa`
}

// Formulario -------------------------------------------------------------------------
const modalAberto = ref(false)
const editandoId = ref<string | null>(null)
const form = ref<FormProdutorCrm>(formVazio())
const erroForm = ref('')
const salvando = ref(false)

const opcoesEtapa = ETAPAS_CRM.map((e) => ({ value: e.value, label: `${ordemEtapa(e.value)}. ${e.label}` }))
const opcoesCasa = computed(() => {
  const usadas = new Set(produtores.value.filter((p) => p.id !== editandoId.value).map((p) => p.organizacaoId))
  return [
    { value: '', label: 'Ainda não tem casa na plataforma' },
    ...casas.value.filter((c) => !usadas.has(c.id)).map((c) => ({ value: c.id, label: `${c.nome} (${c.slug})` }))
  ]
})

function novo() {
  editandoId.value = null
  form.value = { ...formVazio(), ultimoContato: hoje }
  erroForm.value = ''
  modalAberto.value = true
}

function editar(p: ProdutorCrm) {
  editandoId.value = p.id
  form.value = formDoProdutor(p)
  erroForm.value = ''
  modalAberto.value = true
}

async function salvar() {
  erroForm.value = validarFormCrm(form.value)
  if (erroForm.value) return
  salvando.value = true
  try {
    await salvarProdutorCrm(editandoId.value, form.value)
    modalAberto.value = false
    await carregar()
  } catch (e) {
    erroForm.value = e instanceof Error ? e.message : 'Não foi possível salvar.'
  } finally {
    salvando.value = false
  }
}

/** Muda a etapa (kanban, "Mover para" ou botao de avancar); fica no historico. */
async function avancar(p: ProdutorCrm, para: EtapaCrm) {
  erro.value = ''
  const anterior = p.etapa
  p.etapa = para
  try {
    await moverEtapaCrm(p.id, para)
    await carregar()
  } catch (e) {
    p.etapa = anterior
    erro.value = e instanceof Error ? e.message : 'Não foi possível mudar a etapa.'
  }
}

/** Contato registrado no historico: recarrega e mantem o formulario em dia. */
async function aoAlterarHistorico() {
  await carregar()
  const p = produtores.value.find((x) => x.id === editandoId.value)
  if (p) form.value.ultimoContato = p.ultimoContato
}

function proximaEtapa(etapa: EtapaCrm): EtapaCrm | null {
  return ETAPAS_CRM[ordemEtapa(etapa)]?.value ?? null
}

// Excluir ----------------------------------------------------------------------------
const excluindo = ref<ProdutorCrm | null>(null)
const excluindoCarregando = ref(false)

async function confirmarExclusao() {
  if (!excluindo.value) return
  excluindoCarregando.value = true
  try {
    await excluirProdutorCrm(excluindo.value.id)
    excluindo.value = null
    modalAberto.value = false
    await carregar()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível excluir.'
    excluindo.value = null
  } finally {
    excluindoCarregando.value = false
  }
}

// Importar e exportar ---------------------------------------------------------------
const importando = ref(false)

async function importar() {
  importando.value = true
  erro.value = ''
  aviso.value = ''
  try {
    const total = await importarCasasCrm()
    aviso.value = total === 0
      ? 'Todas as casas da plataforma já estão no CRM.'
      : `${total} casa(s) da plataforma entraram no CRM.`
    await carregar()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível importar as casas.'
  } finally {
    importando.value = false
  }
}

function exportar() {
  const blob = new Blob([csvProdutores(filtrados.value)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `crm-ingressoudi-${hoje}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

const corSituacao: Record<string, string> = {
  ATRASADA: 'text-red-300',
  HOJE: 'text-amber-300',
  FUTURA: 'text-zinc-300',
  SEM_DATA: 'text-zinc-500'
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="CRM comercial" subtitle="Produtores em prospecção, funil e indicadores do plano comercial." />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <p
        v-if="erro"
        role="alert"
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        {{ erro }}
      </p>
      <p v-if="aviso" class="rounded-xl border border-amber-400/30 bg-amber-400/10 p-3 text-sm text-amber-200">
        {{ aviso }}
      </p>

      <!-- Indicadores -->
      <BaseCard class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <SegmentedControl v-model="periodo" :options="opcoesPeriodo" :disabled="carregando" />
          <button
            type="button"
            class="inline-flex items-center gap-1.5 text-xs uppercase tracking-wide text-zinc-500 hover:text-zinc-300"
            :disabled="carregando"
            @click="carregar"
          >
            <ArrowPathIcon class="h-4 w-4" :class="carregando ? 'animate-spin' : ''" />
            Atualizar
          </button>
        </div>
        <p class="text-xs text-zinc-500">Indicadores de <strong class="text-zinc-300">{{ rotuloPeriodo }}</strong>.</p>
      </BaseCard>

      <div v-if="resumo" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4" :class="carregando ? 'opacity-60' : ''">
        <DashboardMetricCard
          :icon="MegaphoneIcon"
          label="Produtores contatados"
          :value="formatNumero(resumo.contatados)"
          subtitle="Volume de prospecção"
        />
        <DashboardMetricCard
          :icon="ChatBubbleLeftRightIcon"
          label="Taxa de resposta"
          :value="resumo.taxaResposta === null ? '—' : `${resumo.taxaResposta}%`"
          :subtitle="`${formatNumero(resumo.responderam)} demonstraram interesse`"
        />
        <DashboardMetricCard
          :icon="PresentationChartBarIcon"
          label="Demonstrações realizadas"
          :value="formatNumero(resumo.demonstracoes)"
          subtitle="Interesse comercial"
        />
        <DashboardMetricCard
          :icon="ArrowTrendingUpIcon"
          label="Conversão em produtores ativos"
          :value="resumo.conversaoAtivos === null ? '—' : `${resumo.conversaoAtivos}%`"
          :subtitle="`${formatNumero(resumo.produtoresAtivos)} publicaram evento depois da demonstração`"
        />
        <DashboardMetricCard
          :icon="CalendarDaysIcon"
          label="Eventos publicados"
          :value="formatNumero(resumo.eventosPublicados)"
          subtitle="Pelas casas do CRM"
        />
        <DashboardMetricCard
          :icon="TicketIcon"
          label="Ingressos vendidos"
          :value="formatNumero(resumo.ingressosVendidos)"
          :subtitle="`${formatMoeda(indicadores?.negocio.valorVendido ?? 0)} vendidos`"
        />
        <DashboardMetricCard
          :icon="BanknotesIcon"
          label="Receita líquida da plataforma"
          :value="formatMoeda(resumo.receitaLiquida)"
          subtitle="Taxas das vendas online"
          value-class="text-amber-300"
        />
        <DashboardMetricCard
          :icon="ClockIcon"
          label="Próximas ações"
          :value="formatNumero((indicadores?.acoes.atrasadas ?? 0) + (indicadores?.acoes.hoje ?? 0))"
          :subtitle="`${formatNumero(indicadores?.acoes.atrasadas ?? 0)} atrasada(s) · ${formatNumero(indicadores?.acoes.hoje ?? 0)} para hoje`"
          :value-class="(indicadores?.acoes.atrasadas ?? 0) > 0 ? 'text-red-300' : 'text-white'"
        />
      </div>

      <!-- Produtores -->
      <BaseCard :padded="false" class="overflow-hidden">
        <div class="space-y-3 px-5 pt-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-sm font-semibold text-white">Produtores ({{ filtrados.length }} de {{ produtores.length }})</h2>
            <div class="flex flex-wrap gap-2">
              <AppButton size="sm" variant="primary" @click="novo">
                <PlusIcon class="h-4 w-4" />
                Novo produtor
              </AppButton>
              <AppButton size="sm" variant="outline" :disabled="importando" @click="importar">
                {{ importando ? 'Importando...' : 'Importar casas da plataforma' }}
              </AppButton>
              <AppButton size="sm" variant="ghost" :disabled="filtrados.length === 0" @click="exportar">
                <ArrowDownTrayIcon class="h-4 w-4" />
                Planilha
              </AppButton>
            </div>
          </div>
          <SegmentedControl v-model="visao" :options="opcoesVisao" />
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <BaseSelect v-model="filtro" :options="opcoesFiltro" />
            <label class="relative block">
              <MagnifyingGlassIcon class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500" />
              <input
                v-model="busca"
                type="search"
                placeholder="Buscar nome, evento, cidade..."
                class="w-full rounded-lg border border-zinc-700 bg-zinc-950 py-2.5 pl-9 pr-3 text-sm text-white placeholder:text-zinc-600 focus:border-amber-400 focus:outline-none"
              >
            </label>
          </div>
        </div>

        <p v-if="!carregando && produtores.length === 0" class="p-5 text-sm text-zinc-500">
          Nenhum produtor ainda. Cadastre o primeiro ou importe as casas que já estão na plataforma.
        </p>
        <p v-else-if="filtrados.length === 0" class="p-5 text-sm text-zinc-500">Nenhum produtor neste filtro.</p>

        <div v-else-if="visao === 'KANBAN'" class="mt-4 px-5 pb-5">
          <CrmKanban :produtores="filtrados" :hoje="hoje" @abrir="editar" @mover="avancar" />
        </div>

        <ul v-else class="mt-4 divide-y divide-zinc-800">
          <li v-for="p in filtrados" :key="p.id" class="flex flex-col gap-3 px-5 py-4 lg:flex-row lg:items-start">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <button type="button" class="truncate text-left font-semibold text-white hover:text-amber-400" @click="editar(p)">
                  {{ p.nomeProdutor }}
                </button>
                <span class="rounded-full border border-amber-400/30 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300">
                  {{ ordemEtapa(p.etapa) }}. {{ rotuloEtapa(p.etapa) }}
                </span>
              </div>
              <p class="mt-0.5 truncate text-xs text-zinc-500">
                {{ [p.empresaEvento, p.tipoEvento, p.cidade].filter(Boolean).join(' · ') || 'Sem detalhes' }}
              </p>
              <p class="mt-2 text-xs" :class="corSituacao[situacaoAcao(p.proximaAcaoEm, hoje)]">
                <template v-if="p.proximaAcao || p.proximaAcaoEm">
                  Próxima ação: {{ p.proximaAcao || 'sem descrição' }}
                  <template v-if="p.proximaAcaoEm">
                    em {{ formatarDiaIso(p.proximaAcaoEm) }}
                    <template v-if="situacaoAcao(p.proximaAcaoEm, hoje) === 'ATRASADA'">(atrasada)</template>
                    <template v-else-if="situacaoAcao(p.proximaAcaoEm, hoje) === 'HOJE'">(hoje)</template>
                  </template>
                </template>
                <template v-else>Sem próxima ação definida</template>
              </p>
              <p class="mt-0.5 text-xs text-zinc-600">
                <span :class="leadEsfriando(p) ? 'text-sky-300' : ''">{{ textoDias(p) }}</span>
                · Último contato: {{ p.ultimoContato ? formatarDiaIso(p.ultimoContato) : '—' }}
                <template v-if="p.totalContatos"> · {{ p.totalContatos }} contato(s)</template>
                <template v-if="p.organizacaoNome"> · Casa: {{ p.organizacaoNome }}</template>
              </p>
              <div class="mt-2 flex flex-wrap gap-3 text-xs">
                <a v-if="linkWhatsapp(p.whatsapp)" :href="linkWhatsapp(p.whatsapp)" target="_blank" rel="noopener" class="text-emerald-300 hover:underline">
                  WhatsApp {{ p.whatsapp }}
                </a>
                <a v-if="linkInstagram(p.instagram)" :href="linkInstagram(p.instagram)" target="_blank" rel="noopener" class="text-pink-300 hover:underline">
                  Instagram {{ p.instagram }}
                </a>
              </div>
            </div>

            <div class="flex flex-col gap-3 lg:w-[22rem] lg:shrink-0">
              <div class="grid grid-cols-3 gap-3 text-xs">
                <div>
                  <p class="text-zinc-500">Eventos</p>
                  <p class="text-sm font-semibold text-white">{{ formatNumero(p.eventosPublicados) }}</p>
                </div>
                <div>
                  <p class="text-zinc-500">Ingressos</p>
                  <p class="text-sm font-semibold text-white">{{ formatNumero(p.ingressosVendidos) }}</p>
                </div>
                <div>
                  <p class="text-zinc-500">Receita gerada</p>
                  <p class="text-sm font-semibold text-white">{{ formatMoeda(p.receitaGerada) }}</p>
                </div>
              </div>
              <div class="flex flex-wrap gap-2">
                <AppButton
                  v-if="sugestaoAvanco(p)"
                  size="sm"
                  variant="outlineAccent"
                  @click="avancar(p, sugestaoAvanco(p)!)"
                >
                  <ChevronDoubleRightIcon class="h-4 w-4" />
                  {{ rotuloEtapa(sugestaoAvanco(p)!) }}
                </AppButton>
                <AppButton
                  v-else-if="proximaEtapa(p.etapa)"
                  size="sm"
                  variant="outline"
                  @click="avancar(p, proximaEtapa(p.etapa)!)"
                >
                  <ChevronDoubleRightIcon class="h-4 w-4" />
                  {{ rotuloEtapa(proximaEtapa(p.etapa)!) }}
                </AppButton>
                <AppButton size="sm" variant="ghost" @click="editar(p)">
                  <PencilSquareIcon class="h-4 w-4" />
                  Editar
                </AppButton>
              </div>
            </div>
          </li>
        </ul>
      </BaseCard>

      <p class="text-xs leading-relaxed text-zinc-500">
        No kanban, arraste o cartão para outra coluna ou use "Mover para". Leads em azul estão há 7 dias ou mais na mesma etapa.
        Nos indicadores, pular etapas conta as anteriores. Eventos, ingressos e receita vêm dos dados reais da casa ligada ao produtor;
        sem casa, ficam em zero. Receita gerada é o total vendido pelo produtor; a receita líquida da plataforma são as taxas
        das vendas online.
      </p>
    </template>

    <!-- Formulario -->
    <BaseModal
      :open="modalAberto"
      :title="editandoId ? 'Editar produtor' : 'Novo produtor'"
      size="lg"
      @close="modalAberto = false"
    >
      <form id="form-crm" class="grid grid-cols-1 gap-4 sm:grid-cols-2" @submit.prevent="salvar">
        <BaseInput v-model="form.nomeProdutor" label="Nome do produtor" required />
        <BaseInput v-model="form.empresaEvento" label="Empresa ou evento" />
        <BaseInput v-model="form.instagram" label="Instagram" placeholder="@perfil" />
        <BaseInput v-model="form.whatsapp" label="WhatsApp" type="tel" placeholder="(34) 99999-9999" />
        <BaseInput v-model="form.cidade" label="Cidade" placeholder="Uberlândia" />
        <BaseInput v-model="form.tipoEvento" label="Tipo de evento" placeholder="Festa universitária" />
        <BaseSelect v-model="form.etapa" :options="opcoesEtapa" label="Etapa comercial" />
        <BaseInput v-model="form.ultimoContato" label="Último contato" type="date" />
        <BaseInput v-model="form.proximaAcao" label="Próxima ação" placeholder="Agendar demonstração" />
        <BaseInput v-model="form.proximaAcaoEm" label="Data da próxima ação" type="date" />
        <div class="sm:col-span-2">
          <BaseSelect v-model="form.organizacaoId" :options="opcoesCasa" label="Casa na plataforma" />
          <p class="mt-1 text-xs text-zinc-500">Ligue quando o produtor criar a casa: eventos, ingressos e receita passam a vir dela.</p>
        </div>
        <div class="sm:col-span-2">
          <BaseTextarea v-model="form.observacoes" label="Observações" :rows="3" :maxlength="4000" />
        </div>
        <p v-if="erroForm" role="alert" class="text-sm text-red-300 sm:col-span-2">{{ erroForm }}</p>
      </form>

      <div v-if="editandoId" class="mt-6 border-t border-zinc-800 pt-5">
        <CrmLeadHistorico :produtor-id="editandoId" :hoje="hoje" @alterado="aoAlterarHistorico" />
      </div>

      <template #footer>
        <div class="flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
          <AppButton
            v-if="editandoId"
            variant="ghost"
            :disabled="salvando"
            @click="excluindo = produtores.find((p) => p.id === editandoId) ?? null"
          >
            <TrashIcon class="h-4 w-4" />
            Excluir
          </AppButton>
          <span v-else />
          <div class="flex flex-col-reverse gap-3 sm:flex-row">
            <AppButton variant="ghost" :disabled="salvando" @click="modalAberto = false">Cancelar</AppButton>
            <AppButton variant="primary" type="submit" form="form-crm" :disabled="salvando">
              {{ salvando ? 'Salvando...' : 'Salvar' }}
            </AppButton>
          </div>
        </div>
      </template>
    </BaseModal>

    <ConfirmDialog
      :open="excluindo !== null"
      title="Excluir produtor do CRM?"
      :description="`${excluindo?.nomeProdutor ?? ''} e o histórico de etapas saem do CRM. A casa na plataforma não é afetada.`"
      confirm-label="Excluir"
      tone="danger"
      :loading="excluindoCarregando"
      @confirm="confirmarExclusao"
      @cancel="excluindo = null"
    />
  </div>
</template>
