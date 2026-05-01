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
