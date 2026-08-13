import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTimeForDisplay(String time24h) {
    try {
      final parts = time24h.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final time = TimeOfDay(hour: hour, minute: minute);
      
      final period = time.period == DayPeriod.am ? 'AM' : 'PM';
      final hourOfPeriod = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
      final minuteStr = time.minute.toString().padLeft(2, '0');
      
      return '$hourOfPeriod:$minuteStr $period';
    } catch (_) {
      return time24h;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader(theme, 'Work Schedule'),
          _buildTimeTile(
            context,
            ref,
            title: 'Expected Start Time',
            subtitle: _formatTimeForDisplay(settings.expectedStartTime),
            currentTime: settings.startTimeOfDay,
            onTimeChanged: (newTime) {
              ref.read(settingsProvider.notifier).updateSettings(
                    settings.copyWith(expectedStartTime: _formatTimeOfDay(newTime)),
                  );
            },
          ),
          _buildTimeTile(
            context,
            ref,
            title: 'Expected End Time',
            subtitle: _formatTimeForDisplay(settings.expectedEndTime),
            currentTime: settings.endTimeOfDay,
            onTimeChanged: (newTime) {
              ref.read(settingsProvider.notifier).updateSettings(
                    settings.copyWith(expectedEndTime: _formatTimeOfDay(newTime)),
                  );
            },
          ),
          ListTile(
            title: const Text('Expected Working Hours'),
            subtitle: Text('${settings.expectedWorkingHours} hours'),
            trailing: DropdownButton<double>(
              value: settings.expectedWorkingHours,
              underline: const SizedBox(),
              items: List.generate(17, (index) => 4.0 + (index * 0.5))
                  .map((val) => DropdownMenuItem(
                        value: val,
                        child: Text('$val h'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(expectedWorkingHours: val),
                      );
                }
              },
            ),
          ),
          _buildSectionHeader(theme, 'Working Days'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (index) {
                final dayNum = index + 1; // 1 = Mon, 7 = Sun
                final isSelected = settings.workingDays.contains(dayNum);
                final label = _getDayLabel(dayNum);

                return FilterChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    final updatedDays = List<int>.from(settings.workingDays);
                    if (selected) {
                      updatedDays.add(dayNum);
                    } else {
                      if (updatedDays.length > 1) {
                        updatedDays.remove(dayNum);
                      } else {
                        // Prevent removing all days
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('At least one working day is required.')),
                        );
                        return;
                      }
                    }
                    updatedDays.sort();
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(workingDays: updatedDays),
                        );
                  },
                );
              }),
            ),
          ),
          _buildSectionHeader(theme, 'Notifications'),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            subtitle: const Text('Reminders for Clock-in and Clock-out'),
            value: settings.notificationsEnabled,
            activeColor: theme.colorScheme.primary,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateSettings(
                    settings.copyWith(notificationsEnabled: val),
                  );
            },
          ),
          _buildSectionHeader(theme, 'Appearance'),
          ListTile(
            title: const Text('Theme Mode'),
            subtitle: Text(_getThemeModeLabel(settings.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(themeMode: mode),
                      );
                }
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, right: 16, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTimeTile(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
    required TimeOfDay currentTime,
    required ValueChanged<TimeOfDay> onTimeChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.access_time),
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: currentTime,
        );
        if (time != null) {
          onTimeChanged(time);
        }
      },
    );
  }

  String _getDayLabel(int day) {
    switch (day) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.system:
        return 'Follow System';
    }
  }
}
