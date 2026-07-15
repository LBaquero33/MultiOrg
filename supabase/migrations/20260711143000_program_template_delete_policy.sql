-- Coaches may delete only templates they own in their active organization.
-- Program assignments retain ON DELETE RESTRICT, preventing accidental loss
-- of player history when a template is still in use.
drop policy if exists "sd_program_templates_delete" on public.sd_program_templates;
create policy "sd_program_templates_delete"
on public.sd_program_templates
for delete
using (
  coach_id = auth.uid()
  and public.sd_is_org_staff(org_id)
);
