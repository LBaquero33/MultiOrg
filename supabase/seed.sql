-- Deterministic local-only identity used by database authorization tests.
-- Production platform administrators are granted explicitly after their auth user exists.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'platform-admin@homeplate.local',
  crypt('local-test-only', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Local Platform Admin","role":"coach"}'::jsonb,
  now(),
  now(),
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

insert into public.sd_platform_admins (user_id, notes)
values (
  '00000000-0000-4000-8000-000000000001',
  'Deterministic local test platform administrator'
)
on conflict (user_id) do nothing;
