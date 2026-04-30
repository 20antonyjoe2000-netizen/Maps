-- supabase/migrations/002_run_points_rpc.sql
-- NOTE: use DROP FUNCTION first if the return type changes in a future migration
create or replace function get_run_points_coords(p_run_id uuid)
returns table(seq int4, lng float8, lat float8)
language sql stable security invoker
set search_path = public, extensions, auth
as $$
  select rp.seq,
         st_x(rp.location::geometry)::float8,
         st_y(rp.location::geometry)::float8
  from run_points rp
  join runs r on r.id = rp.run_id
  where rp.run_id = p_run_id
    and r.user_id = auth.uid()
  order by rp.seq;
$$;

grant execute on function get_run_points_coords(uuid) to authenticated;
