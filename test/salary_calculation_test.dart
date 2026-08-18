import 'package:flutter_test/flutter_test.dart';
import 'package:timetracking/domain/entities/time_entry.dart';
import 'package:timetracking/domain/entities/user_settings.dart';
import 'package:timetracking/domain/usecases/salary_calculation_service.dart';
import 'package:timetracking/domain/usecases/time_calculator.dart';

void main() {
  group('SalaryCalculationService Tests', () {
    test('Full working day (no shortfall, no overtime)', () {
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 10, 0), // 10:00 AM
        endTime: DateTime(2026, 8, 13, 19, 30), // 7:30 PM
        workType: WorkType.office,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final attendance = SalaryCalculationService.calculateAttendanceDuration(entry);
      expect(attendance, const Duration(hours: 9, minutes: 30));

      final shortfall = SalaryCalculationService.calculateShortfall(entry, 9.5);
      expect(shortfall, Duration.zero);

      final overtime = SalaryCalculationService.calculateOvertime(entry, 9.5);
      expect(overtime, Duration.zero);
    });

    test('Late arrival & Early departure calculations in TimeCalculator', () {
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 11, 0), // 11:00 AM (Late)
        endTime: DateTime(2026, 8, 13, 18, 30), // 6:30 PM (Early)
        workType: WorkType.office,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Expected start 10:00 AM, expected end 7:30 PM (19:30)
      final lateArrival = TimeCalculator.calculateLateArrival(entry, "10:00");
      expect(lateArrival, const Duration(hours: 1));

      final earlyDeparture = TimeCalculator.calculateEarlyDeparture(entry, "19:30");
      expect(earlyDeparture, const Duration(hours: 1));
    });

    test('Shortfall calculation', () {
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 11, 0), // 11:00 AM
        endTime: DateTime(2026, 8, 13, 19, 30), // 7:30 PM
        workType: WorkType.office,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Attendance: 8.5 hours. Required: 9.5 hours.
      final attendance = SalaryCalculationService.calculateAttendanceDuration(entry);
      expect(attendance, const Duration(hours: 8, minutes: 30));

      final shortfall = SalaryCalculationService.calculateShortfall(entry, 9.5);
      expect(shortfall, const Duration(hours: 1));
    });

    test('Overtime calculation', () {
      final entry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 10, 0), // 10:00 AM
        endTime: DateTime(2026, 8, 13, 20, 30), // 8:30 PM
        workType: WorkType.office,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Attendance: 10.5 hours. Required: 9.5 hours.
      final attendance = SalaryCalculationService.calculateAttendanceDuration(entry);
      expect(attendance, const Duration(hours: 10, minutes: 30));

      final overtime = SalaryCalculationService.calculateOvertime(entry, 9.5);
      expect(overtime, const Duration(hours: 1));
    });

    test('Leave / Holiday / WFH work types', () {
      final leaveEntry = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 10, 0),
        endTime: DateTime(2026, 8, 13, 19, 30),
        workType: WorkType.leave,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final holidayEntry = TimeEntry(
        date: DateTime(2026, 8, 14),
        startTime: DateTime(2026, 8, 14, 10, 0),
        endTime: DateTime(2026, 8, 14, 19, 30),
        workType: WorkType.holiday,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final wfhEntry = TimeEntry(
        date: DateTime(2026, 8, 15),
        startTime: DateTime(2026, 8, 15, 11, 0),
        endTime: DateTime(2026, 8, 15, 19, 30),
        workType: WorkType.wfh,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Leave has 0 attendance, 0 shortfall
      expect(SalaryCalculationService.calculateAttendanceDuration(leaveEntry), Duration.zero);
      expect(SalaryCalculationService.calculateShortfall(leaveEntry, 9.5), Duration.zero);

      // Holiday has 0 attendance, 0 shortfall
      expect(SalaryCalculationService.calculateAttendanceDuration(holidayEntry), Duration.zero);
      expect(SalaryCalculationService.calculateShortfall(holidayEntry, 9.5), Duration.zero);

      // WFH has actual attendance and shortfall
      expect(SalaryCalculationService.calculateAttendanceDuration(wfhEntry), const Duration(hours: 8, minutes: 30));
      expect(SalaryCalculationService.calculateShortfall(wfhEntry, 9.5), const Duration(hours: 1));
    });

    test('Rounding rules', () {
      const shortfall = Duration(hours: 1, minutes: 17); // 77 minutes

      // Exact
      expect(
        SalaryCalculationService.applyRounding(shortfall, RoundingMethod.exact),
        const Duration(hours: 1, minutes: 17),
      );

      // Nearest 15m (77 / 15 = 5.13 -> 5 * 15 = 75m = 1h 15m)
      expect(
        SalaryCalculationService.applyRounding(shortfall, RoundingMethod.nearest15),
        const Duration(hours: 1, minutes: 15),
      );

      // Nearest 30m (77 / 30 = 2.56 -> 3 * 30 = 90m = 1h 30m)
      expect(
        SalaryCalculationService.applyRounding(shortfall, RoundingMethod.nearest30),
        const Duration(hours: 1, minutes: 30),
      );

      // Nearest 60m (77 / 60 = 1.28 -> 1 * 60 = 60m = 1h)
      expect(
        SalaryCalculationService.applyRounding(shortfall, RoundingMethod.nearest60),
        const Duration(hours: 1),
      );
    });

    test('Salary per minute calculation', () {
      // Salary: 70,000, Required Daily: 9.5, Payroll Days: 26
      // Total monthly minutes = 26 * 9.5 * 60 = 14,820
      // Rate = 70,000 / 14,820 = 4.72334
      final rate = SalaryCalculationService.calculateSalaryPerMinute(70000, 9.5, 26);
      expect(rate, closeTo(70000 / (26 * 9.5 * 60), 0.0001));

      // Estimated deduction for 1h 17m (77 mins) exact
      final deduction = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: const Duration(hours: 1, minutes: 17),
        monthlySalary: 70000,
        requiredDailyHours: 9.5,
        payrollDays: 26,
        deductionMethod: SalaryDeductionMethod.perMinute,
        roundingMethod: RoundingMethod.exact,
      );
      expect(deduction, closeTo(77 * (70000 / (26 * 9.5 * 60)), 0.0001));
    });

    test('Salary per hour calculation', () {
      // Salary: 70,000, Required Daily: 9.5, Payroll Days: 26
      // Total monthly hours = 26 * 9.5 = 247
      // Rate = 70,000 / 247 = 283.4008
      final rate = SalaryCalculationService.calculateSalaryPerHour(70000, 9.5, 26);
      expect(rate, closeTo(70000 / (26 * 9.5), 0.0001));

      // Estimated deduction for 1.5 hours nearest 30 mins
      final deduction = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: const Duration(hours: 1, minutes: 17),
        monthlySalary: 70000,
        requiredDailyHours: 9.5,
        payrollDays: 26,
        deductionMethod: SalaryDeductionMethod.perHour,
        roundingMethod: RoundingMethod.nearest30, // rounds 77m -> 90m = 1.5 hours
      );
      expect(deduction, closeTo(1.5 * (70000 / (26 * 9.5)), 0.0001));
    });

    test('Salary per day calculation', () {
      // Salary: 70,000, Payroll Days: 26
      // Rate = 70,000 / 26 = 2692.307
      final rate = SalaryCalculationService.calculateSalaryPerDay(70000, 26);
      expect(rate, closeTo(70000 / 26, 0.0001));

      // Estimated deduction for 1.0 day nearest 60 mins (shortfall: 9.5 hours -> rounds to 9.5 hours)
      final deduction = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: const Duration(hours: 9, minutes: 30),
        monthlySalary: 70000,
        requiredDailyHours: 9.5,
        payrollDays: 26,
        deductionMethod: SalaryDeductionMethod.perDay,
        roundingMethod: RoundingMethod.exact,
      );
      expect(deduction, closeTo(70000 / 26, 0.0001));
    });

    test('CRITICAL: Break isolation test (breaks have zero impact)', () {
      // Entry with a short 30-minute break
      final entryWithShortBreak = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 10, 0),
        endTime: DateTime(2026, 8, 13, 19, 30),
        workType: WorkType.office,
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
      );

      // Same start/end times, but with a 2-hour break instead
      final entryWithLongBreak = TimeEntry(
        date: DateTime(2026, 8, 13),
        startTime: DateTime(2026, 8, 13, 10, 0),
        endTime: DateTime(2026, 8, 13, 19, 30),
        workType: WorkType.office,
        breaks: [
          BreakEntry(
            startTime: DateTime(2026, 8, 13, 13, 0),
            endTime: DateTime(2026, 8, 13, 15, 0),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Verify attendance duration is exactly identical (9h 30m)
      final attShort = SalaryCalculationService.calculateAttendanceDuration(entryWithShortBreak);
      final attLong = SalaryCalculationService.calculateAttendanceDuration(entryWithLongBreak);
      expect(attShort, const Duration(hours: 9, minutes: 30));
      expect(attLong, const Duration(hours: 9, minutes: 30));
      expect(attShort, attLong);

      // Verify shortfall is exactly identical (0)
      final sfShort = SalaryCalculationService.calculateShortfall(entryWithShortBreak, 9.5);
      final sfLong = SalaryCalculationService.calculateShortfall(entryWithLongBreak, 9.5);
      expect(sfShort, sfLong);

      // Verify overtime is exactly identical (0)
      final otShort = SalaryCalculationService.calculateOvertime(entryWithShortBreak, 9.5);
      final otLong = SalaryCalculationService.calculateOvertime(entryWithLongBreak, 9.5);
      expect(otShort, otLong);

      // Verify estimated deduction is exactly identical
      final decShort = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: sfShort,
        monthlySalary: 70000,
        requiredDailyHours: 9.5,
        payrollDays: 26,
        deductionMethod: SalaryDeductionMethod.perMinute,
        roundingMethod: RoundingMethod.exact,
      );
      final decLong = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: sfLong,
        monthlySalary: 70000,
        requiredDailyHours: 9.5,
        payrollDays: 26,
        deductionMethod: SalaryDeductionMethod.perMinute,
        roundingMethod: RoundingMethod.exact,
      );
      expect(decShort, decLong);
    });

    test('No shortfall carryforward: daily rounding test', () {
      final entries = [
        TimeEntry(
          date: DateTime(2026, 8, 10),
          startTime: DateTime(2026, 8, 10, 10, 0),
          endTime: DateTime(2026, 8, 10, 19, 20), // Attendance: 9h 20m -> Shortfall: 10m
          workType: WorkType.office,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TimeEntry(
          date: DateTime(2026, 8, 11),
          startTime: DateTime(2026, 8, 11, 10, 0),
          endTime: DateTime(2026, 8, 11, 19, 20), // Attendance: 9h 20m -> Shortfall: 10m
          workType: WorkType.office,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TimeEntry(
          date: DateTime(2026, 8, 12),
          startTime: DateTime(2026, 8, 12, 10, 0),
          endTime: DateTime(2026, 8, 12, 19, 20), // Attendance: 9h 20m -> Shortfall: 10m
          workType: WorkType.office,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final settings = UserSettings(
        requiredDailyDurationHours: 9.5, // 9h 30m required
        roundingMethod: RoundingMethod.nearest30,
        monthlySalary: 70000,
        payrollDays: 26,
        salaryDeductionMethod: SalaryDeductionMethod.perMinute,
      );

      // Verify that summing the daily rounded shortfalls gives 0
      Duration monthlyShortfall = Duration.zero;
      for (final entry in entries) {
        final raw = SalaryCalculationService.calculateShortfall(entry, settings.requiredDailyDurationHours);
        expect(raw, const Duration(minutes: 10));
        
        final rounded = SalaryCalculationService.applyRounding(raw, settings.roundingMethod);
        expect(rounded, Duration.zero); // 10m rounded to nearest 30m is 0m

        monthlyShortfall += rounded;
      }
      expect(monthlyShortfall, Duration.zero);

      final deduction = SalaryCalculationService.calculateEstimatedDeduction(
        shortfall: monthlyShortfall,
        monthlySalary: settings.monthlySalary,
        requiredDailyHours: settings.requiredDailyDurationHours,
        payrollDays: settings.payrollDays,
        deductionMethod: settings.salaryDeductionMethod,
        roundingMethod: RoundingMethod.exact,
      );
      expect(deduction, 0.0);
    });
  });
}
