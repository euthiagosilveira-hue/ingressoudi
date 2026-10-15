<script setup lang="ts">
import LegalPage from '~/components/public/LegalPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `Termos de uso | ${PLATAFORMA_NOME}`,
  description: `Termos de uso da plataforma ${PLATAFORMA_NOME} para compradores e organizadores de eventos.`
})
</script>

<template>
  <LegalPage titulo="Termos de uso">
    <p>
      Estes Termos regulam o uso do {{ PLATAFORMA_NOME }} ("Plataforma") por quem compra ingressos ("Comprador") e por
      produtores e casas de eventos que vendem ingressos por meio dela ("Organizador"). Ao comprar um ingresso ou criar
      uma conta, você concorda com estes Termos e com a
      <NuxtLink to="/privacidade" class="text-amber-400 hover:text-amber-300">Política de privacidade</NuxtLink>.
    </p>

    <h2>1. O que é a Plataforma</h2>
    <p>
      O {{ PLATAFORMA_NOME }} é uma ferramenta tecnológica que permite ao Organizador divulgar eventos, vender
      ingressos online, gerenciar listas e controlar a entrada com QR Code. A Plataforma não é organizadora, promotora
      nem responsável pela realização dos eventos anunciados.
    </p>

    <h2>2. Cadastro do Organizador</h2>
    <ul>
      <li>O Organizador deve informar dados verdadeiros e mantê-los atualizados.</li>
      <li>
        Novos cadastros passam por análise. A Plataforma pode aprovar, recusar ou suspender casas que descumpram estes
        Termos ou a legislação.
      </li>
      <li>
        O Organizador é responsável pelo acesso da própria equipe (administradores e portaria) e pelas ações realizadas
        com as suas credenciais.
      </li>
    </ul>

    <h2>3. Responsabilidades do Organizador</h2>
    <ul>
      <li>Realizar o evento conforme anunciado (data, local, atrações e capacidade).</li>
      <li>Obter licenças e autorizações exigidas e cumprir as normas de segurança e acessibilidade.</li>
      <li>Respeitar a legislação de meia-entrada e de defesa do consumidor.</li>
      <li>Atender os Compradores e tratar pedidos de cancelamento, troca e reembolso.</li>
      <li>Utilizar os dados dos Compradores apenas para a gestão do evento, conforme a Política de privacidade.</li>
    </ul>

    <h2>4. Pagamentos e taxa de serviço</h2>
    <ul>
      <li>
        Os pagamentos são processados pelo Mercado Pago e creditados diretamente na conta do Organizador. A Plataforma não
        armazena dados de cartão ou de conta bancária.
      </li>
      <li>
        A Plataforma cobra uma taxa de serviço por ingresso vendido online. O Organizador escolhe se a taxa é repassada ao
        Comprador (exibida antes do pagamento) ou absorvida por ele.
      </li>
      <li>O ingresso só é emitido após a confirmação do pagamento.</li>
    </ul>

    <h2>5. Ingressos e entrada no evento</h2>
    <ul>
      <li>Cada ingresso possui um QR Code único, válido para uma única entrada.</li>
      <li>
        Não compartilhe o QR Code: a primeira leitura na portaria registra a entrada e as demais são recusadas.
      </li>
      <li>Os nomes dos participantes não podem ser alterados após a confirmação do pagamento.</li>
      <li>O Organizador pode exigir documento com foto na entrada.</li>
    </ul>

    <h2>6. Cancelamento e reembolso</h2>
    <p>
      O reembolso segue a
      <NuxtLink to="/reembolso" class="text-amber-400 hover:text-amber-300">Política de reembolso</NuxtLink>: desistência em
      até 7 dias após a compra e até 48 horas antes do evento, com devolução integral (ingressos e taxa de serviço), e
      reembolso integral em caso de cancelamento ou alteração relevante do evento. Os pedidos são feitos ao Organizador,
      que os executa pelo painel da Plataforma.
    </p>

    <h2>7. Condutas proibidas</h2>
    <ul>
      <li>Usar a Plataforma para fraudes, eventos ilícitos ou anúncios enganosos.</li>
      <li>Falsificar, duplicar ou revender ingressos de forma irregular.</li>
      <li>Tentar acessar dados de outras casas ou burlar mecanismos de segurança.</li>
    </ul>

    <h2>8. Limitação de responsabilidade</h2>
    <p>
      A Plataforma se empenha para manter o serviço disponível e seguro, mas não responde pela realização, qualidade ou
      segurança dos eventos, nem por falhas de serviços de terceiros (como meios de pagamento e operadoras de internet).
    </p>

    <h2>9. Alterações</h2>
    <p>
      Estes Termos podem ser atualizados. A versão vigente fica sempre disponível nesta página; mudanças relevantes serão
      comunicadas aos Organizadores.
    </p>
  </LegalPage>
</template>
