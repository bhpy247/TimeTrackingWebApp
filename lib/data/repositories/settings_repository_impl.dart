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
