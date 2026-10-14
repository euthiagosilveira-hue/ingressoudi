<script setup lang="ts">
import LegalPage from '~/components/public/LegalPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `Política de privacidade | ${PLATAFORMA_NOME}`,
  description: `Como o ${PLATAFORMA_NOME} trata dados pessoais de compradores e organizadores, conforme a LGPD.`
})
</script>

<template>
  <LegalPage titulo="Política de privacidade">
    <p>
      Esta Política explica como o {{ PLATAFORMA_NOME }} ("Plataforma") e os produtores e casas de eventos que a utilizam
      ("Organizadores") tratam dados pessoais, de acordo com a Lei Geral de Proteção de Dados (Lei nº 13.709/2018 — LGPD).
    </p>

    <h2>1. Quem trata os seus dados</h2>
    <p>
      Ao comprar um ingresso, seus dados são tratados pelo Organizador do evento, para a venda e o controle de entrada,
      e pela Plataforma, que fornece a tecnologia e a mantém segura.
    </p>

    <h2>2. Dados coletados</h2>
    <ul>
      <li><strong>Compradores:</strong> nome, e-mail, telefone e nomes dos participantes informados no pedido.</li>
      <li><strong>Pedidos e entrada:</strong> evento, ingressos, valores, status do pagamento e data/hora da validação na portaria.</li>
      <li>
        <strong>Organizadores e equipe:</strong> nome, e-mail, dados da casa e registros de acesso e de ações no painel.
      </li>
      <li>
        <strong>Pagamento:</strong> processado pelo Mercado Pago. A Plataforma recebe apenas o identificador e o status
        do pagamento — nunca dados de cartão ou de conta bancária.
      </li>
    </ul>

    <h2>3. Para que usamos</h2>
    <ul>
      <li>Emitir os ingressos, enviar o acesso a eles e permitir a recuperação pelo número do pedido e telefone.</li>
      <li>Validar a entrada no evento e evitar o uso duplicado de ingressos.</li>
      <li>Confirmar pagamentos, calcular repasses e taxas e cumprir obrigações legais e fiscais.</li>
      <li>Garantir a segurança da Plataforma e prevenir fraudes.</li>
    </ul>
    <p>
      As bases legais são a execução do contrato de compra, o cumprimento de obrigação legal e o legítimo interesse em
      segurança e prevenção a fraudes. Não vendemos dados pessoais.
    </p>

    <h2>4. Compartilhamento</h2>
    <ul>
      <li>Com o Organizador do evento do qual você comprou o ingresso.</li>
      <li>Com o Mercado Pago, para processar o pagamento.</li>
      <li>
        Com provedores de hospedagem e banco de dados que operam a Plataforma, que podem armazenar dados fora do Brasil
        com garantias adequadas de proteção.
      </li>
      <li>Com autoridades, quando exigido por lei ou ordem judicial.</li>
    </ul>

    <h2>5. Cookies</h2>
    <p>
      Usamos apenas cookies e armazenamento local essenciais para o login e o funcionamento da compra. Não usamos cookies
      de publicidade.
    </p>

    <h2>6. Por quanto tempo guardamos</h2>
    <p>
      Pelo tempo necessário para as finalidades acima e para cumprir prazos legais (por exemplo, fiscais e de defesa do
      consumidor). Depois disso, os dados são excluídos ou anonimizados.
    </p>

    <h2>7. Seus direitos</h2>
    <p>
      Você pode pedir a confirmação do tratamento, o acesso, a correção, a anonimização ou a eliminação de dados
      desnecessários, a portabilidade, informações sobre compartilhamento e a revisão do consentimento, nos termos do
      art. 18 da LGPD. Pedidos sobre um evento específico podem ser feitos ao Organizador ou à Plataforma.
    </p>

    <h2>8. Segurança</h2>
    <p>
      Os dados ficam em ambiente com acesso restrito e controle de permissões por casa: cada Organizador acessa apenas os
      dados dos próprios eventos.
    </p>
  </LegalPage>
</template>
