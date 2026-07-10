-- Player onboarding (Shiny parity).

create table if not exists public.sd_player_onboarding (
  player_id uuid primary key references auth.users(id) on delete cascade,
  improve_focus text not null,
  improve_plan text,
  daily_goals text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.sd_player_onboarding enable row level security;

-- Keep updated_at fresh.
create or replace function public.sd_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sd_player_onboarding_updated_at on public.sd_player_onboarding;
create trigger trg_sd_player_onboarding_updated_at
before update on public.sd_player_onboarding
for each row
execute function public.sd_set_updated_at();

-- Player can read/insert/update their own onboarding row.
drop policy if exists "sd_onboarding_select_own" on public.sd_player_onboarding;
create policy "sd_onboarding_select_own"
on public.sd_player_onboarding
for select
using (auth.uid() = player_id);

drop policy if exists "sd_onboarding_insert_own" on public.sd_player_onboarding;
create policy "sd_onboarding_insert_own"
on public.sd_player_onboarding
for insert
with check (auth.uid() = player_id);

drop policy if exists "sd_onboarding_update_own" on public.sd_player_onboarding;
create policy "sd_onboarding_update_own"
on public.sd_player_onboarding
for update
using (auth.uid() = player_id)
with check (auth.uid() = player_id);

-- Coaches can view all onboarding rows (read-only).
drop policy if exists "sd_onboarding_select_coach_all" on public.sd_player_onboarding;
create policy "sd_onboarding_select_coach_all"
on public.sd_player_onboarding
for select
using (public.is_coach(auth.uid()));

-- Coach reset RPC (security definer) so we don't have to grant coaches general update/delete.
create or replace function public.sd_reset_onboarding(target_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_coach(auth.uid()) then
    raise exception 'not_authorized';
  end if;

  update public.sd_player_onboarding
  set completed_at = null,
      updated_at = now()
  where player_id = target_player_id;
end;
$$;

revoke all on function public.sd_reset_onboarding(uuid) from public;
grant execute on function public.sd_reset_onboarding(uuid) to authenticated;

