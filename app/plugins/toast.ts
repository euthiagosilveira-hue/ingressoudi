import 'vue3-toastify/dist/index.css'
import vue3Toasty from 'vue3-toastify'

export default defineNuxtPlugin((nuxtApp) => {
  nuxtApp.vueApp.use(vue3Toasty, {
    position: 'top-right',
    timeout: 3000,
    autoClose: 3000,
    clearOnNavigate: false
  })
})
