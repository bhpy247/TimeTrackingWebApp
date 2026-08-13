import '../entities/time_entry.dart';
import '../entities/user_settings.dart';

class SalaryCalculationService {
  SalaryCalculationService._();

  /// Calculates attendance duration strictly as: End Time - Start Time.
  /// Lunch breaks and break durations are NOT subtracted.
  /// For Leave/Holiday, it is Duration.zero.
  static Duration calculateAttendanceDuration(TimeEntry entry, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final endTime = entry.endTime ?? relativeTo ?? DateTime.now();
    final diff = endTime.difference(entry.startTime!);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Daily shortfall: Max(0, Required Daily Duration - Attendance Duration)
  static Duration calculateShortfall(TimeEntry entry, double requiredDailyHours, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final actual = calculateAttendanceDuration(entry, relativeTo: relativeTo);
    final required = Duration(milliseconds: (requiredDailyHours * 3600 * 1000).toInt());
    if (actual < required) {
      return required - actual;
    }
    return Duration.zero;
  }

  /// Daily overtime: Max(0, Attendance Duration - Required Daily Duration)
  static Duration calculateOvertime(TimeEntry entry, double requiredDailyHours, {DateTime? relativeTo}) {
    if (entry.startTime == null) return Duration.zero;
    if (entry.workType == WorkType.leave || entry.workType == WorkType.holiday) {
      return Duration.zero;
    }
    final actual = calculateAttendanceDuration(entry, relativeTo: relativeTo);
    final required = Duration(milliseconds: (requiredDailyHours * 3600 * 1000).toInt());
    if (actual > required) {
      return actual - required;
    }
    return Duration.zero;
  }

  /// Rounding rule: rounds the duration to the nearest 15m, 30m, 60m, or returns exact.
  static Duration applyRounding(Duration duration, RoundingMethod roundingMethod) {
    if (duration == Duration.zero) return Duration.zero;

    final minutes = duration.inMinutes;
    int roundedMinutes;

    switch (roundingMethod) {
      case RoundingMethod.exact:
        return duration;
      case RoundingMethod.nearest15:
        roundedMinutes = (minutes / 15.0).round() * 15;
        break;
      case RoundingMethod.nearest30:
        roundedMinutes = (minutes / 30.0).round() * 30;
        break;
      case RoundingMethod.nearest60:
        roundedMinutes = (minutes / 60.0).round() * 60;
        break;
    }

    return Duration(minutes: roundedMinutes);
  }

  /// Salary rates
  static double calculateSalaryPerMinute(double monthlySalary, double requiredDailyHours, int payrollDays) {
    final monthlyHours = payrollDays * requiredDailyHours;
    if (monthlyHours == 0.0) return 0.0;
    return monthlySalary / (monthlyHours * 60.0);
  }

  static double calculateSalaryPerHour(double monthlySalary, double requiredDailyHours, int payrollDays) {
    final monthlyHours = payrollDays * requiredDailyHours;
    if (monthlyHours == 0.0) return 0.0;
    return monthlySalary / monthlyHours;
  }

  static double calculateSalaryPerDay(double monthlySalary, int payrollDays) {
    if (payrollDays == 0) return 0.0;
    return monthlySalary / payrollDays;
  }

  /// Calculate estimated deduction from shortfall
  static double calculateEstimatedDeduction({
    required Duration shortfall,
    required double monthlySalary,
    required double requiredDailyHours,
    required int payrollDays,
    required SalaryDeductionMethod deductionMethod,
    required RoundingMethod roundingMethod,
  }) {
    if (shortfall == Duration.zero) return 0.0;

    final rounded = applyRounding(shortfall, roundingMethod);
    if (rounded == Duration.zero) return 0.0;

    switch (deductionMethod) {
      case SalaryDeductionMethod.perMinute:
        final rate = calculateSalaryPerMinute(monthlySalary, requiredDailyHours, payrollDays);
        return rounded.inMinutes * rate;
      case SalaryDeductionMethod.perHour:
        final rate = calculateSalaryPerHour(monthlySalary, requiredDailyHours, payrollDays);
        final hours = rounded.inMinutes / 60.0;
        return hours * rate;
      case SalaryDeductionMethod.perDay:
        final rate = calculateSalaryPerDay(monthlySalary, payrollDays);
        final requiredMinutes = requiredDailyHours * 60.0;
        if (requiredMinutes == 0.0) return 0.0;
        final days = rounded.inMinutes / requiredMinutes;
        return days * rate;
    }
  }
}
