-- Phase 12ZA compatibility repair for setup-created practices.
--
-- The original organization-setup function created the authoritative event and
-- recorded it in sd_organization_setup_entities, but did not create the
-- canonical practice subtype row. Provenance plus event_type makes this repair
-- unambiguous. Defaults on sd_team_event_practices are the canonical defaults
-- for a newly drafted practice.

insert into public.sd_team_event_practices (event_id)
select event.id
from public.sd_team_events as event
join public.sd_organization_setup_entities as provenance
  on provenance.organization_id = event.organization_id
 and provenance.entity_type = 'team_event'
 and provenance.entity_id = event.id
 and provenance.created_via_setup
left join public.sd_team_event_practices as practice
  on practice.event_id = event.id
where event.event_type = 'practice'
  and practice.event_id is null
on conflict (event_id) do nothing;

-- This migration never rewrites the parent event and cannot match games,
-- tournaments, meetings, travel, custom events, or events without explicit
-- setup provenance. It is safe to re-run.
