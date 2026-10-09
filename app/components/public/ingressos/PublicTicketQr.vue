<script setup lang="ts">
import QrcodeVue from 'qrcode.vue'

const props = defineProps<{
  value: string
}>()
</script>

<template>
  <div class="mx-auto w-full max-w-xs rounded-2xl bg-white p-4">
    <QrcodeVue
      :value="props.value"
      :size="240"
      :margin="4"
      level="M"
      render-as="svg"
      class="mx-auto block h-auto w-full"
    />
  </div>
</template>
