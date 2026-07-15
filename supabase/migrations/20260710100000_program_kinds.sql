-- Separate the shared program engine into three clear coaching workflows while
-- retaining the existing template/day/assignment data model.

alter table public.sd_program_templates
  add column if not exists program_kind text;

update public.sd_program_templates
set program_kind = 'strength'
where program_kind is null or program_kind not in ('strength', 'hitting', 'pitching');

alter table public.sd_program_templates
  alter column program_kind set default 'strength',
  alter column program_kind set not null;

alter table public.sd_program_templates
  drop constraint if exists sd_program_templates_program_kind_check;

alter table public.sd_program_templates
  add constraint sd_program_templates_program_kind_check
  check (program_kind in ('strength', 'hitting', 'pitching'));

create index if not exists idx_sd_program_templates_coach_kind
  on public.sd_program_templates(coach_id, program_kind, created_at desc);
