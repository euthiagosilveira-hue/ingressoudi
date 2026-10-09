-- =============================================================================
-- GZ1 Ingresso - Catalogo publico seguro
-- Migration: catalogo_publico_seguro
--
-- Superficie publica de leitura via RPC (sem SELECT direto e sem RLS aberta):
--   public.listar_eventos_publicos() -> private (SECURITY DEFINER)
--   public.obter_evento_publico(slug) -> private (SECURITY DEFINER)
--
-- Regras:
--   * listar: publicacao_status='PUBLICADO', status='AGENDADO', inicio_em >= now(),
--             ordem inicio_em ASC.
--   * detalhe por slug: publicacao_status='PUBLICADO' (aceita CANCELADO/REALIZADO/
--             EM_ANDAMENTO para links antigos), nunca RASCUNHO.
--   * situacao_venda: DISPONIVEL | ESGOTADO | VENDAS_ENCERRADAS |
--             EVENTO_EM_ANDAMENTO | ENCERRADO | CANCELADO | SEM_LOTE.
--
-- Nao expor: capacidade_total, estoque_antecipado, quantidade de lote, ordem,
-- tipo_ativacao, ativacao_em, ativado_em, encerrado_em, criado/atualizado.
-- Nao cria view nem policy. Tabelas seguem fechadas.
--
-- REVOKE explicito em TODAS as funcoes novas (nao confiar em default privileges).
-- =============================================================================

-- private.calcular_situacao_venda ---------------------------------------------
create or replace function private.calcular_situacao_venda(p_evento_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_e public.eventos%rowtype;
  v_lote_id uuid;
  v_disp_e integer;
  v_disp_l integer;
begin
  select * into v_e from public.eventos e where e.id = p_evento_id;
  if not found then
    return null;
  end if;

  if v_e.status = 'CANCELADO' then
    return 'CANCELADO';
  end if;
  if v_e.status = 'REALIZADO' then
    return 'ENCERRADO';
  end if;
  if v_e.status = 'EM_ANDAMENTO' then
    return 'EVENTO_EM_ANDAMENTO';
  end if;
  if v_e.vendas_status <> 'ABERTAS' then
    return 'VENDAS_ENCERRADAS';
  end if;
  if now() >= v_e.inicio_em then
    return 'VENDAS_ENCERRADAS';
  end if;

  select l.id into v_lote_id
    from public.lotes l
   where l.evento_id = v_e.id and l.status = 'ATIVO'
   limit 1;

  if v_lote_id is null then
    return 'SEM_LOTE';
  end if;

  v_disp_e := private.calcular_disponibilidade_evento(v_e.id);
  if v_disp_e <= 0 then
    return 'ESGOTADO';
  end if;

  v_disp_l := private.calcular_disponibilidade_lote(v_lote_id);
  if v_disp_l <= 0 then
    return 'ESGOTADO';
  end if;

  return 'DISPONIVEL';
end;
$$;

-- private.listar_eventos_publicos ---------------------------------------------
create or replace function private.listar_eventos_publicos()
returns table (
  evento_id uuid,
  slug text,
  nome text,
  descricao text,
  imagem_url text,
  inicio_em timestamptz,
  local text,
  endereco text,
  status public.status_evento,
  vendas_status public.status_vendas,
  lote_id uuid,
  lote_nome text,
  preco numeric,
  situacao_venda text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id)
  from public.eventos e
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where e.publicacao_status = 'PUBLICADO'
    and e.status = 'AGENDADO'
    and e.inicio_em >= now()
  order by e.inicio_em asc;
$$;

-- private.obter_evento_publico ------------------------------------------------
create or replace function private.obter_evento_publico(p_slug text)
returns table (
  evento_id uuid,
  slug text,
  nome text,
  descricao text,
  imagem_url text,
  inicio_em timestamptz,
  local text,
  endereco text,
  status public.status_evento,
  vendas_status public.status_vendas,
  lote_id uuid,
  lote_nome text,
  preco numeric,
  situacao_venda text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id)
  from public.eventos e
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where e.slug = p_slug
    and e.publicacao_status = 'PUBLICADO'
  limit 1;
$$;

-- WRAPPERS PUBLICOS (SECURITY INVOKER) ----------------------------------------
create or replace function public.listar_eventos_publicos()
returns table (
  evento_id uuid,
  slug text,
  nome text,
  descricao text,
  imagem_url text,
  inicio_em timestamptz,
  local text,
  endereco text,
  status public.status_evento,
  vendas_status public.status_vendas,
  lote_id uuid,
  lote_nome text,
  preco numeric,
  situacao_venda text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.listar_eventos_publicos();
$$;

create or replace function public.obter_evento_publico(p_slug text)
returns table (
  evento_id uuid,
  slug text,
  nome text,
  descricao text,
  imagem_url text,
  inicio_em timestamptz,
  local text,
  endereco text,
  status public.status_evento,
  vendas_status public.status_vendas,
  lote_id uuid,
  lote_nome text,
  preco numeric,
  situacao_venda text
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.obter_evento_publico(p_slug);
$$;

-- ACL EXPLICITA (sem depender de default privileges) --------------------------
revoke all on function private.calcular_situacao_venda(uuid) from public, anon, authenticated;
revoke all on function private.listar_eventos_publicos() from public, anon, authenticated;
revoke all on function private.obter_evento_publico(text) from public, anon, authenticated;

grant execute on function private.listar_eventos_publicos() to anon, authenticated, service_role;
grant execute on function private.obter_evento_publico(text) to anon, authenticated, service_role;

revoke all on function public.listar_eventos_publicos() from public, anon, authenticated, service_role;
revoke all on function public.obter_evento_publico(text) from public, anon, authenticated, service_role;

grant execute on function public.listar_eventos_publicos() to anon, authenticated, service_role;
grant execute on function public.obter_evento_publico(text) to anon, authenticated, service_role;
