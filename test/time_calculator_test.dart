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

    test('HalfDay working duration, overtime, and shortfall', () {
      // Half-day where expected full day is 8.5h -> half day expected is 4.25h (4h 15m)
      final start = DateTime(2026, 8, 13, 10, 0);
      final end = DateTime(2026, 8, 13, 14, 45); // 4h 45m gross
      final halfDayEntry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: start,
        endTime: end,
        workType: WorkType.halfDay,
        breaks: [
          BreakEntry(
            startTime: DateTime(2026, 8, 13, 12, 0),
            endTime: DateTime(2026, 8, 13, 12, 30), // 30m break -> 4h 15m net working
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(TimeCalculator.calculateWorkingDuration(halfDayEntry), const Duration(hours: 4, minutes: 15));
      // Net is exactly 4.25h -> 0 overtime, 0 shortfall against 8.5h full-day expectation
      expect(TimeCalculator.calculateOvertime(halfDayEntry, 8.5), Duration.zero);
      expect(TimeCalculator.calculateShortfall(halfDayEntry, 8.5), Duration.zero);

      // Worked 5h net -> 45m overtime on half day
      final halfDayOvertime = halfDayEntry.copyWith(
        endTime: DateTime(2026, 8, 13, 15, 30), // 5h net
      );
      expect(TimeCalculator.calculateOvertime(halfDayOvertime, 8.5), const Duration(minutes: 45));

      // Worked 3.5h net -> 45m shortfall on half day
      final halfDayShortfall = halfDayEntry.copyWith(
        endTime: DateTime(2026, 8, 13, 14, 0), // 3h 30m net
      );
      expect(TimeCalculator.calculateShortfall(halfDayShortfall, 8.5), const Duration(minutes: 45));
    });
  });
}
