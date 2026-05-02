import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'history_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _map;
  PolylineAnnotationManager? _lineManager;
  PolylineAnnotation? _routeLine;

  final List<Position> _routePoints = [];
  StreamSubscription<geo.Position>? _locationSub;
  bool _isTracking = false;
  bool _saving = false;

  double _totalDistanceMeters = 0.0;
  DateTime? _startTime;
  Timer? _ticker;

  Duration get _elapsed =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);

  String get _distanceString {
    final km = _totalDistanceMeters / 1000;
    return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${_totalDistanceMeters.toInt()} m';
  }

  String get _durationString {
    final s = _elapsed.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String get _paceString {
    if (_totalDistanceMeters < 50 || _elapsed.inSeconds < 5) return '--:--';
    final secPerKm = _elapsed.inSeconds / (_totalDistanceMeters / 1000);
    final mm = (secPerKm ~/ 60).toString().padLeft(2, '0');
    final ss = (secPerKm % 60).toInt().toString().padLeft(2, '0');
    return '$mm:$ss /km';
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;

    geo.LocationPermission perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }

    if (perm == geo.LocationPermission.whileInUse ||
        perm == geo.LocationPermission.always) {
      await map.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          pulsingColor: Colors.blue.value,
          pulsingMaxRadius: 50.0,
        ),
      );

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings:
            const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      );
      await map.easeTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 15.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }

    _lineManager = await map.annotations.createPolylineAnnotationManager();
  }

  Future<bool> _ensureBackgroundPermissions() async {
    var locPerm = await geo.Geolocator.checkPermission();

    if (locPerm == geo.LocationPermission.denied) {
      locPerm = await geo.Geolocator.requestPermission();
    }

    if (locPerm == geo.LocationPermission.denied ||
        locPerm == geo.LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required')),
        );
      }
      return false;
    }

    if (locPerm == geo.LocationPermission.whileInUse) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Background location needed'),
            content: const Text(
              'Tracking stops when your screen turns off unless you allow '
              '"Always" location access.\n\n'
              'Open Settings → Permissions → Location → Allow all the time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await geo.Geolocator.openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      locPerm = await geo.Geolocator.checkPermission();
      if (locPerm != geo.LocationPermission.always) return false;
    }

    final batteryOk = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!batteryOk) {
      await Permission.ignoreBatteryOptimizations.request();
      final granted = await Permission.ignoreBatteryOptimizations.isGranted;
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Battery optimization not disabled — tracking may stop when screen is off.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }

    return true;
  }

  Future<void> _startTracking() async {
    final ok = await _ensureBackgroundPermissions();
    if (!ok) return;

    setState(() {
      _isTracking = true;
      _routePoints.clear();
      _totalDistanceMeters = 0.0;
      _startTime = DateTime.now();
    });

    if (_routeLine != null) {
      await _lineManager?.delete(_routeLine!);
      _routeLine = null;
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

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
  }

  Future<void> _onLocation(geo.Position pos) async {
    final coord = Position(pos.longitude, pos.latitude);

    if (_routePoints.isNotEmpty) {
      final prev = _routePoints.last;
      setState(() {
        _totalDistanceMeters += geo.Geolocator.distanceBetween(
          (prev[1] as num).toDouble(), (prev[0] as num).toDouble(),
          pos.latitude, pos.longitude,
        );
      });
    }

    _routePoints.add(coord);

    _map?.easeTo(
      CameraOptions(
        center: Point(coordinates: coord),
        zoom: 17.0,
      ),
      MapAnimationOptions(duration: 600),
    );

    if (_routePoints.length < 2) return;

    final lineGeometry = LineString(coordinates: _routePoints);

    if (_routeLine == null) {
      _routeLine = await _lineManager?.create(
        PolylineAnnotationOptions(
          geometry: lineGeometry,
          lineColor: Colors.blue.value,
          lineWidth: 5.0,
          lineOpacity: 0.9,
        ),
      );
    } else {
      _routeLine!.geometry = lineGeometry;
      await _lineManager?.update(_routeLine!);
    }
  }

  Future<void> _stopTracking() async {
    _ticker?.cancel();
    _ticker = null;
    await _locationSub?.cancel();
    _locationSub = null;

    final endTime = DateTime.now();
    final startTime = _startTime!;
    final distance = _totalDistanceMeters;
    final duration = endTime.difference(startTime).inSeconds;
    final pace = distance > 0 ? duration / (distance / 1000) : null;
    final points = List<Position>.from(_routePoints);

    setState(() {
      _isTracking = false;
      _saving = true;
    });

    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final db = Supabase.instance.client.from;

      String? routeWkt;
      if (points.length >= 2) {
        final coords = points
            .map((p) => '${(p[0] as num).toDouble()} ${(p[1] as num).toDouble()}')
            .join(',');
        routeWkt = 'SRID=4326;LINESTRING($coords)';
      }

      final run = await db('runs').insert({
        'user_id': uid,
        'started_at': startTime.toIso8601String(),
        'ended_at': endTime.toIso8601String(),
        'distance_meters': distance,
        'duration_seconds': duration,
        'avg_pace_sec_per_km': pace,
        if (routeWkt != null) 'route': routeWkt,
      }).select('id').single();

      final runId = run['id'] as String;

      if (points.length >= 2) {
        final pointRows = points.asMap().entries.map((e) {
          final lng = (e.value[0] as num).toDouble();
          final lat = (e.value[1] as num).toDouble();
          return {
            'run_id': runId,
            'seq': e.key,
            'location': 'SRID=4326;POINT($lng $lat)',
          };
        }).toList();
        await db('run_points').insert(pointRows);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Run saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            styleUri: MapboxStyles.OUTDOORS,
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(101.6869, 3.1390)),
              zoom: 15.0,
            ),
          ),
          if (_isTracking)
            Positioned(
              top: 48,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statCol('DISTANCE', _distanceString),
                    _statCol('DURATION', _durationString),
                    _statCol('PACE', _paceString),
                  ],
                ),
              ),
            ),
          if (!_isTracking)
            Positioned(
              top: 48,
              right: 16,
              child: SafeArea(
                child: IconButton.filled(
                  icon: const Icon(Icons.logout),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: () =>
                      Supabase.instance.client.auth.signOut(),
                ),
              ),
            ),
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
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: _saving
                  ? const CircularProgressIndicator()
                  : _isTracking
                      ? _btn('Stop', const Color(0xFFE53935), _stopTracking)
                      : _btn('Start Run', const Color(0xFF43A047), _startTracking),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _btn(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        shape: const StadiumBorder(),
        elevation: 8,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
