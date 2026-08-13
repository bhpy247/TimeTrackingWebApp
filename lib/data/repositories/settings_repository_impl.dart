import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SharedPreferences _prefs;

  SettingsRepositoryImpl(this._prefs);

  static const String _keyStartTime = 'settings_expected_start_time';
  static const String _keyEndTime = 'settings_expected_end_time';
  static const String _keyWorkingHours = 'settings_expected_working_hours';
  static const String _keyWorkingDays = 'settings_working_days';
  static const String _keyBreakDuration = 'settings_default_break_duration';
  static const String _keyNotificationsEnabled = 'settings_notifications_enabled';
  static const String _keyMorningReminder = 'settings_morning_reminder_time';
  static const String _keyEveningReminder = 'settings_evening_reminder_time';
  static const String _keyThemeMode = 'settings_theme_mode';

  // Salary/Attendance Keys
  static const String _keyMonthlySalary = 'settings_monthly_salary';
  static const String _keyPayrollDays = 'settings_payroll_days';
  static const String _keyRequiredDuration = 'settings_required_daily_duration_hours';
  static const String _keyDeductionMethod = 'settings_salary_deduction_method';
  static const String _keyRoundingMethod = 'settings_rounding_method';

  @override
  Future<UserSettings> getSettings() async {
    final startTime = _prefs.getString(_keyStartTime) ?? "10:00";
    final endTime = _prefs.getString(_keyEndTime) ?? "19:30";
    final workingHours = _prefs.getDouble(_keyWorkingHours) ?? 8.5;
    final workingDaysString = _prefs.getString(_keyWorkingDays) ?? "1,2,3,4,5";
    final breakDuration = _prefs.getInt(_keyBreakDuration) ?? 45;
    final notificationsEnabled = _prefs.getBool(_keyNotificationsEnabled) ?? true;
    final morningReminder = _prefs.getString(_keyMorningReminder) ?? "10:00";
    final eveningReminder = _prefs.getString(_keyEveningReminder) ?? "19:30";
    final themeString = _prefs.getString(_keyThemeMode) ?? "system";

    // Salary Load
    final monthlySalary = _prefs.getDouble(_keyMonthlySalary) ?? 70000.0;
    final payrollDays = _prefs.getInt(_keyPayrollDays) ?? 26;
    final requiredDuration = _prefs.getDouble(_keyRequiredDuration) ?? 9.5;
    final deductionString = _prefs.getString(_keyDeductionMethod) ?? SalaryDeductionMethod.perMinute.name;
    final roundingString = _prefs.getString(_keyRoundingMethod) ?? RoundingMethod.exact.name;

    final workingDays = workingDaysString
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();

    ThemeMode themeMode;
    switch (themeString) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      case 'system':
      default:
        themeMode = ThemeMode.system;
        break;
    }

    // Enum mapping
    final deductionMethod = SalaryDeductionMethod.values.firstWhere(
      (e) => e.name == deductionString,
      orElse: () => SalaryDeductionMethod.perMinute,
    );

    final roundingMethod = RoundingMethod.values.firstWhere(
      (e) => e.name == roundingString,
      orElse: () => RoundingMethod.exact,
    );

    return UserSettings(
      expectedStartTime: startTime,
      expectedEndTime: endTime,
      expectedWorkingHours: workingHours,
      workingDays: workingDays,
      defaultBreakDurationMinutes: breakDuration,
      notificationsEnabled: notificationsEnabled,
      morningReminderTime: morningReminder,
      eveningReminderTime: eveningReminder,
      themeMode: themeMode,
      monthlySalary: monthlySalary,
      payrollDays: payrollDays,
      requiredDailyDurationHours: requiredDuration,
      salaryDeductionMethod: deductionMethod,
      roundingMethod: roundingMethod,
    );
  }

  @override
  Future<void> saveSettings(UserSettings settings) async {
    await _prefs.setString(_keyStartTime, settings.expectedStartTime);
    await _prefs.setString(_keyEndTime, settings.expectedEndTime);
    await _prefs.setDouble(_keyWorkingHours, settings.expectedWorkingHours);
    await _prefs.setString(_keyWorkingDays, settings.workingDays.join(','));
    await _prefs.setInt(_keyBreakDuration, settings.defaultBreakDurationMinutes);
    await _prefs.setBool(_keyNotificationsEnabled, settings.notificationsEnabled);
    await _prefs.setString(_keyMorningReminder, settings.morningReminderTime);
    await _prefs.setString(_keyEveningReminder, settings.eveningReminderTime);

    // Salary Save
    await _prefs.setDouble(_keyMonthlySalary, settings.monthlySalary);
    await _prefs.setInt(_keyPayrollDays, settings.payrollDays);
    await _prefs.setDouble(_keyRequiredDuration, settings.requiredDailyDurationHours);
    await _prefs.setString(_keyDeductionMethod, settings.salaryDeductionMethod.name);
    await _prefs.setString(_keyRoundingMethod, settings.roundingMethod.name);

    String themeString;
    switch (settings.themeMode) {
      case ThemeMode.light:
        themeString = 'light';
        break;
      case ThemeMode.dark:
        themeString = 'dark';
        break;
      case ThemeMode.system:
        themeString = 'system';
        break;
    }
    await _prefs.setString(_keyThemeMode, themeString);
  }
}
