-- Align web calendar visibility with the active Phase 12 roster model.
-- Coach-created events are team-scoped unless the coach has explicit
-- organization-wide access. Draft events remain staff-only.

create or replace function public.sd_can_schedule_event(
  p_org_id uuid,
  p_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.sd_is_org_admin(p_org_id)
    or (
      public.sd_is_org_staff(p_org_id)
      and exists (
        select 1
        from public.sd_coach_team_assignments assignment
        where assignment.organization_id = p_org_id
          and assignment.coach_id = auth.uid()
          and assignment.active
          and assignment.ended_at is null
          and (
            assignment.organization_wide_access
            or (p_team_id is not null and assignment.team_id = p_team_id)
          )
      )
    );
$$;
create or replace function public.sd_can_manage_event(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_events event
    where event.id = p_event_id
      and (
        public.sd_is_org_admin(event.org_id)
        or (
          event.created_by = auth.uid()
          and public.sd_can_schedule_event(event.org_id, event.team_id)
        )
        or exists (
          select 1
          from public.sd_event_participants participant
          where participant.event_id = event.id
            and participant.user_id = auth.uid()
            and participant.can_edit
            and public.sd_is_org_staff(event.org_id)
        )
      )
  );
$$;
create or replace function public.sd_can_view_event(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_events event
    where event.id = p_event_id
      and (
        event.status <> 'draft'
        or public.sd_can_manage_event(event.id)
      )
      and (
        public.sd_is_platform_admin_game_support()
        or public.sd_is_org_admin(event.org_id)
        or (
          event.visibility = 'organization'
          and public.sd_is_org_member(event.org_id)
        )
        or (
          event.visibility in ('team', 'participants')
          and event.team_id is not null
          and exists (
            select 1
            from public.sd_player_team_memberships membership
            where membership.organization_id = event.org_id
              and membership.team_id = event.team_id
              and membership.player_id = auth.uid()
              and membership.active
              and membership.ended_at is null
          )
        )
        or (
          event.visibility in ('team', 'participants')
          and event.team_id is not null
          and exists (
            select 1
            from public.sd_player_team_memberships membership
            join public.sd_parent_child_links link
              on link.org_id = membership.organization_id
             and link.child_id = membership.player_id
             and link.parent_id = auth.uid()
            where membership.organization_id = event.org_id
              and membership.team_id = event.team_id
              and membership.active
              and membership.ended_at is null
          )
        )
        or exists (
          select 1
          from public.sd_event_participants participant
          where participant.event_id = event.id
            and participant.org_id = event.org_id
            and participant.can_view
            and (
              participant.user_id = auth.uid()
              or (
                participant.team_id is not null
                and exists (
                  select 1
                  from public.sd_player_team_memberships membership
                  where membership.organization_id = event.org_id
                    and membership.team_id = participant.team_id
                    and membership.player_id = auth.uid()
                    and membership.active
                    and membership.ended_at is null
                )
              )
              or (
                participant.player_id is not null
                and public.sd_is_linked_parent_in_org(
                  auth.uid(), participant.player_id, event.org_id
                )
              )
            )
        )
        or exists (
          select 1
          from public.sd_event_participants child_participant
          join public.sd_parent_child_links link
            on link.org_id = event.org_id
           and link.child_id = child_participant.user_id
           and link.parent_id = auth.uid()
          where child_participant.event_id = event.id
            and child_participant.participant_type = 'player'
            and child_participant.can_view
        )
      )
  );
$$;
create or replace function public.sd_event_notification_recipients(p_event_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with event_scope as (
    select id, org_id, team_id
    from public.sd_events
    where id = p_event_id and status <> 'draft'
  ),
  recipients as (
    select participant.user_id
    from public.sd_event_participants participant
    join event_scope scope on scope.id = participant.event_id
    where participant.can_view and participant.user_id is not null
    union
    select membership.player_id
    from public.sd_player_team_memberships membership
    join event_scope scope
      on scope.org_id = membership.organization_id
     and scope.team_id = membership.team_id
    where membership.active and membership.ended_at is null
    union
    select link.parent_id
    from public.sd_parent_child_links link
    join event_scope scope on scope.org_id = link.org_id
    join public.sd_player_team_memberships membership
      on membership.organization_id = scope.org_id
     and membership.team_id = scope.team_id
     and membership.player_id = link.child_id
    where membership.active and membership.ended_at is null
  )
  select coalesce(array_agg(distinct user_id), array[]::uuid[])
  from recipients
  where user_id is not null;
$$;
drop policy if exists "sd_events_insert_admin" on public.sd_events;
drop policy if exists "sd_events_insert_scheduler" on public.sd_events;
create policy "sd_events_insert_scheduler" on public.sd_events
for insert to authenticated
with check (
  public.sd_can_schedule_event(org_id, team_id)
  and created_by = auth.uid()
  and updated_by = auth.uid()
  and status in ('draft', 'scheduled')
  and (
    (team_id is null and visibility = 'organization')
    or (team_id is not null and visibility in ('team', 'participants'))
  )
);
revoke all on function public.sd_can_schedule_event(uuid, uuid) from public, anon;
revoke all on function public.sd_can_manage_event(uuid) from public, anon;
revoke all on function public.sd_can_view_event(uuid) from public, anon;
revoke all on function public.sd_event_notification_recipients(uuid) from public, anon;
grant execute on function public.sd_can_schedule_event(uuid, uuid) to authenticated, service_role;
grant execute on function public.sd_can_manage_event(uuid) to authenticated, service_role;
grant execute on function public.sd_can_view_event(uuid) to authenticated, service_role;
grant execute on function public.sd_event_notification_recipients(uuid) to service_role;
