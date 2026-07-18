-- Repair the Phase 12E mutation receipt response variable on databases where
-- the original function was installed before the source migration correction.
-- The guarded rewrite is a no-op on clean databases that already use
-- v_response and preserves the complete authoritative mutation function.

do $repair$
declare
  definition text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.sd_apply_game_plan_mutation(uuid,uuid,uuid,text,uuid,jsonb)'::pg_catalog.regprocedure
  ) into definition;

  definition := pg_catalog.replace(
    definition,
    'fingerprint text; response jsonb;',
    'fingerprint text; v_response jsonb;'
  );
  definition := pg_catalog.replace(
    definition,
    ' response:=',
    ' v_response:='
  );
  definition := pg_catalog.replace(
    definition,
    'previous,response,reason',
    'previous,v_response,reason'
  );
  definition := pg_catalog.replace(
    definition,
    'response=sd_apply_game_plan_mutation.response',
    'response=v_response'
  );
  definition := pg_catalog.replace(
    definition,
    'response=response',
    'response=v_response'
  );
  definition := pg_catalog.replace(
    definition,
    'return response;',
    'return v_response;'
  );

  if pg_catalog.strpos(definition, 'fingerprint text; v_response jsonb;') = 0
    or pg_catalog.strpos(definition, 'response=v_response') = 0
    or pg_catalog.strpos(definition, 'return v_response;') = 0
    or pg_catalog.strpos(definition, ' response:=') > 0
    or pg_catalog.strpos(
      definition,
      'response=sd_apply_game_plan_mutation.response'
    ) > 0
    or pg_catalog.strpos(definition, 'response=response') > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'unexpected_sd_apply_game_plan_mutation_definition';
  end if;

  execute definition;
end;
$repair$;
