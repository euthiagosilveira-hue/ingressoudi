<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import { ClipboardDocumentIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import EventImageUploader from '~/components/eventos/EventImageUploader.vue'
import { atualizarMarcaOrganizacao, obterMarcaOrganizacao, type MarcaOrganizacao } from '~/services/admin/marca'
import { COR_PADRAO, corTextoContraste, normalizarCor } from '~/utils/marca'
import { urlPublicaAbsoluta } from '~/utils/rotasPublicas'

definePageMeta({
  title: 'Página pública',
  description: 'Logo, cor e link da página de eventos da sua casa.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth']
})

const config = useRuntimeConfig()

const carregando = ref(true)
const salvando = ref(false)
const erro = ref('')
const marca = ref<MarcaOrganizacao | null>(null)
const logoUrl = ref<string | null>(null)
const cor = ref(COR_PADRAO)

const corValida = computed(() => normalizarCor(cor.value))
const corPreview = computed(() => corValida.value ?? COR_PADRAO)
const textoPreview = computed(() => corTextoContraste(corPreview.value))

const caminhoPublico = computed(() => (marca.value ? `/${marca.value.slug}` : ''))
const linkCompleto = computed(() => {
  const base = String(config.public.siteUrl || (import.meta.client ? window.location.origin : ''))
  return urlPublicaAbsoluta(base, caminhoPublico.value)
})

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    marca.value = await obterMarcaOrganizacao()
    logoUrl.value = marca.value.logoUrl
    cor.value = marca.value.corPrimaria ?? COR_PADRAO
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar.'
  } finally {
    carregando.value = false
  }
}

async function salvar() {
  if (!corValida.value) {
    toast.error('Cor inválida. Use o formato #RRGGBB.')
    return
  }
  salvando.value = true
  try {
    marca.value = await atualizarMarcaOrganizacao(logoUrl.value, corValida.value)
    toast.success('Página pública atualizada.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar.')
  } finally {
    salvando.value = false
  }
}

async function copiarLink() {
  try {
    await navigator.clipboard.writeText(linkCompleto.value)
    toast.success('Link copiado.')
  } catch {
    toast.error('Não foi possível copiar. Selecione o link e copie manualmente.')
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Página pública" subtitle="Como sua casa aparece para quem compra ingressos.">
      <template #actions>
        <AppButton to="/configuracoes" size="sm">Voltar</AppButton>
      </template>
    </PageHeader>

    <div v-if="carregando" class="h-40 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />

    <BaseCard v-else-if="erro">
      <p class="text-sm text-red-300">{{ erro }}</p>
      <AppButton class="mt-3" size="sm" @click="carregar">Tentar novamente</AppButton>
    </BaseCard>

    <template v-else-if="marca">
      <BaseCard>
        <h2 class="text-sm font-semibold text-white">Link da sua página</h2>
        <p class="mt-1 text-xs text-zinc-500">Divulgue este link nas redes sociais e no WhatsApp.</p>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <code class="min-w-0 flex-1 truncate rounded-lg border border-zinc-700 bg-zinc-950 px-3.5 py-2.5 text-sm text-zinc-300">
            {{ linkCompleto }}
          </code>
          <AppButton size="sm" @click="copiarLink">
            <ClipboardDocumentIcon class="h-4 w-4" />
            Copiar
          </AppButton>
          <AppButton size="sm" variant="ghost" :to="caminhoPublico">Abrir</AppButton>
        </div>
      </BaseCard>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <BaseCard>
          <h2 class="text-sm font-semibold text-white">Logo</h2>
          <p class="mt-1 text-xs text-zinc-500">Aparece no topo da sua página. Sem logo, mostramos o nome da casa.</p>
          <div class="mt-4">
            <EventImageUploader
              v-model="logoUrl"
              recomendacao="Recomendado: PNG com fundo transparente, formato horizontal (ex.: 600×200px)."
            />
          </div>
        </BaseCard>

        <BaseCard>
          <h2 class="text-sm font-semibold text-white">Cor de destaque</h2>
          <p class="mt-1 text-xs text-zinc-500">Usada na faixa do topo, no preço e no botão de comprar.</p>
          <div class="mt-4 flex items-center gap-3">
            <input v-model="cor" type="color" class="h-11 w-16 cursor-pointer rounded-lg border border-zinc-700 bg-zinc-950 p-1" aria-label="Escolher cor" />
            <input
              v-model="cor"
              type="text"
              maxlength="7"
              class="w-32 rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2.5 text-sm text-white focus:border-amber-400/60 focus:outline-none"
              aria-label="Código da cor"
            />
          </div>

          <p class="mt-6 text-xs uppercase tracking-wide text-zinc-500">Prévia</p>
          <div class="mt-2 overflow-hidden rounded-xl border border-zinc-800 bg-black">
            <div class="h-1 w-full" :style="{ background: corPreview }" />
            <div class="flex items-center justify-between gap-3 px-4 py-3">
              <img v-if="logoUrl" :src="logoUrl" :alt="marca.nome" class="h-7 w-auto" />
              <span v-else class="truncate font-bold text-white">{{ marca.nome }}</span>
              <span class="rounded-lg px-3 py-1.5 text-xs font-bold uppercase" :style="{ background: corPreview, color: textoPreview }">
                Comprar ingresso
              </span>
            </div>
          </div>
        </BaseCard>
      </div>

      <div class="flex justify-end">
        <AppButton variant="primary" :disabled="salvando" @click="salvar">
          {{ salvando ? 'Salvando...' : 'Salvar página pública' }}
        </AppButton>
      </div>
    </template>
  </div>
</template>
