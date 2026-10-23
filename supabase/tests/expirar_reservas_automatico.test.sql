-- =============================================================================
-- Ingressoudi - Testes: expiracao automatica de reservas (pg_cron)
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $t$
declare
  v_qtd integer;
  v_agenda text;
  v_comando text;
begin
  select count(*), max(schedule), max(command) into v_qtd, v_agenda, v_comando
    from cron.job where jobname = 'ingressoudi-expirar-reservas';

  if v_qtd <> 1 then
    raise exception 'FALHOU: esperado 1 job ingressoudi-expirar-reservas, encontrado %', v_qtd;
  end if;
  if v_agenda <> '55 2 * * *' then
    raise exception 'FALHOU: agenda inesperada %', v_agenda;
  end if;
  if v_comando <> 'select private.processar_reservas_expiradas(null)' then
    raise exception 'FALHOU: comando inesperado %', v_comando;
  end if;

  -- o comando agendado precisa rodar sem erro
  perform private.processar_reservas_expiradas(null);

  raise notice 'OK: job de expiracao automatica agendado para 23h55 de Brasilia';
end
$t$;

rollback;
