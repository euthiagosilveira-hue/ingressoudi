-- =============================================================================
-- GZ1 Ingresso - Criacao de evento: correcao da normalizacao de slug
-- Migration: criar_evento_admin_slug
--
-- Substitui a versao anterior usando literal Unicode escapada (U&'...') para
-- evitar corrupcao de encoding na remocao de acentos.
-- =============================================================================

create or replace function public.criar_evento_admin(
  p_nome text,
  p_slug text,
  p_descricao text default null,
  p_imagem_url text default null,
  p_inicio_em timestamptz default null,
  p_local text default null,
  p_endereco text default null,
  p_capacidade_total integer default null,
  p_estoque_antecipado integer default null,
  p_publicacao_status public.status_publicacao default 'RASCUNHO',
  p_vendas_status public.status_vendas default 'ENCERRADAS'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_slug text;
  v_evento_id uuid;
  v_capacidade integer := coalesce(p_capacidade_total, 0);
  v_estoque integer := coalesce(p_estoque_antecipado, 0);
  v_publicado_em timestamptz;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
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

  v_publicado_em := case when p_publicacao_status = 'PUBLICADO' then now() else null end;

  begin
    insert into public.eventos (
      nome, slug, descricao, imagem_url, inicio_em, local, endereco,
      capacidade_total, estoque_antecipado, status, vendas_status,
      publicacao_status, publicado_em
    ) values (
      btrim(p_nome), v_slug, nullif(btrim(coalesce(p_descricao, '')), ''), nullif(btrim(coalesce(p_imagem_url, '')), ''),
      p_inicio_em, btrim(p_local), btrim(p_endereco),
      v_capacidade, v_estoque, 'AGENDADO', p_vendas_status,
      p_publicacao_status, v_publicado_em
    )
    returning id into v_evento_id;
  exception
    when unique_violation then
      raise exception 'Ja existe um evento com esse endereco de URL' using errcode = '23505';
  end;

  return jsonb_build_object(
    'evento_id', v_evento_id,
    'slug', v_slug,
    'nome', btrim(p_nome),
    'status', 'AGENDADO',
    'publicacao_status', p_publicacao_status
  );
end;
$$;

revoke execute on function public.criar_evento_admin(
  text, text, text, text, timestamptz, text, text, integer, integer, public.status_publicacao, public.status_vendas
) from public, anon, authenticated, service_role;
grant execute on function public.criar_evento_admin(
  text, text, text, text, timestamptz, text, text, integer, integer, public.status_publicacao, public.status_vendas
) to authenticated, service_role;
