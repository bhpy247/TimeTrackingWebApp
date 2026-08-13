import 'package:flutter_test/flutter_test.dart';
import 'package:timetracking/domain/entities/time_entry.dart';
import 'package:timetracking/domain/usecases/time_calculator.dart';

void main() {
  group('TimeCalculator tests', () {
    test('calculateGrossDuration', () {
      final start = DateTime(2026, 8, 13, 10, 0);
      final end = DateTime(2026, 8, 13, 19, 0);
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: start,
        endTime: end,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(TimeCalculator.calculateGrossDuration(entry), const Duration(hours: 9));
    });

    test('calculateBreakDuration', () {
      final start = DateTime(2026, 8, 13, 10, 0);
      final end = DateTime(2026, 8, 13, 19, 0);
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: start,
        endTime: end,
        breaks: [
          BreakEntry(
            startTime: DateTime(2026, 8, 13, 13, 0),
            endTime: DateTime(2026, 8, 13, 13, 45),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          BreakEntry(
            startTime: DateTime(2026, 8, 13, 16, 0),
            endTime: DateTime(2026, 8, 13, 16, 15),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(TimeCalculator.calculateBreakDuration(entry), const Duration(minutes: 60));
      expect(TimeCalculator.calculateWorkingDuration(entry), const Duration(hours: 8));
    });

    test('calculateOvertime and Shortfall', () {
      final start = DateTime(2026, 8, 13, 10, 0);
      final end = DateTime(2026, 8, 13, 19, 0);
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: start,
        endTime: end,
        breaks: [
          BreakEntry(
            startTime: DateTime(2026, 8, 13, 13, 0),
            endTime: DateTime(2026, 8, 13, 13, 30),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ); // 9h gross - 30m break = 8.5h working

      expect(TimeCalculator.calculateOvertime(entry, 8.0), const Duration(minutes: 30));
      expect(TimeCalculator.calculateShortfall(entry, 9.0), const Duration(minutes: 30));
    });

    test('calculateLateArrival and EarlyDeparture', () {
      final start = DateTime(2026, 8, 13, 10, 15);
      final end = DateTime(2026, 8, 13, 19, 10);
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: start,
        endTime: end,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(TimeCalculator.calculateLateArrival(entry, "10:00"), const Duration(minutes: 15));
      expect(TimeCalculator.calculateEarlyDeparture(entry, "19:30"), const Duration(minutes: 20));
    });
  });
}
