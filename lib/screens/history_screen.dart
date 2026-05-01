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
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final run = _runs[i];
                        return ListTile(
                          title: Text(formatDate(run['started_at'] as String)),
                          subtitle: Text(
                              formatDistance(run['distance_meters'])),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatDuration(run['duration_seconds'])),
                              Text(
                                formatPace(run['avg_pace_sec_per_km']),
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
