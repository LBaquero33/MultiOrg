-- Additive compatibility repair for the parent-code generator.
--
-- pgcrypto is installed in the extensions schema in hosted Supabase. Qualifying
-- gen_random_bytes keeps the existing algorithm and privileges unchanged while
-- allowing database lint and restricted-search-path execution to resolve it.
create or replace function public.sd_generate_parent_code(size int default 8)
returns text
language plpgsql
volatile
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(size);
  out text := '';
  i int;
  idx int;
begin
  if size < 4 then
    size := 4;
  end if;

  for i in 0..(size - 1) loop
    idx := (get_byte(bytes, i) % length(alphabet)) + 1;
    out := out || substr(alphabet, idx, 1);
  end loop;
  return out;
end;
$$;
