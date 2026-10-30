-- Preserve the public website visibility of offerings created before the
-- connected operations workspace introduced public_visible.
update public.sd_registration_offerings
set public_visible = true
where visibility = 'public'
  and public_visible = false;
