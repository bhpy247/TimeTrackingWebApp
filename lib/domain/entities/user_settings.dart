import 'package:flutter/material.dart';

class UserSettings {
  final String expectedStartTime; // format: "HH:mm" (24h) or "HH:mm AM/PM"
  final String expectedEndTime;   // format: "HH:mm" (24h) or "HH:mm AM/PM"
  final double expectedWorkingHours; // e.g. 8.5
  final List<int> workingDays; // Monday=1, Sunday=7. e.g. [1, 2, 3, 4, 5]
  final int defaultBreakDurationMinutes; // e.g. 45
  final bool notificationsEnabled;
  final String morningReminderTime; // format: "HH:mm"
  final String eveningReminderTime; // format: "HH:mm"
  final ThemeMode themeMode;

  const UserSettings({
    this.expectedStartTime = "10:00",
    this.expectedEndTime = "19:30",
    this.expectedWorkingHours = 8.5,
    this.workingDays = const [1, 2, 3, 4, 5],
    this.defaultBreakDurationMinutes = 45,
    this.notificationsEnabled = true,
    this.morningReminderTime = "10:00",
    this.eveningReminderTime = "19:30",
    this.themeMode = ThemeMode.system,
  });

  UserSettings copyWith({
    String? expectedStartTime,
    String? expectedEndTime,
    double? expectedWorkingHours,
    List<int>? workingDays,
    int? defaultBreakDurationMinutes,
    bool? notificationsEnabled,
    String? morningReminderTime,
    String? eveningReminderTime,
    ThemeMode? themeMode,
  }) {
    return UserSettings(
      expectedStartTime: expectedStartTime ?? this.expectedStartTime,
      expectedEndTime: expectedEndTime ?? this.expectedEndTime,
      expectedWorkingHours: expectedWorkingHours ?? this.expectedWorkingHours,
      workingDays: workingDays ?? this.workingDays,
      defaultBreakDurationMinutes: defaultBreakDurationMinutes ?? this.defaultBreakDurationMinutes,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      morningReminderTime: morningReminderTime ?? this.morningReminderTime,
      eveningReminderTime: eveningReminderTime ?? this.eveningReminderTime,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  TimeOfDay get startTimeOfDay {
    final parts = expectedStartTime.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  TimeOfDay get endTimeOfDay {
    final parts = expectedEndTime.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  TimeOfDay get morningReminderTimeOfDay {
    final parts = morningReminderTime.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  TimeOfDay get eveningReminderTimeOfDay {
    final parts = eveningReminderTime.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}
