begin;

create table if not exists public.sd_testing_field_media (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  testing_entry_id uuid not null references public.sd_testing_entries(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  field_key text not null check (length(btrim(field_key)) between 1 and 100),
  storage_path text not null unique,
  file_name text,
  mime_type text not null check (mime_type in ('video/mp4', 'video/quicktime')),
  byte_size bigint check (byte_size is null or byte_size between 1 and 262144000),
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (testing_entry_id, field_key)
);

create or replace function public.sd_scope_testing_field_media()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  entry_row public.sd_testing_entries%rowtype;
begin
  select * into entry_row
  from public.sd_testing_entries
  where id = new.testing_entry_id;

  if not found or entry_row.org_id is null then
    raise exception 'testing_entry_not_found' using errcode = 'P0002';
  end if;

  new.org_id := entry_row.org_id;
  new.player_id := entry_row.player_id;
  new.uploaded_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists sd_scope_testing_field_media_trigger on public.sd_testing_field_media;
create trigger sd_scope_testing_field_media_trigger
before insert or update on public.sd_testing_field_media
for each row execute function public.sd_scope_testing_field_media();

alter table public.sd_testing_field_media enable row level security;

drop policy if exists "testing field media read" on public.sd_testing_field_media;
create policy "testing field media read"
on public.sd_testing_field_media for select to authenticated
using (
  player_id = (select auth.uid())
  or public.sd_can_manage_team_player(org_id, player_id)
  or public.sd_is_linked_parent_in_org((select auth.uid()), player_id, org_id)
);

drop policy if exists "testing field media create" on public.sd_testing_field_media;
create policy "testing field media create"
on public.sd_testing_field_media for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and (
    player_id = (select auth.uid())
    or public.sd_can_manage_team_player(org_id, player_id)
  )
);

drop policy if exists "testing field media update" on public.sd_testing_field_media;
create policy "testing field media update"
on public.sd_testing_field_media for update to authenticated
using (
  player_id = (select auth.uid())
  or public.sd_can_manage_team_player(org_id, player_id)
)
with check (
  uploaded_by = (select auth.uid())
  and (
    player_id = (select auth.uid())
    or public.sd_can_manage_team_player(org_id, player_id)
  )
);

drop policy if exists "testing field media delete" on public.sd_testing_field_media;
create policy "testing field media delete"
on public.sd_testing_field_media for delete to authenticated
using (
  uploaded_by = (select auth.uid())
  or player_id = (select auth.uid())
  or public.sd_can_manage_team_player(org_id, player_id)
);

create table if not exists public.sd_chat_attachments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  channel_id uuid not null references public.sd_chat_channels(id) on delete cascade,
  message_id uuid not null references public.sd_chat_messages(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null check (length(btrim(file_name)) between 1 and 255),
  mime_type text not null check (length(btrim(mime_type)) between 1 and 150),
  byte_size bigint not null check (byte_size between 1 and 52428800),
  attachment_kind text not null check (attachment_kind in ('image', 'file')),
  created_at timestamptz not null default now()
);

create index if not exists ix_sd_chat_attachments_message
on public.sd_chat_attachments(message_id, created_at, id);

create or replace function public.sd_scope_chat_attachment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  message_row public.sd_chat_messages%rowtype;
begin
  select * into message_row
  from public.sd_chat_messages
  where id = new.message_id;

  if not found or message_row.org_id is null then
    raise exception 'chat_message_not_found' using errcode = 'P0002';
  end if;
  if message_row.sender_id is distinct from auth.uid() then
    raise exception 'chat_attachment_sender_mismatch' using errcode = '42501';
  end if;

  new.org_id := message_row.org_id;
  new.channel_id := message_row.channel_id;
  new.uploader_id := auth.uid();
  return new;
end;
$$;

drop trigger if exists sd_scope_chat_attachment_trigger on public.sd_chat_attachments;
create trigger sd_scope_chat_attachment_trigger
before insert or update on public.sd_chat_attachments
for each row execute function public.sd_scope_chat_attachment();

alter table public.sd_chat_attachments enable row level security;

drop policy if exists "chat attachments read" on public.sd_chat_attachments;
create policy "chat attachments read"
on public.sd_chat_attachments for select to authenticated
using (public.sd_chat_is_member(channel_id, (select auth.uid())));

drop policy if exists "chat attachments create" on public.sd_chat_attachments;
create policy "chat attachments create"
on public.sd_chat_attachments for insert to authenticated
with check (
  uploader_id = (select auth.uid())
  and public.sd_chat_is_member(channel_id, (select auth.uid()))
);

drop policy if exists "chat attachments delete" on public.sd_chat_attachments;
create policy "chat attachments delete"
on public.sd_chat_attachments for delete to authenticated
using (uploader_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-attachments',
  'chat-attachments',
  false,
  52428800,
  array[
    'image/jpeg', 'image/png', 'image/heic', 'image/webp',
    'application/pdf', 'text/plain', 'text/csv',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat members upload attachments" on storage.objects;
create policy "chat members upload attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-attachments'
  and owner_id = (select auth.uid()::text)
  and (storage.foldername(name))[3] = (select auth.uid()::text)
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and public.sd_chat_is_member(((storage.foldername(name))[2])::uuid, (select auth.uid()))
  and exists (
    select 1 from public.sd_chat_channels channel
    where channel.id = ((storage.foldername(name))[2])::uuid
      and channel.org_id = ((storage.foldername(name))[1])::uuid
  )
);

drop policy if exists "chat members read attachments" on storage.objects;
create policy "chat members read attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and public.sd_chat_is_member(((storage.foldername(name))[2])::uuid, (select auth.uid()))
);

drop policy if exists "chat attachment owners delete" on storage.objects;
create policy "chat attachment owners delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-attachments'
  and owner_id = (select auth.uid()::text)
);

grant select, insert, update, delete on public.sd_testing_field_media to authenticated;
grant select, insert, delete on public.sd_chat_attachments to authenticated;

commit;
