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
      lineColor: Colors.blue.toARGB32(),
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
