-- =============================================================================
-- GZ1 Ingresso - Defesa: rejeitar imagem_url nao persistente (blob:/data:)
-- Migration: atualizar_evento_admin_imagem
--
-- Reaplica private.atualizar_evento_admin com validacao de imagem persistente.
-- =============================================================================

create or replace function private.atualizar_evento_admin(
  p_evento_id uuid,
  p_nome text,
  p_slug text,
  p_descricao text default null,
  p_imagem_url text default null,
  p_inicio_em timestamptz default null,
  p_local text default null,
  p_endereco text default null,
  p_capacidade_total integer default null,
  p_estoque_antecipado integer default null,
  p_publicacao_status public.status_publicacao default null,
  p_vendas_status public.status_vendas default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_slug text;
  v_capacidade integer := coalesce(p_capacidade_total, 0);
  v_estoque integer := coalesce(p_estoque_antecipado, 0);
  v_ocupados integer;
  v_publicado_em timestamptz;
  v_descricao text;
  v_imagem text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao pode ser editado (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do evento' using errcode = '23514';
  end if;
  if p_local is null or btrim(p_local) = '' then
    raise exception 'Informe o local' using errcode = '23514';
  end if;
  if p_endereco is null or btrim(p_endereco) = '' then
    raise exception 'Informe o endereco' using errcode = '23514';
  end if;
  if p_inicio_em is null then
    raise exception 'Informe a data de inicio' using errcode = '23514';
  end if;
  if v_capacidade <= 0 then
    raise exception 'A capacidade deve ser maior que zero' using errcode = '23514';
  end if;
  if v_estoque < 0 then
    raise exception 'O estoque nao pode ser negativo' using errcode = '23514';
  end if;
  if v_estoque > v_capacidade then
    raise exception 'O estoque nao pode exceder a capacidade total' using errcode = '23514';
  end if;

  if p_imagem_url is not null and btrim(p_imagem_url) ~* '^(blob:|data:)' then
    raise exception 'URL de imagem invalida' using errcode = '23514';
  end if;

  select count(*) into v_ocupados
    from public.ingressos i
    join public.pedidos p on p.id = i.pedido_id
   where i.evento_id = p_evento_id
     and (
       i.status in ('VALIDO', 'UTILIZADO')
       or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
     );
  if v_capacidade < v_ocupados then
    raise exception 'A capacidade nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;
  if v_estoque < v_ocupados then
    raise exception 'O estoque nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;

  v_slug := btrim(
    regexp_replace(
      lower(
        translate(
          btrim(coalesce(p_slug, '')),
          U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00F1',
          'aaaaaeeeeiiiiooooouuuucn'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
  if v_slug = '' then
    raise exception 'Informe o slug' using errcode = '23514';
  end if;

  v_descricao := nullif(btrim(coalesce(p_descricao, '')), '');
  v_imagem := nullif(btrim(coalesce(p_imagem_url, '')), '');

  if exists (
    select 1 from public.eventos e
     where e.slug = v_slug and e.id <> p_evento_id
  ) then
    raise exception 'Ja existe um evento com esse endereco de URL' using errcode = '23505';
  end if;

  v_publicado_em := v_evento.publicado_em;
  if p_publicacao_status = 'PUBLICADO' and v_publicado_em is null then
    v_publicado_em := now();
  end if;

  update public.eventos
     set nome = btrim(p_nome),
         slug = v_slug,
         descricao = v_descricao,
         imagem_url = v_imagem,
         inicio_em = p_inicio_em,
         local = btrim(p_local),
         endereco = btrim(p_endereco),
         capacidade_total = v_capacidade,
         estoque_antecipado = v_estoque,
         publicacao_status = coalesce(p_publicacao_status, publicacao_status),
         publicado_em = v_publicado_em,
         atualizado_em = now()
   where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'EVENTO_ATUALIZADO_ADMIN',
    'eventos',
    p_evento_id,
    jsonb_build_object(
      'nome', v_evento.nome,
      'slug', v_evento.slug,
      'capacidade_total', v_evento.capacidade_total,
      'estoque_antecipado', v_evento.estoque_antecipado,
      'publicacao_status', v_evento.publicacao_status,
      'inicio_em', v_evento.inicio_em
    ),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'slug', v_slug,
      'capacidade_total', v_capacidade,
      'estoque_antecipado', v_estoque,
      'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
      'inicio_em', p_inicio_em
    )
  );

  if p_vendas_status is not null then
    perform private.definir_vendas_evento_admin(p_evento_id, p_vendas_status);
  end if;

  return jsonb_build_object(
    'evento_id', p_evento_id,
    'slug', v_slug,
    'nome', btrim(p_nome),
    'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
    'vendas_status', coalesce(p_vendas_status, v_evento.vendas_status)
  );
end;
$$;

revoke all on function private.atualizar_evento_admin(
  uuid, text, text, text, text, timestamptz, text, text, integer, integer,
  public.status_publicacao, public.status_vendas
) from public;
grant execute on function private.atualizar_evento_admin(
  uuid, text, text, text, text, timestamptz, text, text, integer, integer,
  public.status_publicacao, public.status_vendas
) to authenticated, service_role;
