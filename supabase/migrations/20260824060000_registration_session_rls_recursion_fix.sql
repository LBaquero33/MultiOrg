begin;

-- Avoid re-entering sd_registration_offering_staff through its own policy.
drop policy if exists sd_registration_offering_staff_subject_read
  on public.sd_registration_offering_staff;

create policy sd_registration_offering_staff_subject_read
on public.sd_registration_offering_staff
for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.sd_is_org_admin(organization_id)
);

-- Session schedule details belong on every active organization member's calendar.
-- Participants, evaluations, and decisions keep their separate restrictive policies.
drop policy if exists sd_registration_sessions_authorized_read
  on public.sd_registration_sessions;

create policy sd_registration_sessions_authorized_read
on public.sd_registration_sessions
for select
to authenticated
using (public.sd_is_org_member(organization_id));

commit;
