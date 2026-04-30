# Background GPS Tracking Fix + Run History Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix GPS tracking going offline when phone screen turns off, and add a run history screen with a route preview map.

**Architecture:** A Supabase RPC function returns run point coordinates cleanly. An Android foreground service (via geolocator's `AndroidSettings`) keeps GPS alive through Doze mode. Two new screens — `HistoryScreen` (list) and `RunDetailSheet` (bottom sheet with map) — plus shared formatting helpers extracted to a utility file.

**Tech Stack:** Flutter, Dart, geolocator ^13.0.0, mapbox_maps_flutter ^2.3.0, supabase_flutter ^2.8.4, Android foreground service

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `supabase/migrations/002_run_points_rpc.sql` | Create | RPC returning lng/lat from geography column |
| `android/app/src/main/AndroidManifest.xml` | Modify | Background location permission + foreground service declaration |
| `lib/utils/run_format.dart` | Create | Shared distance/duration/pace/date formatters |
| `test/run_format_test.dart` | Create | Unit tests for formatters |
| `lib/screens/map_screen.dart` | Modify | Use `AndroidSettings` + add history button |
| `lib/screens/history_screen.dart` | Create | Scrollable list of past runs |
| `lib/screens/run_detail_sheet.dart` | Create | Bottom sheet: Mapbox map + stats |

---

## Task 1: Supabase RPC for run point coordinates

`run_points.location` is `geography(POINT,4326)`. PostgREST returns geography as binary hex — unusable in Dart. This RPC returns plain floats.

**Files:**
- Create: `supabase/migrations/002_run_points_rpc.sql`

- [ ] **Step 1: Write migration SQL**

```sql
-- supabase/migrations/002_run_points_rpc.sql
create or replace function get_run_points_coords(p_run_id uuid)
returns table(seq int4, lng float8, lat float8)
language sql stable security invoker as $$
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
```

- [ ] **Step 2: Apply migration via Supabase MCP**

Use `mcp__supabase__apply_migration` with the SQL above. Verify success — no error means the function is live.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/002_run_points_rpc.sql
git commit -m "feat: add get_run_points_coords RPC for geography → float extraction"
```

---

## Task 2: Android manifest — background location + foreground service

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add permissions and service declaration**

Open `android/app/src/main/AndroidManifest.xml`. Add `ACCESS_BACKGROUND_LOCATION` after the existing location permissions, and declare the geolocator foreground service inside `<application>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <application
        android:label="map"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service
            android:name="com.baseflow.geolocator.GeolocatorService"
            android:foregroundServiceType="location"/>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

- [ ] **Step 2: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "feat: add background location permission and geolocator foreground service"
```

---

## Task 3: Shared formatting utilities

Extract reusable formatters so `HistoryScreen` and `RunDetailSheet` don't duplicate code.

**Files:**
- Create: `lib/utils/run_format.dart`
- Create: `test/run_format_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/run_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:map/utils/run_format.dart';

void main() {
  group('formatDistance', () {
    test('returns km string when >= 1000 m', () {
      expect(formatDistance(1500), '1.50 km');
    });
    test('returns m string when < 1000 m', () {
      expect(formatDistance(500), '500 m');
    });
    test('returns -- for null', () {
      expect(formatDistance(null), '--');
    });
  });

  group('formatDuration', () {
    test('formats seconds into mm:ss', () {
      expect(formatDuration(90), '01:30');
    });
    test('returns -- for null', () {
      expect(formatDuration(null), '--');
    });
  });

  group('formatPace', () {
    test('formats sec/km into mm:ss /km', () {
      expect(formatPace(330), '05:30 /km');
    });
    test('returns --:-- for null', () {
      expect(formatPace(null), '--:--');
    });
  });

  group('formatDate', () {
    test('formats ISO string to d/m/yyyy hh:mm', () {
      final result = formatDate('2026-04-30T06:00:00.000Z');
      expect(result, matches(RegExp(r'^\d+/\d+/\d{4}  \d{2}:\d{2}$')));
    });
  });

  group('formatDateShort', () {
    test('formats ISO string to d/m/yyyy', () {
      final result = formatDateShort('2026-04-30T06:00:00.000Z');
      expect(result, matches(RegExp(r'^\d+/\d+/\d{4}$')));
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd /home/joe/App/map && flutter test test/run_format_test.dart
```

Expected: compile error — `package:map/utils/run_format.dart` not found.

- [ ] **Step 3: Create `lib/utils/run_format.dart`**

```dart
String formatDistance(dynamic meters) {
  if (meters == null) return '--';
  final km = (meters as num).toDouble() / 1000;
  return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${(meters as num).toInt()} m';
}

String formatDuration(dynamic seconds) {
  if (seconds == null) return '--';
  final s = (seconds as num).toInt();
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

String formatPace(dynamic secPerKm) {
  if (secPerKm == null) return '--:--';
  final s = (secPerKm as num).toInt();
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss /km';
}

String formatDate(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String formatDateShort(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  return '${dt.day}/${dt.month}/${dt.year}';
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd /home/joe/App/map && flutter test test/run_format_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/run_format.dart test/run_format_test.dart
git commit -m "feat: add run formatting utilities with tests"
```

---

## Task 4: Fix background GPS tracking in map_screen.dart

**Files:**
- Modify: `lib/screens/map_screen.dart`

The current `getPositionStream` uses plain `LocationSettings` — no foreground service. Android Doze kills GPS updates when screen turns off. Fix: use `AndroidSettings` with `foregroundNotificationConfig` on Android, fall back to `LocationSettings` on other platforms.

- [ ] **Step 1: Add `dart:io` import**

At the top of `lib/screens/map_screen.dart`, add after existing imports:

```dart
import 'dart:io' show Platform;
```

- [ ] **Step 2: Replace location stream settings in `_startTracking()`**

Find this block (around line 124):

```dart
    _locationSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onLocation);
```

Replace with:

```dart
    _locationSub = geo.Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? geo.AndroidSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 5,
              foregroundNotificationConfig:
                  const geo.ForegroundNotificationConfig(
                notificationTitle: 'Run in progress',
                notificationText: 'Tracking your route',
                enableWakeLock: true,
              ),
            )
          : const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 5,
            ),
    ).listen(_onLocation);
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/map_screen.dart
git commit -m "fix: use Android foreground service for GPS tracking to survive screen-off"
```

---

## Task 5: Create HistoryScreen

**Files:**
- Create: `lib/screens/history_screen.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/run_format.dart';
import 'run_detail_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _runs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRuns();
  }

  Future<void> _fetchRuns() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
          .from('runs')
          .select(
              'id, started_at, distance_meters, duration_seconds, avg_pace_sec_per_km')
          .eq('user_id', uid)
          .order('started_at', ascending: false)
          .limit(50);
      setState(() {
        _runs = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Failed to load runs: $_error'))
              : _runs.isEmpty
                  ? const Center(child: Text('No runs yet'))
                  : ListView.separated(
                      itemCount: _runs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final run = _runs[i];
                        return ListTile(
                          title: Text(
                              formatDate(run['started_at'] as String)),
                          subtitle: Text(
                              formatDistance(run['distance_meters'])),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatDuration(
                                  run['duration_seconds'])),
                              Text(
                                formatPace(
                                    run['avg_pace_sec_per_km']),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => RunDetailSheet(run: run),
                          ),
                        );
                      },
                    ),
    );
  }
}
```

- [ ] **Step 2: Verify app still compiles**

```bash
cd /home/joe/App/map && flutter analyze lib/screens/history_screen.dart
```

Expected: no errors (note: `run_detail_sheet.dart` import will warn until Task 6 creates it — that's fine).

- [ ] **Step 3: Commit**

```bash
git add lib/screens/history_screen.dart
git commit -m "feat: add HistoryScreen with run list from Supabase"
```

---

## Task 6: Create RunDetailSheet

**Files:**
- Create: `lib/screens/run_detail_sheet.dart`

The sheet fetches run points via the `get_run_points_coords` RPC (Task 1). It handles a race condition between map creation and data fetch by checking both are ready before drawing.

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/run_format.dart';

class RunDetailSheet extends StatefulWidget {
  final Map<String, dynamic> run;
  const RunDetailSheet({super.key, required this.run});

  @override
  State<RunDetailSheet> createState() => _RunDetailSheetState();
}

class _RunDetailSheetState extends State<RunDetailSheet> {
  List<Position>? _positions;
  MapboxMap? _map;
  bool _loading = true;
  bool _routeDrawn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPoints();
  }

  Future<void> _fetchPoints() async {
    try {
      final runId = widget.run['id'] as String;
      final data = await Supabase.instance.client
          .rpc('get_run_points_coords', params: {'p_run_id': runId});

      final positions = (data as List).map((row) {
        return Position(
          (row['lng'] as num).toDouble(),
          (row['lat'] as num).toDouble(),
        );
      }).toList();

      setState(() {
        _positions = positions;
        _loading = false;
      });

      _drawRoute();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    _drawRoute();
  }

  Future<void> _drawRoute() async {
    final map = _map;
    final positions = _positions;
    if (map == null || positions == null || positions.length < 2 || _routeDrawn) return;
    _routeDrawn = true;

    final lineManager =
        await map.annotations.createPolylineAnnotationManager();
    await lineManager.create(PolylineAnnotationOptions(
      geometry: LineString(coordinates: positions),
      lineColor: Colors.blue.value,
      lineWidth: 4.0,
      lineOpacity: 0.9,
    ));

    final lngs = positions.map((p) => (p[0] as num).toDouble());
    final lats = positions.map((p) => (p[1] as num).toDouble());
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);

    final bounds = CoordinateBounds(
      southwest: Point(coordinates: Position(minLng, minLat)),
      northeast: Point(coordinates: Position(maxLng, maxLat)),
      infiniteBounds: false,
    );
    final camera = await map.cameraForCoordinateBounds(
      bounds,
      MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
      null,
      null,
      null,
      null,
    );
    await map.setCamera(camera);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.35,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Failed to load route: $_error'))
                      : (_positions == null || _positions!.length < 2)
                          ? const Center(child: Text('No route data'))
                          : MapWidget(
                              styleUri: MapboxStyles.OUTDOORS,
                              onMapCreated: _onMapCreated,
                              cameraOptions: CameraOptions(
                                center: Point(
                                    coordinates: _positions!.first),
                                zoom: 14.0,
                              ),
                            ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('DISTANCE',
                      formatDistance(widget.run['distance_meters'])),
                  _stat('DURATION',
                      formatDuration(widget.run['duration_seconds'])),
                  _stat('PACE',
                      formatPace(widget.run['avg_pace_sec_per_km'])),
                  _stat('DATE',
                      formatDateShort(widget.run['started_at'] as String)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /home/joe/App/map && flutter analyze lib/screens/run_detail_sheet.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/run_detail_sheet.dart
git commit -m "feat: add RunDetailSheet with Mapbox route preview and stats"
```

---

## Task 7: Wire history button into MapScreen

**Files:**
- Modify: `lib/screens/map_screen.dart`

- [ ] **Step 1: Add import for HistoryScreen**

At the top of `lib/screens/map_screen.dart`, add after existing imports:

```dart
import 'history_screen.dart';
```

- [ ] **Step 2: Add history button to the Stack**

In the `build` method, inside the `Stack`'s `children` list, add after the logout button block (the `if (!_isTracking)` Positioned):

```dart
          if (!_isTracking && !_saving)
            Positioned(
              top: 48,
              left: 16,
              child: SafeArea(
                child: IconButton.filled(
                  icon: const Icon(Icons.history),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black54),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HistoryScreen()),
                  ),
                ),
              ),
            ),
```

- [ ] **Step 3: Run full analyze**

```bash
cd /home/joe/App/map && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/map_screen.dart
git commit -m "feat: add history button to map screen"
```

---

## Task 8: Build and smoke-test on device

- [ ] **Step 1: Build debug APK**

```bash
cd /home/joe/App/map && flutter build apk --debug
```

Expected: BUILD SUCCESSFUL, APK at `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 2: Install and verify background tracking**

Install APK. Start a run. Turn screen off. Walk/move. Turn screen back on. Verify:
- Persistent notification "Run in progress" visible in notification shade while screen is off
- Route line on map does not show km-scale jumps after screen was off

- [ ] **Step 3: Verify history screen**

Stop and save the run. Tap the history icon (top-left). Verify:
- Run appears in list with correct distance, duration, pace, date
- Tapping the run opens the bottom sheet
- Route is drawn on the Mapbox map in the sheet
- Stats row shows correct values

- [ ] **Step 4: Verify edge cases**

- Run with < 2 points (start then immediately stop): sheet shows "No route data" not a crash
- No runs at all: history screen shows "No runs yet"
