-- =============================================================================
-- Ingressoudi - Expiracao automatica de reservas (Pix abandonados)
--
-- Ate aqui a reserva so era expirada quando a pagina de pagamento do comprador
-- consultava o status depois do prazo. Se o comprador fechava a pagina, o
-- pedido ficava RESERVADO e o pagamento PENDENTE para sempre (o estoque ja
-- ignorava a reserva vencida; era so o status que ficava errado).
--
-- Agenda private.processar_reservas_expiradas(null) uma vez por dia, as 23h55
-- de Brasilia (02h55 UTC; o pg_cron usa UTC). Roda dentro do Supabase, sem
-- chamar a Vercel. A funcao ja existe e so expira pedidos RESERVADO com o prazo
-- vencido; pagamento aprovado depois do prazo continua aceito.
-- =============================================================================

create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'ingressoudi-expirar-reservas';
  perform cron.schedule(
    'ingressoudi-expirar-reservas',
    '55 2 * * *',
    'select private.processar_reservas_expiradas(null)'
  );
end
$$;
