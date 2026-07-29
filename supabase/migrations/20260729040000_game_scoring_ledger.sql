-- Phase 5: immutable scoring ledger and disposable state snapshots.
-- Rollback: archive dependent games, then drop RPCs/policies/tables in reverse order.

create table if not exists public.sd_game_scoring_events (
  id uuid primary key,
  org_id uuid not null references public.sd_organizations(id) on delete cascade,
  game_id uuid not null references public.sd_games(id) on delete cascade,
  game_version bigint not null check (game_version > 0),
  sequence bigint not null check (sequence > 0),
  event_type text not null,
  actor_user_id uuid not null references auth.users(id),
  actor_device_id uuid not null,
  occurred_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  ruleset_version integer,
  idempotency_key text not null,
  correction_of_event_id uuid references public.sd_game_scoring_events(id),
  supersedes_event_id uuid references public.sd_game_scoring_events(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, sequence),
  unique (game_id, game_version),
  unique (game_id, idempotency_key)
);

create table if not exists public.sd_game_state_snapshots (
  game_id uuid primary key references public.sd_games(id) on delete cascade,
  org_id uuid not null references public.sd_organizations(id) on delete cascade,
  game_version bigint not null default 0,
  state jsonb not null default '{}'::jsonb,
  last_event_id uuid references public.sd_game_scoring_events(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sd_game_scoring_events_game_sequence_idx
  on public.sd_game_scoring_events(game_id, sequence);
create index if not exists sd_game_scoring_events_org_game_idx
  on public.sd_game_scoring_events(org_id, game_id);

alter table public.sd_game_scoring_events enable row level security;
alter table public.sd_game_state_snapshots enable row level security;

drop policy if exists sd_game_scoring_events_select on public.sd_game_scoring_events;
create policy sd_game_scoring_events_select on public.sd_game_scoring_events for select
using (
  exists (select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id))
);
drop policy if exists sd_game_state_snapshots_select on public.sd_game_state_snapshots;
create policy sd_game_state_snapshots_select on public.sd_game_state_snapshots for select
using (
  exists (select 1 from public.sd_games g where g.id = game_id and public.sd_can_view_event(g.event_id))
);
grant select on public.sd_game_scoring_events, public.sd_game_state_snapshots to authenticated;

create or replace function public.sd_reject_scoring_event_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'scoring_ledger_is_immutable'; end;
$$;
drop trigger if exists trg_sd_game_scoring_events_immutable on public.sd_game_scoring_events;
create trigger trg_sd_game_scoring_events_immutable
before update or delete on public.sd_game_scoring_events
for each row execute function public.sd_reject_scoring_event_mutation();

create or replace function public.sd_can_score_game(p_game_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.sd_games g
    where g.id = p_game_id and (
      public.sd_is_org_admin(g.org_id)
      or exists (
        select 1 from public.sd_event_participants p
        where p.event_id = g.event_id and p.user_id = auth.uid() and p.can_score
      )
    )
  );
$$;
grant execute on function public.sd_can_score_game(uuid) to authenticated;

create or replace function public.sd_append_game_scoring_event(
  p_game_id uuid,
  p_canonical_event_id uuid,
  p_scoring_event_id uuid,
  p_expected_version bigint,
  p_event_type text,
  p_actor_device_id uuid,
  p_payload jsonb,
  p_idempotency_key text,
  p_correction_of_event_id uuid default null,
  p_supersedes_event_id uuid default null
) returns public.sd_game_scoring_events
language plpgsql security definer set search_path = '' as $$
declare
  v_game public.sd_games;
  v_existing public.sd_game_scoring_events;
  v_inserted public.sd_game_scoring_events;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into v_existing from public.sd_game_scoring_events
  where game_id = p_game_id and idempotency_key = p_idempotency_key;
  if found then return v_existing; end if;

  select * into v_game from public.sd_games where id = p_game_id for update;
  if not found or v_game.event_id <> p_canonical_event_id then raise exception 'game_not_found'; end if;
  if not public.sd_can_score_game(p_game_id) then raise exception 'scorekeeping_not_authorized'; end if;
  if v_game.status in ('final','forfeit','no_contest','canceled') then
    raise exception 'game_not_mutable';
  end if;
  if v_game.game_version <> p_expected_version then raise exception 'stale_game_version'; end if;

  insert into public.sd_game_scoring_events (
    id, org_id, game_id, game_version, sequence, event_type,
    actor_user_id, actor_device_id, payload, ruleset_version,
    idempotency_key, correction_of_event_id, supersedes_event_id
  ) values (
    p_scoring_event_id, v_game.org_id, p_game_id, p_expected_version + 1,
    p_expected_version + 1, p_event_type, auth.uid(), p_actor_device_id,
    coalesce(p_payload, '{}'::jsonb), v_game.ruleset_version,
    p_idempotency_key, p_correction_of_event_id, p_supersedes_event_id
  ) returning * into v_inserted;

  update public.sd_games set game_version = p_expected_version + 1 where id = p_game_id;
  insert into public.sd_game_state_snapshots(game_id, org_id, game_version, state, last_event_id)
  values (p_game_id, v_game.org_id, p_expected_version + 1,
          jsonb_build_object('requires_replay', true), p_scoring_event_id)
  on conflict (game_id) do update set
    game_version = excluded.game_version,
    state = excluded.state,
    last_event_id = excluded.last_event_id,
    updated_at = now();
  return v_inserted;
end;
$$;
grant execute on function public.sd_append_game_scoring_event(
  uuid, uuid, uuid, bigint, text, uuid, jsonb, text, uuid, uuid
) to authenticated;

comment on table public.sd_game_scoring_events is
  'Immutable physical/ruling/rule/scoring events; replay is the source of truth.';
