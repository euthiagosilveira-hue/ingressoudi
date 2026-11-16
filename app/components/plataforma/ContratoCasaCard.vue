<script setup lang="ts">
import { onMounted, ref } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatDataHoraCompleta } from '~/utils/format'
import { formatarDocumento, formatarTelefone } from '~/utils/documento'

/** Super admin: documento, telefone e historico de aceites do Contrato do Organizador. */
const props = defineProps<{ organizacaoId: string }>()

interface Aceite {
  versao: string
  aceito_em: string
  ip: string | null
  user_agent: string | null
  usuario_nome: string
  usuario_email: string
}
interface ContratoCasa {
  tipo_documento: 'CPF' | 'CNPJ' | null
  documento: string | null
  responsavel_nome: string | null
  telefone: string | null
  contrato_exigido: boolean
  contrato_pendente: boolean
  versao_vigente: string
  aceites: Aceite[]
}

const client = useSupabaseClient()
const dados = ref<ContratoCasa | null>(null)
const erro = ref('')

onMounted(async () => {
  const { data, error } = await client.rpc('obter_contrato_organizacao_plataforma', {
    p_organizacao_id: props.organizacaoId
  })
  if (error) erro.value = 'Não foi possível carregar o contrato desta casa.'
  else dados.value = data as ContratoCasa
})
</script>

<template>
  <BaseCard>
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold text-white">Organizador e contrato</h2>
      <span
        v-if="dados"
        class="rounded-full px-2.5 py-0.5 text-xs font-semibold"
        :class="dados.contrato_pendente ? 'bg-amber-400/15 text-amber-300' : 'bg-emerald-500/15 text-emerald-300'"
      >
        {{ dados.contrato_pendente ? 'Contrato pendente' : `Contrato ${dados.versao_vigente} aceito` }}
      </span>
    </div>
    <p v-if="erro" class="mt-3 text-sm text-red-300">{{ erro }}</p>
    <template v-else-if="dados">
      <dl class="mt-3 grid grid-cols-1 gap-x-6 gap-y-1.5 text-xs sm:grid-cols-3">
        <div>
          <dt class="text-zinc-500">{{ dados.tipo_documento ?? 'Documento' }}</dt>
          <dd class="text-zinc-300">
            {{ dados.documento ? formatarDocumento(dados.tipo_documento, dados.documento) : 'Não informado' }}
          </dd>
        </div>
        <div>
          <dt class="text-zinc-500">{{ dados.tipo_documento === 'CNPJ' ? 'Razão social' : 'Nome completo' }}</dt>
          <dd class="text-zinc-300">{{ dados.responsavel_nome || 'Não informado' }}</dd>
        </div>
        <div>
          <dt class="text-zinc-500">Telefone</dt>
          <dd class="text-zinc-300">
            <a
              v-if="dados.telefone"
              :href="`https://wa.me/55${dados.telefone}`"
              target="_blank"
              rel="noopener"
              class="text-amber-300 hover:underline"
            >{{ formatarTelefone(dados.telefone) }}</a>
            <span v-else>Não informado</span>
          </dd>
        </div>
      </dl>

      <h3 class="mt-5 text-xs font-semibold uppercase tracking-wide text-zinc-500">Aceites registrados</h3>
      <p v-if="!dados.aceites.length" class="mt-2 text-xs text-zinc-500">Nenhum aceite ainda.</p>
      <ul v-else class="mt-2 divide-y divide-zinc-800 text-xs">
        <li v-for="a in dados.aceites" :key="a.aceito_em" class="py-2">
          <p class="text-zinc-300">
            Versão {{ a.versao }} em {{ formatDataHoraCompleta(a.aceito_em) }} por
            {{ a.usuario_nome || a.usuario_email }}
            <span class="text-zinc-500">({{ a.usuario_email }})</span>
          </p>
          <p class="mt-0.5 break-all text-zinc-500">IP {{ a.ip ?? '—' }} · {{ a.user_agent ?? 'navegador não informado' }}</p>
        </li>
      </ul>
    </template>
    <div v-else class="mt-3 h-16 animate-pulse rounded-xl bg-zinc-900" />
  </BaseCard>
</template>
