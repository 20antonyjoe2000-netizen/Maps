# Background GPS Tracking Fix + Run History Screen

**Date:** 2026-04-30  
**Status:** Approved

---

## Problem

GPS path is inaccurate (km-scale jumps) when phone screen turns off. Android Doze mode throttles location updates without a foreground service, causing batched/stale fixes.

No history screen exists — users cannot review past runs.

---

## Change 1: Background GPS Tracking Fix

### Root Cause

`LocationSettings` with no foreground service config. Android kills/throttles location updates in Doze mode. Fix: geolocator foreground service keeps GPS receiver active continuously.

### AndroidManifest Changes

- Add `ACCESS_BACKGROUND_LOCATION` permission (Android 10+ requirement for foreground service location)
- Declare `<service android:name="com.baseflow.geolocator.GeolocatorService" android:foregroundServiceType="location" />`

### Code Change

In `_startTracking()`, replace:
```dart
geo.LocationSettings(accuracy: geo.LocationAccuracy.high, distanceFilter: 5)
```
with:
```dart
geo.AndroidSettings(
  accuracy: geo.LocationAccuracy.high,
  distanceFilter: 5,
  foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
    notificationTitle: 'Run in progress',
    notificationText: 'Tracking your route',
    enableWakeLock: true,
  ),
)
```

### Permission Flow

Request `LocationPermission.always` instead of accepting `whileInUse`. Show rationale snackbar if denied, gracefully fall back.

---

## Change 2: Run History Screen

### Files

| File | Purpose |
|------|---------|
| `lib/screens/history_screen.dart` | List of past runs |
| `lib/screens/run_detail_sheet.dart` | Bottom sheet: map + stats for one run |
| `lib/screens/map_screen.dart` | Add history button (top-left when not tracking) |

### History Screen

- Fetches on mount: `runs` table, columns `id, started_at, distance_meters, duration_seconds, avg_pace_sec_per_km`, ordered by `started_at desc`, limit 50
- List tile per run: date (formatted), distance, duration, pace
- Loading / empty / error states
- Tap row → shows `RunDetailSheet` as modal bottom sheet

### Run Detail Sheet

- `DraggableScrollableSheet` (initial 60%, max 95%)
- Top half: `MapWidget` (Mapbox OUTDOORS style) — draws route polyline on `onMapCreated`, fits camera to route bounds with padding
- Bottom half: stats row (distance / duration / pace) + formatted date
- If run has < 2 points: show "No route data" message instead of map
- Fetches `run_points` for the run lazily (only when sheet opens): `select seq, location` ordered by `seq`, parses PostgREST GeoJSON response `{"type":"Point","coordinates":[lng,lat]}` → `Position`

### Navigation

- `map_screen.dart`: history icon button (`Icons.history`) top-left, visible only when `!_isTracking && !_saving`
- Pushes `HistoryScreen` via `Navigator.push`

---

## Error Handling

- Supabase fetch errors: show `SnackBar` with message, list stays empty
- Route fetch error in sheet: show error text inside sheet
- Permission permanently denied: show settings-redirect dialog
- Run with 0–1 points: "No route data" placeholder in sheet map area

---

## Out of Scope

- Deleting runs
- Filtering/sorting history
- iOS-specific background location (requires separate `Info.plist` keys — address when iOS is targeted)
