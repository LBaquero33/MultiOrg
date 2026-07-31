begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select is(
  pg_get_function_result('public.sd_generate_parent_code(integer)'::regprocedure),
  'text',
  'parent-code generator retains its text return type'
);

select lives_ok(
  $$select public.sd_generate_parent_code()$$,
  'parent-code generator executes with its default argument'
);

select matches(
  public.sd_generate_parent_code(),
  '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$',
  'default parent code retains the eight-character human-friendly format'
);

select matches(
  public.sd_generate_parent_code(12),
  '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$',
  'explicit parent-code size retains the existing format'
);

select is(
  (
    select count(*)::bigint
    from generate_series(1, 24)
    where public.sd_generate_parent_code(8)
      ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$'
  ),
  24::bigint,
  'a bounded batch of parent codes is generated successfully'
);

select ok(
  position(
    'extensions.gen_random_bytes(size)'
    in pg_get_functiondef('public.sd_generate_parent_code(integer)'::regprocedure)
  ) > 0,
  'parent-code randomness is explicitly resolved from the extensions schema'
);

select ok(
  position(
    'bytes bytea := gen_random_bytes(size)'
    in pg_get_functiondef('public.sd_generate_parent_code(integer)'::regprocedure)
  ) = 0,
  'parent-code function no longer contains the unqualified random-byte call'
);

select ok(
  has_function_privilege(
    'anon',
    'public.sd_generate_parent_code(integer)',
    'EXECUTE'
  ),
  'anon retains its existing execute privilege'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.sd_generate_parent_code(integer)',
    'EXECUTE'
  ),
  'authenticated retains its existing execute privilege'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.sd_generate_parent_code(integer)',
    'EXECUTE'
  ),
  'service role retains its existing execute privilege'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    join pg_class table_row on table_row.oid = constraint_row.conrelid
    join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'sd_parent_codes'
      and constraint_row.contype = 'u'
      and pg_get_constraintdef(constraint_row.oid)
        = 'UNIQUE (parent_code)'
  ),
  'the existing database collision guard remains intact'
);

select * from finish();

rollback;
