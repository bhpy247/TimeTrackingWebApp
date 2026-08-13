import '../entities/time_entry.dart';

class TimeCalculator {
  TimeCalculator._();

  static Duration calculateGrossDuration(TimeEntry entry, {DateTime? relativeTo}) {
    final startTime = entry.startTime;
    if (startTime == null) return Duration.zero;

    final endTime = entry.endTime ?? relativeTo ?? DateTime.now();
    return endTime.difference(startTime);
  }

  static Duration calculateBreakDuration(TimeEntry entry, {DateTime? relativeTo}) {
    Duration total = Duration.zero;
    for (final b in entry.breaks) {
      final end = b.endTime ?? relativeTo ?? DateTime.now();
      total += end.difference(b.startTime);
    }
    return total;
  }

  static Duration calculateWorkingDuration(TimeEntry entry, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final gross = calculateGrossDuration(entry, relativeTo: relativeTo);
    final breaks = calculateBreakDuration(entry, relativeTo: relativeTo);
    final working = gross - breaks;
    return working.isNegative ? Duration.zero : working;
  }

  static Duration calculateOvertime(TimeEntry entry, double expectedHours, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final working = calculateWorkingDuration(entry, relativeTo: relativeTo);
    final expected = Duration(milliseconds: (expectedHours * 3600 * 1000).toInt());
    if (working > expected) {
      return working - expected;
    }
    return Duration.zero;
  }

  static Duration calculateShortfall(TimeEntry entry, double expectedHours, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final working = calculateWorkingDuration(entry, relativeTo: relativeTo);
    final expected = Duration(milliseconds: (expectedHours * 3600 * 1000).toInt());
    if (working < expected) {
      return expected - working;
    }
    return Duration.zero;
  }

  static Duration calculateLateArrival(TimeEntry entry, String expectedStartTime24h) {
    final start = entry.startTime;
    if (start == null) return Duration.zero;

    final parts = expectedStartTime24h.split(':');
    final expectedHour = int.parse(parts[0]);
    final expectedMinute = int.parse(parts[1]);

    final expectedTime = DateTime(start.year, start.month, start.day, expectedHour, expectedMinute);
    if (start.isAfter(expectedTime)) {
      return start.difference(expectedTime);
    }
    return Duration.zero;
  }

  static Duration calculateEarlyDeparture(TimeEntry entry, String expectedEndTime24h) {
    final end = entry.endTime;
    if (end == null) return Duration.zero;

    final parts = expectedEndTime24h.split(':');
    final expectedHour = int.parse(parts[0]);
    final expectedMinute = int.parse(parts[1]);

    final expectedTime = DateTime(end.year, end.month, end.day, expectedHour, expectedMinute);
    if (end.isBefore(expectedTime)) {
      return expectedTime.difference(end);
    }
    return Duration.zero;
  }

  static Duration calculateMonthlyTotal(List<TimeEntry> entries, {DateTime? relativeTo}) {
    Duration total = Duration.zero;
    for (final entry in entries) {
      total += calculateWorkingDuration(entry, relativeTo: relativeTo);
    }
    return total;
  }

  static Duration calculateMonthlyAverage(List<TimeEntry> entries, {DateTime? relativeTo}) {
    if (entries.isEmpty) return Duration.zero;
    final total = calculateMonthlyTotal(entries, relativeTo: relativeTo);
    // Count days where start time is recorded
    final activeDays = entries.where((e) => e.startTime != null).length;
    if (activeDays == 0) return Duration.zero;
    return Duration(milliseconds: (total.inMilliseconds / activeDays).round());
  }

  static double calculateRemainingMonthlyTarget(Duration monthlyTotal, double monthlyTargetHours) {
    final target = Duration(milliseconds: (monthlyTargetHours * 3600 * 1000).toInt());
    final remaining = target - monthlyTotal;
    return remaining.isNegative ? 0.0 : remaining.inMilliseconds / (3600 * 1000);
  }
}
