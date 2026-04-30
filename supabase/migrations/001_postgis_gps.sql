-- Requires: PostGIS extension enabled in Supabase dashboard

-- runs table
create table if not exists runs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users not null,
  started_at      timestamptz not null,
  ended_at        timestamptz not null,
  distance_meters double precision,
  duration_seconds int,
  avg_pace_sec_per_km double precision,
  route           geography(LINESTRING, 4326)
);

alter table runs enable row level security;
create policy "users own runs" on runs
  for all using (auth.uid() = user_id);

create index runs_route_gist on runs using gist(route);

-- run_points table (single geography column instead of lat/lng)
create table if not exists run_points (
  id      bigserial primary key,
  run_id  uuid references runs(id) on delete cascade not null,
  seq     int not null,
  location geography(POINT, 4326) not null
);

alter table run_points enable row level security;
create policy "users own run_points" on run_points
  for all using (
    exists (
      select 1 from runs
      where runs.id = run_points.run_id
        and runs.user_id = auth.uid()
    )
  );

create index run_points_run_id_idx on run_points(run_id, seq);
create index run_points_location_gist on run_points using gist(location);
