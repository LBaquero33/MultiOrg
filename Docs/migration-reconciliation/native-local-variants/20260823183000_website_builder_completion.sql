begin;
create table if not exists public.sd_public_site_navigation_items (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  location text not null default 'header' check (location in ('header', 'footer', 'utility')),
  parent_id uuid references public.sd_public_site_navigation_items(id) on delete set null,
  item_type text not null default 'page' check (item_type in ('page', 'section', 'form', 'registration', 'facility', 'file', 'external', 'email', 'phone')),
  label text not null check (char_length(label) between 1 and 80),
  page_id uuid references public.sd_public_site_pages(id) on delete cascade,
  destination jsonb not null default '{}'::jsonb check (jsonb_typeof(destination) = 'object'),
  sort_order integer not null default 0,
  is_visible boolean not null default true,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id)
);
create index if not exists sd_public_site_navigation_items_order
  on public.sd_public_site_navigation_items(site_id, location, parent_id, sort_order);
alter table public.sd_public_form_definitions
  add column if not exists confirmation jsonb not null default '{}'::jsonb check (jsonb_typeof(confirmation) = 'object'),
  add column if not exists notifications jsonb not null default '{}'::jsonb check (jsonb_typeof(notifications) = 'object'),
  add column if not exists presentation jsonb not null default '{}'::jsonb check (jsonb_typeof(presentation) = 'object'),
  add column if not exists payment jsonb not null default '{"enabled":false,"currency":"usd","mode":"fixed","collection":"full"}'::jsonb check (jsonb_typeof(payment) = 'object'),
  add column if not exists revision integer not null default 1 check (revision > 0);
alter table public.sd_public_form_submissions
  drop constraint if exists sd_public_form_submissions_workflow_status_check;
alter table public.sd_public_form_submissions
  add constraint sd_public_form_submissions_workflow_status_check
    check (workflow_status in ('new', 'in_progress', 'awaiting_payment', 'paid', 'replied', 'completed', 'spam', 'archived')),
  add column if not exists payment_status text not null default 'not_required' check (payment_status in ('not_required', 'pending', 'paid', 'failed', 'abandoned', 'refunded', 'disputed')),
  add column if not exists amount_cents integer check (amount_cents is null or amount_cents >= 0),
  add column if not exists currency text check (currency is null or currency ~ '^[a-z]{3}$'),
  add column if not exists price_option_id text,
  add column if not exists checkout_session_id text,
  add column if not exists payment_intent_id text,
  add column if not exists provider_account_id text,
  add column if not exists offering_id uuid references public.sd_registration_offerings(id) on delete set null,
  add column if not exists form_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(form_snapshot) = 'object'),
  add column if not exists audit_history jsonb not null default '[]'::jsonb check (jsonb_typeof(audit_history) = 'array');
create unique index if not exists sd_public_form_submissions_checkout
  on public.sd_public_form_submissions(checkout_session_id)
  where checkout_session_id is not null;
create table if not exists public.sd_public_registration_submissions (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references public.sd_public_form_submissions(id) on delete cascade,
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  offering_id uuid references public.sd_registration_offerings(id) on delete set null,
  registration_type text not null default 'tryout' check (registration_type in ('tryout', 'camp', 'clinic', 'program', 'custom')),
  status text not null default 'submitted' check (status in ('submitted', 'awaiting_payment', 'paid', 'reviewing', 'accepted', 'waitlisted', 'declined', 'cancelled', 'refunded')),
  linked_user_id uuid references auth.users(id) on delete set null,
  linked_player_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sd_public_registration_submissions_queue
  on public.sd_public_registration_submissions(org_id, status, created_at desc);
create table if not exists public.sd_public_form_uploads (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sd_public_sites(id) on delete cascade,
  org_id uuid not null references public.sd_orgs(id) on delete cascade,
  form_id uuid not null references public.sd_public_form_definitions(id) on delete cascade,
  submission_id uuid references public.sd_public_form_submissions(id) on delete cascade,
  bucket_id text not null default 'public-form-uploads' check (bucket_id = 'public-form-uploads'),
  object_path text not null,
  file_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size between 1 and 10485760),
  status text not null default 'pending' check (status in ('pending', 'submitted', 'deleted')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (bucket_id, object_path)
);
create index if not exists sd_public_form_uploads_submission
  on public.sd_public_form_uploads(org_id, submission_id, created_at desc);
create table if not exists public.sd_public_request_limits (
  bucket_key text primary key,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  expires_at timestamptz not null
);
create or replace function public.sd_public_request_allowed(
  p_bucket_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_count integer;
begin
  if p_bucket_key is null or char_length(p_bucket_key) < 16 or p_limit < 1 or p_window_seconds < 1 then
    return false;
  end if;

  insert into public.sd_public_request_limits(bucket_key, window_start, request_count, expires_at)
  values (p_bucket_key, v_now, 1, v_now + make_interval(secs => p_window_seconds))
  on conflict (bucket_key) do update
  set window_start = case when public.sd_public_request_limits.expires_at <= v_now then v_now else public.sd_public_request_limits.window_start end,
      request_count = case when public.sd_public_request_limits.expires_at <= v_now then 1 else public.sd_public_request_limits.request_count + 1 end,
      expires_at = case when public.sd_public_request_limits.expires_at <= v_now then v_now + make_interval(secs => p_window_seconds) else public.sd_public_request_limits.expires_at end
  returning request_count into v_count;

  return v_count <= p_limit;
end;
$$;
revoke all on function public.sd_public_request_allowed(text, integer, integer) from public;
grant execute on function public.sd_public_request_allowed(text, integer, integer) to service_role;
create or replace function public.sd_set_public_site_homepage(
  p_site_id uuid,
  p_page_id uuid,
  p_expected_revision integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
begin
  select * into v_site from public.sd_public_sites where id = p_site_id for update;
  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;
  if not exists (select 1 from public.sd_public_site_pages where id = p_page_id and site_id = p_site_id and org_id = v_site.org_id) then
    raise exception 'page_not_found';
  end if;

  update public.sd_public_site_pages set is_home = false, updated_by = auth.uid(), updated_at = now() where site_id = p_site_id and is_home;
  update public.sd_public_site_pages set is_home = true, slug = '', status = 'draft', updated_by = auth.uid(), updated_at = now() where id = p_page_id and site_id = p_site_id;
  update public.sd_public_sites set draft_revision = draft_revision + 1, updated_by = auth.uid(), updated_at = now() where id = p_site_id;
  return p_expected_revision + 1;
end;
$$;
revoke all on function public.sd_set_public_site_homepage(uuid, uuid, integer) from public;
grant execute on function public.sd_set_public_site_homepage(uuid, uuid, integer) to authenticated;
create or replace function public.sd_delete_public_site_page(
  p_page_id uuid,
  p_expected_revision integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_page public.sd_public_site_pages%rowtype;
  v_site public.sd_public_sites%rowtype;
begin
  select * into v_page from public.sd_public_site_pages where id = p_page_id;
  if v_page.id is null then
    raise exception 'page_not_found';
  end if;

  select * into v_site from public.sd_public_sites where id = v_page.site_id for update;
  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;
  if v_page.org_id <> v_site.org_id then
    raise exception 'page_not_found';
  end if;
  if v_page.is_home then
    raise exception 'homepage_cannot_be_deleted';
  end if;

  delete from public.sd_public_site_pages where id = p_page_id and site_id = v_site.id;
  update public.sd_public_sites
  set draft_revision = draft_revision + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = v_site.id;
  return p_expected_revision + 1;
end;
$$;
revoke all on function public.sd_delete_public_site_page(uuid, integer) from public;
grant execute on function public.sd_delete_public_site_page(uuid, integer) to authenticated;
create or replace function public.sd_save_public_site_navigation(
  p_site_id uuid,
  p_expected_revision integer,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
  v_item jsonb;
  v_id uuid;
  v_parent uuid;
  v_page uuid;
begin
  select * into v_site from public.sd_public_sites where id = p_site_id for update;
  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 80 then
    raise exception 'invalid_navigation';
  end if;

  delete from public.sd_public_site_navigation_items where site_id = p_site_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
    v_page := nullif(v_item ->> 'page_id', '')::uuid;
    if v_page is not null and not exists (select 1 from public.sd_public_site_pages where id = v_page and site_id = p_site_id) then
      raise exception 'navigation_page_not_found';
    end if;
    insert into public.sd_public_site_navigation_items(
      id, site_id, org_id, location, parent_id, item_type, label, page_id,
      destination, sort_order, is_visible, created_by, updated_by
    ) values (
      v_id, p_site_id, v_site.org_id,
      case when v_item ->> 'location' in ('header', 'footer', 'utility') then v_item ->> 'location' else 'header' end,
      null,
      case when v_item ->> 'item_type' in ('page', 'section', 'form', 'registration', 'facility', 'file', 'external', 'email', 'phone') then v_item ->> 'item_type' else 'page' end,
      left(coalesce(nullif(v_item ->> 'label', ''), 'Link'), 80), v_page,
      coalesce(v_item -> 'destination', '{}'::jsonb),
      coalesce((v_item ->> 'sort_order')::integer, 0),
      coalesce((v_item ->> 'is_visible')::boolean, true), auth.uid(), auth.uid()
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_id := nullif(v_item ->> 'id', '')::uuid;
    v_parent := nullif(v_item ->> 'parent_id', '')::uuid;
    if v_id is not null and v_parent is not null then
      if not exists (
        select 1 from public.sd_public_site_navigation_items parent
        where parent.id = v_parent and parent.site_id = p_site_id and parent.parent_id is null
      ) then
        raise exception 'invalid_navigation_parent';
      end if;
      update public.sd_public_site_navigation_items child
      set parent_id = v_parent
      where child.id = v_id and child.site_id = p_site_id;
    end if;
  end loop;

  update public.sd_public_sites set draft_revision = draft_revision + 1, updated_by = auth.uid(), updated_at = now() where id = p_site_id;
  return p_expected_revision + 1;
end;
$$;
revoke all on function public.sd_save_public_site_navigation(uuid, integer, jsonb) from public;
grant execute on function public.sd_save_public_site_navigation(uuid, integer, jsonb) to authenticated;
create or replace function public.sd_public_site_safe_url(p_value text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when p_value is null or btrim(p_value) = '' then false
    when left(btrim(p_value), 1) = '/' and left(btrim(p_value), 2) <> '//' then true
    when btrim(p_value) ~* '^https?://[^[:space:]]+$' then true
    else false
  end;
$$;
create or replace function public.sd_public_site_luminance(p_hex text)
returns double precision
language plpgsql
immutable
set search_path = public
as $$
declare
  v_bytes bytea;
  v_red double precision;
  v_green double precision;
  v_blue double precision;
begin
  if p_hex is null or p_hex !~ '^#[0-9A-Fa-f]{6}$' then
    return -1;
  end if;
  v_bytes := decode(substr(p_hex, 2), 'hex');
  v_red := get_byte(v_bytes, 0) / 255.0;
  v_green := get_byte(v_bytes, 1) / 255.0;
  v_blue := get_byte(v_bytes, 2) / 255.0;
  v_red := case when v_red <= 0.03928 then v_red / 12.92 else power((v_red + 0.055) / 1.055, 2.4) end;
  v_green := case when v_green <= 0.03928 then v_green / 12.92 else power((v_green + 0.055) / 1.055, 2.4) end;
  v_blue := case when v_blue <= 0.03928 then v_blue / 12.92 else power((v_blue + 0.055) / 1.055, 2.4) end;
  return 0.2126 * v_red + 0.7152 * v_green + 0.0722 * v_blue;
end;
$$;
create or replace function public.sd_public_site_contrast_ratio(p_first text, p_second text)
returns double precision
language sql
immutable
set search_path = public
as $$
  select case
    when public.sd_public_site_luminance(p_first) < 0 or public.sd_public_site_luminance(p_second) < 0 then 0
    else (greatest(public.sd_public_site_luminance(p_first), public.sd_public_site_luminance(p_second)) + 0.05)
      / (least(public.sd_public_site_luminance(p_first), public.sd_public_site_luminance(p_second)) + 0.05)
  end;
$$;
revoke all on function public.sd_public_site_safe_url(text) from public;
revoke all on function public.sd_public_site_luminance(text) from public;
revoke all on function public.sd_public_site_contrast_ratio(text, text) from public;
create or replace function public.sd_publish_public_site(
  p_site_id uuid,
  p_expected_revision integer
)
returns table(version_id uuid, version_number integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site public.sd_public_sites%rowtype;
  v_number integer;
  v_version_id uuid;
  v_snapshot jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_page public.sd_public_site_pages%rowtype;
  v_form public.sd_public_form_definitions%rowtype;
  v_nav public.sd_public_site_navigation_items%rowtype;
  v_block jsonb;
  v_action jsonb;
  v_target text;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
begin
  select * into v_site from public.sd_public_sites where id = p_site_id for update;
  if v_site.id is null or not public.sd_public_site_can_manage(v_site.org_id) then
    raise exception 'website_admin_required';
  end if;
  if v_site.draft_revision <> p_expected_revision then
    raise exception 'website_revision_conflict';
  end if;
  if not exists (select 1 from public.sd_public_site_pages where site_id = p_site_id and is_home and status <> 'hidden') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'homepage_required', 'message', 'A visible homepage is required.'));
  end if;
  for v_page in
    select * from public.sd_public_site_pages where site_id = p_site_id and status <> 'hidden'
  loop
    if btrim(v_page.title) = '' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'page_title_required', 'message', 'Every page needs a title.', 'page_id', v_page.id));
    end if;
    if jsonb_typeof(v_page.blocks) <> 'array' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'invalid_page_blocks', 'message', 'A page contains invalid section data.', 'page_id', v_page.id));
      continue;
    end if;
    if jsonb_array_length(v_page.blocks) = 0 then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'empty_page', 'message', 'A published page has no sections.', 'page_id', v_page.id));
    end if;

    for v_block in select value from jsonb_array_elements(v_page.blocks)
    loop
      if v_block ->> 'type' in ('contact_form', 'registration_form', 'paid_form', 'custom_form') then
        v_target := nullif(v_block #>> '{data,form_id}', '');
        if v_target is null or not exists (
          select 1 from public.sd_public_form_definitions form_row
          where form_row.id::text = v_target and form_row.site_id = p_site_id and form_row.is_active
        ) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'form_not_connected', 'message', 'Every form section must be connected to an active form.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
        end if;
      end if;

      if v_block #>> '{background,mode}' = 'image'
        and nullif(v_block #>> '{background,media_id}', '') is null
        and nullif(v_block #>> '{background,image_url}', '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'background_image_missing', 'message', 'An image background is missing its image.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
      end if;

      if v_block ->> 'type' = 'image_text'
        and (nullif(v_block #>> '{content,media_id}', '') is not null or nullif(v_block #>> '{content,image_url}', '') is not null)
        and nullif(btrim(v_block #>> '{content,image_alt}'), '') is null then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'image_alt_required', 'message', 'Meaningful images need alt text.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
      end if;

      if v_block #>> '{visibility,mode}' = 'scheduled' then
        begin
          v_starts_at := (v_block #>> '{visibility,starts_at}')::timestamptz;
          v_ends_at := (v_block #>> '{visibility,ends_at}')::timestamptz;
          if v_starts_at >= v_ends_at then
            raise exception 'invalid_visibility_schedule';
          end if;
        exception when others then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'visibility_schedule_invalid', 'message', 'Scheduled sections need a valid start time before their end time.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
        end;
      end if;

      if jsonb_typeof(v_block -> 'actions') = 'array' then
        for v_action in select value from jsonb_array_elements(v_block -> 'actions')
        loop
          if v_action #>> '{destination,type}' = 'page' and not exists (
            select 1 from public.sd_public_site_pages target_page
          where target_page.id::text = (v_action #>> '{destination,page_id}') and target_page.site_id = p_site_id and target_page.status <> 'hidden'
          ) then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'button_destination_missing', 'message', 'A button points to a hidden or missing page.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
          end if;
          if v_action #>> '{destination,type}' = 'form' and not exists (
            select 1 from public.sd_public_form_definitions target_form
            where target_form.id::text = (v_action #>> '{destination,form_id}') and target_form.site_id = p_site_id and target_form.is_active
          ) then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'button_form_missing', 'message', 'A button points to a missing form.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
          end if;
          if v_action #>> '{destination,type}' in ('external', 'file')
            and not public.sd_public_site_safe_url(v_action #>> '{destination,value}') then
            v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'button_destination_invalid', 'message', 'A button has an invalid public destination.', 'page_id', v_page.id, 'block_id', v_block ->> 'id'));
          end if;
        end loop;
      end if;
    end loop;
  end loop;

  for v_form in
    select * from public.sd_public_form_definitions where site_id = p_site_id and is_active
  loop
    if jsonb_typeof(v_form.fields) <> 'array' or jsonb_array_length(v_form.fields) = 0 then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'form_fields_required', 'message', 'Every active form needs at least one field.', 'form_id', v_form.id));
    end if;
    if v_form.payment ->> 'enabled' = 'true' then
      if v_form.payment ->> 'mode' = 'options' then
        if jsonb_typeof(v_form.payment -> 'options') <> 'array' then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'paid_form_price_invalid', 'message', 'A paid form needs valid server-owned price options.', 'form_id', v_form.id));
        elsif jsonb_array_length(v_form.payment -> 'options') = 0
          or exists (
            select 1 from jsonb_array_elements(v_form.payment -> 'options') option_row
            where case
              when coalesce(option_row ->> 'amount_cents', '') ~ '^[0-9]+$'
                then (option_row ->> 'amount_cents')::integer
              else 0
            end < 50
          ) then
          v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'paid_form_price_invalid', 'message', 'A paid form needs valid server-owned price options.', 'form_id', v_form.id));
        end if;
      elsif (case
        when coalesce(v_form.payment ->> 'fixed_amount_cents', '') ~ '^[0-9]+$'
          then (v_form.payment ->> 'fixed_amount_cents')::integer
        else 0
      end) < 50 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'paid_form_price_invalid', 'message', 'A paid form needs a valid server-owned fixed price.', 'form_id', v_form.id));
      end if;
    end if;
    if nullif(v_form.confirmation ->> 'redirect_url', '') is not null
      and not public.sd_public_site_safe_url(v_form.confirmation ->> 'redirect_url') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'form_redirect_invalid', 'message', 'A form has an invalid confirmation redirect.', 'form_id', v_form.id));
    end if;
  end loop;

  for v_nav in
    select * from public.sd_public_site_navigation_items where site_id = p_site_id and is_visible
  loop
    if btrim(v_nav.label) = '' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'navigation_label_required', 'message', 'Every visible navigation item needs a label.', 'navigation_id', v_nav.id));
    end if;
    if v_nav.item_type = 'page' and not exists (
      select 1 from public.sd_public_site_pages target_page where target_page.id = v_nav.page_id and target_page.site_id = p_site_id and target_page.status <> 'hidden'
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'navigation_page_missing', 'message', 'A navigation item points to a hidden or missing page.', 'navigation_id', v_nav.id));
    end if;
    if v_nav.item_type = 'form' and not exists (
      select 1 from public.sd_public_form_definitions target_form where target_form.id::text = (v_nav.destination ->> 'form_id') and target_form.site_id = p_site_id and target_form.is_active
    ) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'navigation_form_missing', 'message', 'A navigation item points to a missing form.', 'navigation_id', v_nav.id));
    end if;
    if v_nav.item_type in ('external', 'file') and not public.sd_public_site_safe_url(v_nav.destination ->> 'value') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'navigation_destination_invalid', 'message', 'A navigation item has an invalid public destination.', 'navigation_id', v_nav.id));
    end if;
  end loop;

  if nullif(v_site.settings #>> '{header_cta,label}', '') is not null
    and not public.sd_public_site_safe_url(v_site.settings #>> '{header_cta,href}') then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'header_cta_invalid', 'message', 'The header action button has an invalid destination.'));
  end if;
  if public.sd_public_site_contrast_ratio(
    coalesce(nullif(v_site.theme ->> 'text', ''), '#171A18'),
    coalesce(nullif(v_site.theme ->> 'background', ''), '#F6F4EE')
  ) < 4.5 then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code', 'theme_contrast_invalid', 'message', 'Body text and background colors do not meet WCAG contrast requirements.'));
  end if;

  if (select count(*) from public.sd_public_site_navigation_items where site_id = p_site_id and location = 'header' and parent_id is null and is_visible) > 7 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'header_navigation_crowded', 'message', 'More than seven top-level links may crowd the header.'));
  end if;
  if jsonb_array_length(v_errors) > 0 then
    raise exception 'website_validation_failed:%', v_errors::text;
  end if;

  select coalesce(max(site_version.version_number), 0) + 1
  into v_number
  from public.sd_public_site_versions as site_version
  where site_version.site_id = p_site_id;

  select jsonb_build_object(
    'schema_version', 2,
    'site', jsonb_build_object('slug', v_site.slug, 'name', v_site.name, 'theme', v_site.theme, 'settings', v_site.settings),
    'pages', coalesce((
      select jsonb_agg(to_jsonb(page_row) - 'created_by' - 'updated_by' - 'created_at' - 'updated_at' order by page_row.sort_order, page_row.created_at)
      from public.sd_public_site_pages page_row where page_row.site_id = p_site_id and page_row.status <> 'hidden'
    ), '[]'::jsonb),
    'navigation', coalesce((
      select jsonb_agg(to_jsonb(nav_row) - 'created_by' - 'updated_by' - 'created_at' - 'updated_at' order by nav_row.location, nav_row.sort_order, nav_row.created_at)
      from public.sd_public_site_navigation_items nav_row where nav_row.site_id = p_site_id and nav_row.is_visible
    ), '[]'::jsonb),
    'forms', coalesce((
      select jsonb_agg(to_jsonb(form_row) - 'created_by' - 'updated_by' - 'created_at' - 'updated_at')
      from public.sd_public_form_definitions form_row where form_row.site_id = p_site_id and form_row.is_active
    ), '[]'::jsonb),
    'published_at', now()
  ) into v_snapshot;

  insert into public.sd_public_site_versions(site_id, org_id, version_number, snapshot, validation, published_by)
  values (p_site_id, v_site.org_id, v_number, v_snapshot, jsonb_build_object('status', 'passed', 'errors', v_errors, 'warnings', v_warnings), auth.uid())
  returning id into v_version_id;

  update public.sd_public_sites
  set status = 'published', published_version_id = v_version_id, updated_by = auth.uid(), updated_at = now()
  where id = p_site_id;

  insert into public.sd_public_site_audit_log(site_id, org_id, actor_id, action, target_type, target_id, details)
  values (p_site_id, v_site.org_id, auth.uid(), 'publish', 'site', p_site_id::text, jsonb_build_object('version', v_number, 'schema_version', 2, 'warnings', v_warnings));

  return query select v_version_id, v_number;
end;
$$;
revoke all on function public.sd_publish_public_site(uuid, integer) from public;
grant execute on function public.sd_publish_public_site(uuid, integer) to authenticated;
insert into public.sd_public_site_navigation_items(
  site_id, org_id, location, item_type, label, page_id, destination,
  sort_order, is_visible, created_by, updated_by
)
select page.site_id, page.org_id,
  case when page.navigation_location in ('header', 'footer', 'utility') then page.navigation_location else 'header' end,
  'page', page.title, page.id, jsonb_build_object('page_id', page.id),
  page.sort_order, page.status <> 'hidden', page.created_by, page.updated_by
from public.sd_public_site_pages page
where page.navigation_location <> 'hidden'
  and not exists (
    select 1 from public.sd_public_site_navigation_items nav
    where nav.site_id = page.site_id and nav.page_id = page.id
  );
alter table public.sd_public_site_navigation_items enable row level security;
alter table public.sd_public_registration_submissions enable row level security;
alter table public.sd_public_form_uploads enable row level security;
alter table public.sd_public_request_limits enable row level security;
create policy sd_public_site_navigation_items_manage on public.sd_public_site_navigation_items
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_registration_submissions_manage on public.sd_public_registration_submissions
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
create policy sd_public_form_uploads_manage on public.sd_public_form_uploads
  for all to authenticated
  using (public.sd_public_site_can_manage(org_id))
  with check (public.sd_public_site_can_manage(org_id));
grant select, insert, update, delete on public.sd_public_site_navigation_items to authenticated;
grant select, insert, update, delete on public.sd_public_registration_submissions to authenticated;
grant select, insert, update, delete on public.sd_public_form_uploads to authenticated;
revoke all on public.sd_public_request_limits from anon, authenticated;
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'public-form-uploads', 'public-form-uploads', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/csv']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create policy sd_public_form_uploads_storage_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'public-form-uploads'
    and exists (
      select 1 from public.sd_org_memberships membership
      where membership.org_id::text = (storage.foldername(name))[1]
        and membership.user_id = auth.uid()
        and membership.status = 'active'
        and membership.role in ('owner', 'admin')
    )
  );
commit;
