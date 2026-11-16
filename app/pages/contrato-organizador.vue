<script setup lang="ts">
import LegalPage from '~/components/public/LegalPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { CONTRATO_ORGANIZADOR_VERSAO } from '~/utils/contratoOrganizador'
import { PLATAFORMA_NOME } from '~/utils/marca'

/*
 * Contrato do Organizador. Ao mudar este texto, troque
 * CONTRATO_ORGANIZADOR_VERSAO (app/utils/contratoOrganizador.ts) e
 * private.contrato_organizador_versao() no banco: todas as casas aceitam de novo.
 */

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `Contrato do Organizador | ${PLATAFORMA_NOME}`,
  description: `Contrato entre a plataforma ${PLATAFORMA_NOME} e os produtores e casas de eventos que vendem ingressos por ela.`
})
</script>

<template>
  <LegalPage titulo="Contrato do Organizador" :versao="CONTRATO_ORGANIZADOR_VERSAO" atualizado-em="novembro de 2026">
    <p>
      Este Contrato regula a relação entre o {{ PLATAFORMA_NOME }} ("Plataforma") e o produtor, casa de eventos ou
      empresa que cria uma conta para vender ingressos por meio dela ("Organizador"), identificado pelo nome, CPF ou
      CNPJ e telefone informados no painel. Ele complementa os
      <NuxtLink to="/termos" class="text-amber-400 hover:text-amber-300">Termos de uso</NuxtLink>, a
      <NuxtLink to="/privacidade" class="text-amber-400 hover:text-amber-300">Política de privacidade</NuxtLink> e a
      <NuxtLink to="/reembolso" class="text-amber-400 hover:text-amber-300">Política de reembolso</NuxtLink>. Em caso de
      conflito entre eles nas relações entre Plataforma e Organizador, vale este Contrato.
    </p>

    <h2>1. Objeto</h2>
    <p>
      A Plataforma fornece ao Organizador a tecnologia para divulgar eventos, vender ingressos online (Pix e cartão, por
      meio do Mercado Pago), registrar vendas manuais, gerenciar listas e controlar a entrada com QR Code. O Organizador
      é quem realiza o evento e vende os ingressos ao público.
    </p>

    <h2>2. Cadastro e dados do Organizador</h2>
    <ul>
      <li>
        O Organizador declara que os dados informados (nome completo ou razão social, CPF ou CNPJ e telefone) são
        verdadeiros e se obriga a mantê-los atualizados.
      </li>
      <li>
        Quem aceita este Contrato declara ter poderes para representar o Organizador e se obriga solidariamente pelas
        obrigações de reembolso e ressarcimento previstas aqui.
      </li>
      <li>
        O nome e o documento do Organizador são exibidos aos compradores na página do evento (o CPF de forma parcial).
      </li>
      <li>O Organizador responde pelos acessos da sua equipe e pelas ações feitas com as credenciais dela.</li>
    </ul>

    <h2>3. Responsabilidade pelo evento</h2>
    <ul>
      <li>
        O Organizador é o único fornecedor do evento e o destinatário do valor dos ingressos. Cabe a ele realizar o
        evento conforme anunciado (data, local, atrações e capacidade).
      </li>
      <li>
        O Organizador deve obter as licenças e autorizações exigidas e cumprir as normas de segurança, acessibilidade,
        meia-entrada e defesa do consumidor.
      </li>
      <li>
        Cancelamento, adiamento ou alteração relevante devem ser informados aos compradores e à Plataforma assim que
        decididos, e registrados no painel.
      </li>
    </ul>

    <h2>4. Reembolso aos compradores</h2>
    <ul>
      <li>
        Em caso de cancelamento, adiamento sem aceite do comprador ou alteração relevante do evento, o Organizador deve
        reembolsar integralmente os compradores, incluindo a taxa de serviço, em até 5 (cinco) dias úteis contados do
        cancelamento ou do pedido.
      </li>
      <li>
        Os pedidos de desistência dentro do prazo legal seguem a
        <NuxtLink to="/reembolso" class="text-amber-400 hover:text-amber-300">Política de reembolso</NuxtLink>.
      </li>
      <li>
        O Organizador se obriga a manter na sua conta Mercado Pago saldo suficiente para os reembolsos dos eventos ainda
        não realizados, ou a devolver os valores por outro meio no mesmo prazo.
      </li>
    </ul>

    <h2>5. Autorizações à Plataforma</h2>
    <p>
      O Organizador autoriza a Plataforma, de forma irrevogável enquanto houver vendas de eventos ainda não realizados,
      a:
    </p>
    <ul>
      <li>suspender as vendas e cancelar o evento quando houver indício de que ele não ocorrerá;</li>
      <li>
        executar os reembolsos em nome do Organizador, por meio da integração com o Mercado Pago, sempre que ele não o
        fizer no prazo;
      </li>
      <li>comunicar os compradores sobre o cancelamento e os seus direitos.</li>
    </ul>

    <h2>6. Ressarcimento, multa e compensação</h2>
    <ul>
      <li>
        Se a Plataforma for cobrada, condenada ou decidir reembolsar compradores por fato do Organizador, este deve
        ressarcir integralmente a Plataforma, com correção monetária, juros de 1% ao mês, custas e honorários
        advocatícios de 20%, em até 5 (cinco) dias úteis da notificação.
      </li>
      <li>
        O Organizador deve assumir a defesa, ou indenizar a Plataforma pelos custos dela, em reclamações no Procon, no
        consumidor.gov.br e em ações judiciais relativas aos seus eventos.
      </li>
      <li>
        O descumprimento do dever de reembolso sujeita o Organizador a multa de 20% sobre o total não reembolsado, sem
        prejuízo das perdas e danos.
      </li>
      <li>
        A Plataforma pode compensar valores devidos pelo Organizador com quaisquer valores que tenha a repassar a ele,
        inclusive de outros eventos.
      </li>
    </ul>

    <h2>7. Pagamentos, taxa de serviço e garantias</h2>
    <ul>
      <li>
        Os pagamentos online são processados pelo Mercado Pago e creditados na conta do Organizador conectada ao painel.
        A Plataforma recebe a taxa de serviço por ingresso vendido online, informada no painel.
      </li>
      <li>
        Conforme o histórico da casa e o volume de vendas, a Plataforma pode exigir garantias, como retenção de parte das
        vendas até a realização do evento, caução, fiança dos sócios ou limite de vendas antecipadas.
      </li>
    </ul>

    <h2>8. Dados dos compradores</h2>
    <p>
      O Organizador usa os dados dos compradores apenas para a gestão dos seus eventos, conforme a Lei Geral de Proteção
      de Dados e a Política de privacidade, e não os repassa a terceiros sem base legal.
    </p>

    <h2>9. Suspensão e encerramento</h2>
    <ul>
      <li>
        Em caso de descumprimento, a Plataforma pode suspender a conta da casa, suspender vendas, reter repasses que
        dependam dela e fornecer aos compradores e às autoridades os dados de identificação do Organizador.
      </li>
      <li>
        O Organizador pode encerrar a conta a qualquer momento, desde que não haja eventos com vendas ainda não
        realizados ou reembolsos pendentes.
      </li>
    </ul>

    <h2>10. Aceite eletrônico e alterações</h2>
    <p>
      O aceite deste Contrato é feito no painel e registrado com a versão, a data, a hora, o IP e o navegador de quem
      aceitou. Quando o Contrato for alterado, a nova versão será apresentada no painel e precisará ser aceita para
      continuar usando a Plataforma.
    </p>

    <h2>11. Foro</h2>
    <p>
      Fica eleito o foro da comarca de Uberlândia/MG para as disputas entre a Plataforma e o Organizador, ressalvadas as
      regras de competência do Código de Defesa do Consumidor nas relações com os compradores.
    </p>
  </LegalPage>
</template>
