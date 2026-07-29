-- Phase 8: immutable official-scoring decisions and disposable statistics.
-- Rollback: preserve exported box scores, then drop RPCs and the two derived tables.

create table if not exists public.sd_game_scoring_decisions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_organizations(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  physical_event_id uuid not null references public.sd_game_scoring_events(id) on delete cascade,
  root_decision_id uuid not null,
  supersedes_decision_id uuid references public.sd_game_scoring_decisions(id),
  decision_type text not null,
  preliminary_value text,
  final_value text,
  decision_status text not null check (decision_status in ('preliminary','final','under_review','superseded')),
  rule_reference text,
  reasoning_note text,
  review_requested boolean not null default false,
  decision_maker_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  finalized_at timestamptz
);

create table if not exists public.sd_game_stat_snapshots (
  game_id uuid primary key references public.sd_games(id) on delete cascade,
  org_id uuid not null references public.sd_organizations(id) on delete cascade,
  game_version bigint not null,
  decision_version bigint not null default 0,
  batting jsonb not null default '{}',
  pitching jsonb not null default '{}',
  fielding jsonb not null default '{}',
  team_totals jsonb not null default '{}',
  validation jsonb not null default '{}',
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sd_game_scoring_decisions_game_event_idx
  on public.sd_game_scoring_decisions(game_id, physical_event_id, created_at);
create index if not exists sd_game_scoring_decisions_root_idx
  on public.sd_game_scoring_decisions(root_decision_id, created_at desc);

alter table public.sd_game_scoring_decisions enable row level security;
alter table public.sd_game_stat_snapshots enable row level security;
create policy sd_game_scoring_decisions_select on public.sd_game_scoring_decisions
for select using (exists (
  select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id)
));
create policy sd_game_stat_snapshots_select on public.sd_game_stat_snapshots
for select using (exists (
  select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id)
));
grant select on public.sd_game_scoring_decisions, public.sd_game_stat_snapshots to authenticated;

create or replace function public.sd_append_game_scoring_decision(
  p_game_id uuid,
  p_physical_event_id uuid,
  p_root_decision_id uuid,
  p_supersedes_decision_id uuid,
  p_decision_type text,
  p_preliminary_value text,
  p_final_value text,
  p_decision_status text,
  p_rule_reference text,
  p_reasoning_note text,
  p_review_requested boolean
) returns public.sd_game_scoring_decisions
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_previous public.sd_game_scoring_decisions;
  v_inserted public.sd_game_scoring_decisions;
begin
  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or not public.sd_can_score_game(p_game_id) then
    raise exception 'official_scoring_not_authorized';
  end if;
  if p_decision_status not in ('preliminary','final','under_review') then
    raise exception 'invalid_decision_status';
  end if;
  if not exists (
    select 1 from public.sd_game_scoring_events
    where id = p_physical_event_id and game_id = p_game_id
  ) then raise exception 'physical_event_not_found'; end if;
  if p_supersedes_decision_id is not null then
    select * into v_previous from public.sd_game_scoring_decisions
      where id = p_supersedes_decision_id and game_id = p_game_id for update;
    if not found or v_previous.root_decision_id <> p_root_decision_id then
      raise exception 'decision_revision_invalid';
    end if;
  end if;
  insert into public.sd_game_scoring_decisions(
    org_id,game_id,physical_event_id,root_decision_id,supersedes_decision_id,
    decision_type,preliminary_value,final_value,decision_status,rule_reference,
    reasoning_note,review_requested,decision_maker_id,finalized_at
  ) values(
    v_game.org_id,p_game_id,p_physical_event_id,p_root_decision_id,p_supersedes_decision_id,
    p_decision_type,p_preliminary_value,p_final_value,p_decision_status,p_rule_reference,
    p_reasoning_note,p_review_requested,auth.uid(),
    case when p_decision_status='final' then now() else null end
  ) returning * into v_inserted;
  if p_supersedes_decision_id is not null then
    update public.sd_game_scoring_decisions set decision_status='superseded'
      where id=p_supersedes_decision_id;
  end if;
  return v_inserted;
end;
$$;
grant execute on function public.sd_append_game_scoring_decision(
  uuid,uuid,uuid,uuid,text,text,text,text,text,text,boolean
) to authenticated;
