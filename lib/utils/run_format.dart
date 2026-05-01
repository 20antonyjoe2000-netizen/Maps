String formatDistance(dynamic meters) {
  if (meters == null) return '--';
  final m = meters as num;
  final km = m.toDouble() / 1000;
  return km >= 1 ? '${km.toStringAsFixed(2)} km' : '${m.toInt()} m';
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
