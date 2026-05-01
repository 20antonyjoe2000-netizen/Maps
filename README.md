# Runner Map

Flutter app for recording outdoor runs. Tracks your GPS route in real time — including when the phone screen is off — and lets you review past runs with a route preview map.

## Features

- Live GPS route tracking with Mapbox
- Background tracking survives screen-off (Android foreground service)
- Saves runs and points to Supabase
- Run history screen with distance, duration, and pace
- Tap any past run to see the route drawn on a map

## Tech Stack

| Layer | Tech |
|-------|------|
| UI | Flutter (Dart) |
| Maps | Mapbox Maps Flutter SDK |
| Backend | Supabase (Postgres + PostGIS) |
| Auth | Supabase Auth |
| Location | geolocator + Android foreground service |

## Setup

### 1. Clone

```bash
git clone https://github.com/20antonyjoe2000-netizen/Map.git
cd Map
```

### 2. Add your keys

```bash
cp lib/config.example.dart lib/config.dart
```

Edit `lib/config.dart` and fill in:
- `mapboxToken` — Mapbox public token (`pk.*`) from [mapbox.com](https://account.mapbox.com)
- `supabaseUrl` — your Supabase project URL
- `supabaseAnonKey` — your Supabase anon/public key

### 3. Mapbox SDK download token

Add your Mapbox **secret** downloads token to `~/.gradle/gradle.properties`:

```
MAPBOX_DOWNLOADS_TOKEN=sk.eyJ1...
```

### 4. Supabase schema

Apply migrations in order from `supabase/migrations/`.

### 5. Run

```bash
flutter pub get
flutter run
```

## Database Schema

- `runs` — one row per run (`user_id`, `started_at`, `distance_meters`, `duration_seconds`, `avg_pace_sec_per_km`)
- `run_points` — GPS points per run (`run_id`, `seq`, `location` as `geography(POINT,4326)`)
- `get_run_points_coords(run_id)` — RPC returning `(seq, lng, lat)` floats

## Android Permissions

`ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`
