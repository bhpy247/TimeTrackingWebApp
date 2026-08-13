import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/usecases/time_calculator.dart';
import '../providers/providers.dart';
import 'daily_detail_screen.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  int _getDaysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  int _getFirstDayOffset(DateTime month) {
    // DateTime.weekday is Mon=1, Sun=7.
    // If offset is for Monday-first: Mon=0 offset, Sun=6 offset.
    return DateTime(month.year, month.month, 1).weekday - 1;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final entriesAsync = ref.watch(monthlyCalendarEntriesProvider(selectedMonth));
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    final monthStr = DateFormat('MMMM yyyy').format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Month Selector Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    ref.read(selectedMonthProvider.notifier).state =
                        DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                  },
                ),
                Text(
                  monthStr,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    ref.read(selectedMonthProvider.notifier).state =
                        DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                  },
                ),
              ],
            ),
          ),

          // Weekday Labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map((day) => Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onBackground.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Grid View of Days
          Expanded(
            child: entriesAsync.when(
              data: (entries) {
                final totalDays = _getDaysInMonth(selectedMonth);
                final offset = _getFirstDayOffset(selectedMonth);
                final totalCells = totalDays + offset;

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    if (index < offset) {
                      return const SizedBox.shrink();
                    }

                    final dayNumber = index - offset + 1;
                    final dayDate = DateTime(selectedMonth.year, selectedMonth.month, dayNumber);
                    final isToday = _isToday(dayDate);

                    // Find if there is an entry for this day
                    TimeEntry? dayEntry;
                    try {
                      dayEntry = entries.firstWhere((e) => e.date.day == dayNumber);
                    } catch (_) {
                      dayEntry = null;
                    }

                    return _buildDayCell(
                      context,
                      ref,
                      theme: theme,
                      date: dayDate,
                      dayNum: dayNumber,
                      entry: dayEntry,
                      isToday: isToday,
                      settingsWorkingDays: settings.workingDays,
                      expectedHours: settings.expectedWorkingHours,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading entries: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    WidgetRef ref, {
    required ThemeData theme,
    required DateTime date,
    required int dayNum,
    required TimeEntry? entry,
    required bool isToday,
    required List<int> settingsWorkingDays,
    required double expectedHours,
  }) {
    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final isConfiguredWorkingDay = settingsWorkingDays.contains(date.weekday);
    final isInPast = date.isBefore(DateTime.now());

    Color? backgroundColor;
    Border? border;
    Widget? statusIndicator;
    Color textColor = theme.colorScheme.onBackground;

    // Check entry statuses
    if (entry != null) {
      if (entry.workType == WorkType.holiday) {
        backgroundColor = theme.colorScheme.tertiaryContainer.withOpacity(0.4);
        statusIndicator = Icon(Icons.star, size: 14, color: theme.colorScheme.tertiary);
      } else if (entry.workType == WorkType.leave) {
        backgroundColor = theme.colorScheme.secondaryContainer.withOpacity(0.4);
        statusIndicator = Icon(Icons.beach_access, size: 14, color: theme.colorScheme.secondary);
      } else if (entry.startTime != null) {
        final working = TimeCalculator.calculateWorkingDuration(entry);
        textColor = Colors.white;
        backgroundColor = entry.endTime == null
            ? theme.colorScheme.primary.withOpacity(0.85) // Ticking working day
            : Colors.green.shade600; // Completed day
        
        statusIndicator = Text(
          '${working.inHours}h ${working.inMinutes % 60}m',
          style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600),
        );
      }
    } else {
      // Missing entry check
      if (isInPast && isConfiguredWorkingDay && !isToday) {
        backgroundColor = Colors.red.shade50;
        border = Border.all(color: Colors.red.shade200, width: 1.5);
        statusIndicator = Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade600);
        textColor = Colors.red.shade900;
      } else if (isWeekend) {
        textColor = theme.colorScheme.onBackground.withOpacity(0.35);
      }
    }

    if (isToday) {
      border = Border.all(color: theme.colorScheme.primary, width: 2);
    }

    return InkWell(
      onTap: () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DailyDetailScreen(date: date),
          ),
        );
        if (result == true) {
          // Re-evaluate monthly calendar entries provider
          ref.invalidate(monthlyCalendarEntriesProvider(DateTime(date.year, date.month, 1)));
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: border ?? Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5), width: 1),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                '$dayNum',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            if (statusIndicator != null)
              Align(
                alignment: Alignment.bottomRight,
                child: statusIndicator,
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
