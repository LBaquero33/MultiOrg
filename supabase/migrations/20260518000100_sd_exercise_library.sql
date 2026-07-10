-- Per-coach exercise name library for autocomplete in program builder.

create table if not exists public.sd_exercise_library (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  name_norm text not null,
  usage_count int not null default 1,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_sd_exercise_library_unique
on public.sd_exercise_library(coach_id, name_norm);

create index if not exists idx_sd_exercise_library_coach_last_used
on public.sd_exercise_library(coach_id, last_used_at desc);

create or replace function public.trg_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sd_exercise_library_updated_at on public.sd_exercise_library;
create trigger trg_sd_exercise_library_updated_at
before update on public.sd_exercise_library
for each row execute function public.trg_touch_updated_at();

alter table public.sd_exercise_library enable row level security;

drop policy if exists "sd_exercise_library_select" on public.sd_exercise_library;
create policy "sd_exercise_library_select"
on public.sd_exercise_library
for select
using (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

drop policy if exists "sd_exercise_library_write" on public.sd_exercise_library;
create policy "sd_exercise_library_write"
on public.sd_exercise_library
for all
using (coach_id = auth.uid() and public.sd_is_coach(auth.uid()))
with check (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

