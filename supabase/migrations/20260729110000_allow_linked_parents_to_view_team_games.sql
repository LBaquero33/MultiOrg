-- A linked parent may view a team-scoped event when their child is an active
-- roster member of that event's team.

create or replace function public.sd_can_view_event(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sd_events e
    where e.id = p_event_id
      and (
        public.sd_is_platform_admin_game_support()
        or public.sd_is_org_admin(e.org_id)
        or (
          e.visibility = 'organization'
          and public.sd_is_org_member(e.org_id)
        )
        or (
          e.visibility in ('team', 'participants')
          and e.team_id is not null
          and exists (
            select 1
            from public.sd_team_members tm
            where tm.org_id = e.org_id
              and tm.team_id = e.team_id
              and tm.player_id = auth.uid()
          )
        )
        or (
          e.visibility in ('team', 'participants')
          and e.team_id is not null
          and exists (
            select 1
            from public.sd_team_members tm
            join public.sd_parent_child_links link
              on link.org_id = tm.org_id
             and link.child_id = tm.player_id
             and link.parent_id = auth.uid()
            where tm.org_id = e.org_id
              and tm.team_id = e.team_id
          )
        )
        or exists (
          select 1
          from public.sd_event_participants p
          where p.event_id = e.id
            and p.org_id = e.org_id
            and p.can_view
            and (
              p.user_id = auth.uid()
              or (
                p.team_id is not null
                and exists (
                  select 1
                  from public.sd_team_members tm
                  where tm.org_id = e.org_id
                    and tm.team_id = p.team_id
                    and tm.player_id = auth.uid()
                )
              )
              or (
                p.player_id is not null
                and public.sd_is_linked_parent_in_org(auth.uid(), p.player_id, e.org_id)
              )
            )
        )
        or exists (
          select 1
          from public.sd_event_participants child_participant
          join public.sd_parent_child_links link
            on link.org_id = e.org_id
           and link.child_id = child_participant.user_id
           and link.parent_id = auth.uid()
          where child_participant.event_id = e.id
            and child_participant.participant_type = 'player'
            and child_participant.can_view
        )
      )
  );
$$;

revoke all on function public.sd_can_view_event(uuid) from public, anon;
grant execute on function public.sd_can_view_event(uuid) to authenticated, service_role;
