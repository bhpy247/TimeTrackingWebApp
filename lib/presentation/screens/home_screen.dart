import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/usecases/time_calculator.dart';
import '../../domain/usecases/salary_calculation_service.dart';
import '../../domain/entities/user_settings.dart';
import '../providers/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  WorkType _selectedWorkType = WorkType.office;
  final TextEditingController _notesController = TextEditingController();
  bool _isEditingNotes = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${hours}h ${minutes}m ${seconds}s';
  }

  String _formatBreakDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return DateFormat('hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final todayEntryAsync = ref.watch(todayTimeEntryProvider);
    final monthEntriesAsync = ref.watch(currentMonthEntriesProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todayTimeEntryProvider);
          ref.invalidate(currentMonthEntriesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              _buildHeader(theme),
              const SizedBox(height: 24),

              // Main Status Card
              todayEntryAsync.when(
                data: (entry) {
                  if (entry != null && !_isEditingNotes) {
                    _notesController.text = entry.notes ?? '';
                  }
                  return _buildStatusCard(theme, entry, settings.expectedWorkingHours);
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading today\'s entry: $err'),
                ),
              ),
              const SizedBox(height: 24),

              // Today's Notes (Only if clocked in)
              todayEntryAsync.maybeWhen(
                data: (entry) {
                  if (entry == null || entry.startTime == null) return const SizedBox.shrink();
                  return _buildNotesCard(theme, entry);
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),

              // Today's Timeline Card
              todayEntryAsync.maybeWhen(
                data: (entry) {
                  if (entry == null || entry.startTime == null) return const SizedBox.shrink();
                  return _buildTimelineCard(theme, entry);
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),

              // Today's Salary Summary Card
              monthEntriesAsync.when(
                data: (entries) => _LiveTodaySalarySummary(entries: entries, settings: settings),
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM').format(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Good Day 👋',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const LiveHeaderClock(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          dateStr,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(ThemeData theme, TimeEntry? entry, double expectedHours) {
    final isClockedIn = entry != null && entry.startTime != null;
    final isClockedOut = entry != null && entry.endTime != null;
    final isOnBreak = entry != null && entry.isOnBreak;
    final isUnclockedDayOff = entry != null &&
        entry.startTime == null &&
        (entry.workType == WorkType.halfDay || entry.workType == WorkType.leave || entry.workType == WorkType.holiday);

    String statusText = 'NOT CLOCKED IN';
    Color statusColor = Colors.grey;
    if (isClockedOut) {
      statusText = entry.workType == WorkType.halfDay ? 'HALF DAY COMPLETED' : 'CLOCKED OUT';
      statusColor = entry.workType == WorkType.halfDay ? Colors.amber.shade800 : Colors.teal;
    } else if (isOnBreak) {
      statusText = 'ON BREAK';
      statusColor = Colors.amber;
    } else if (isClockedIn) {
      statusText = entry.workType == WorkType.halfDay ? 'HALF DAY WORKING' : 'WORKING';
      statusColor = entry.workType == WorkType.halfDay ? Colors.amber.shade800 : theme.colorScheme.primary;
    } else if (isUnclockedDayOff) {
      statusText = entry.workType == WorkType.halfDay ? 'HALF DAY OFF' : entry.workType.name.toUpperCase();
      statusColor = Colors.amber.shade800;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'STATUS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Mode switcher when clocked in or completed
            if (isClockedIn || isClockedOut) ...[
              const SizedBox(height: 16),
              _buildWorkTypeChipSelector(theme, entry.workType),
            ],

            const SizedBox(height: 20),

            // Live working duration timer (or off message)
            if (isUnclockedDayOff) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.hourglass_bottom, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Marked as Half Day Off',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Target attendance: ${(expectedHours / 2.0).toStringAsFixed(1)}h work. Half-day deduction applies if unworked.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ref.read(todayTimeEntryProvider.notifier).clockIn(workType: WorkType.halfDay);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('CLOCK IN NOW'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(todayTimeEntryProvider.notifier).deleteTodayEntry();
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ] else if (isClockedIn) ...[
              _LiveDurationText(
                entry: entry,
                formatDuration: _formatDuration,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              // Live Target Progress Indicator
              _LiveTargetProgressCard(
                entry: entry,
                expectedWorkingHours: expectedHours,
              ),
            ] else if (isClockedOut) ...[
              _LiveDurationText(
                entry: entry,
                formatDuration: _formatDuration,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              _LiveTargetProgressCard(
                entry: entry,
                expectedWorkingHours: expectedHours,
              ),
            ] else ...[
              Text(
                '00h 00m 00s',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Controls
            if (!isClockedIn && !isUnclockedDayOff) ...[
              // Work type selection before Clock In
              SegmentedButton<WorkType>(
                segments: const [
                  ButtonSegment<WorkType>(
                    value: WorkType.office,
                    label: Text('Office'),
                    icon: Icon(Icons.business),
                  ),
                  ButtonSegment<WorkType>(
                    value: WorkType.wfh,
                    label: Text('WFH'),
                    icon: Icon(Icons.home_outlined),
                  ),
                  ButtonSegment<WorkType>(
                    value: WorkType.halfDay,
                    label: Text('Half Day'),
                    icon: Icon(Icons.hourglass_bottom),
                  ),
                ],
                selected: {_selectedWorkType},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedWorkType = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(todayTimeEntryProvider.notifier).clockIn(workType: _selectedWorkType);
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(_selectedWorkType == WorkType.halfDay ? 'CLOCK IN (HALF DAY)' : 'CLOCK IN'),
                style: _selectedWorkType == WorkType.halfDay
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      )
                    : theme.elevatedButtonTheme.style,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(todayTimeEntryProvider.notifier).markDayOff(WorkType.halfDay);
                },
                icon: Icon(Icons.hourglass_bottom, size: 16, color: Colors.amber.shade900),
                label: Text(
                  'Mark Today as Half Day Off (No Clock-In)',
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.amber.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else if (!isClockedOut && !isUnclockedDayOff) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (isOnBreak) {
                          ref.read(todayTimeEntryProvider.notifier).endBreak();
                        } else {
                          ref.read(todayTimeEntryProvider.notifier).startBreak();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOnBreak ? Colors.amber : Colors.orange.shade50,
                        foregroundColor: isOnBreak ? Colors.white : Colors.orange.shade900,
                        minimumSize: const Size(0, 56),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(isOnBreak ? 'END BREAK' : 'BREAK'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _showClockOutConfirmation(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 56),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('CLOCK OUT'),
                    ),
                  ),
                ],
              ),
            ] else if (isClockedOut) ...[
              // Already Clocked Out today
              Text(
                entry.workType == WorkType.halfDay
                    ? 'You completed your Half Day work! 🏖️'
                    : 'You completed your work for today! 🎉',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkTypeChipSelector(ThemeData theme, WorkType currentType) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildModeChip(theme, WorkType.office, 'Office', Icons.business, currentType == WorkType.office),
        const SizedBox(width: 8),
        _buildModeChip(theme, WorkType.wfh, 'WFH', Icons.home_outlined, currentType == WorkType.wfh),
        const SizedBox(width: 8),
        _buildModeChip(theme, WorkType.halfDay, 'Half Day', Icons.hourglass_bottom, currentType == WorkType.halfDay),
      ],
    );
  }

  Widget _buildModeChip(ThemeData theme, WorkType type, String label, IconData icon, bool isSelected) {
    final activeColor = type == WorkType.halfDay ? Colors.amber.shade800 : theme.colorScheme.primary;
    return InkWell(
      onTap: isSelected
          ? null
          : () {
              ref.read(todayTimeEntryProvider.notifier).updateWorkType(type);
            },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (type == WorkType.halfDay ? Colors.amber.shade100 : theme.colorScheme.primaryContainer.withValues(alpha: 0.5))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? activeColor : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClockOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clock Out'),
        content: const Text('Are you sure you want to clock out for today?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(todayTimeEntryProvider.notifier).clockOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 40),
            ),
            child: const Text('CLOCK OUT'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(ThemeData theme, TimeEntry entry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NOTES',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                IconButton(
                  icon: Icon(_isEditingNotes ? Icons.check : Icons.edit, size: 20),
                  onPressed: () {
                    if (_isEditingNotes) {
                      ref.read(todayTimeEntryProvider.notifier).updateNotes(_notesController.text);
                    }
                    setState(() {
                      _isEditingNotes = !_isEditingNotes;
                    });
                  },
                ),
              ],
            ),
            if (_isEditingNotes)
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'What did you work on today?',
                ),
              )
            else
              Text(
                entry.notes?.isNotEmpty == true ? entry.notes! : 'No notes added yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: entry.notes?.isNotEmpty == true
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                  fontStyle: entry.notes?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(ThemeData theme, TimeEntry entry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TODAY\'S TIMELINE',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 16),
            _buildTimelineItem(
              theme,
              time: _formatTime(entry.startTime),
              label: 'Clock In',
              description: 'Started as ${entry.workType.name.toUpperCase()}',
              isFirst: true,
              isLast: entry.breaks.isEmpty && entry.endTime == null,
            ),
            ...entry.breaks.map((b) {
              final isLastBreak = entry.breaks.last == b && entry.endTime == null;
              return Column(
                children: [
                  _buildTimelineItem(
                    theme,
                    time: _formatTime(b.startTime),
                    label: 'Break Started',
                    isFirst: false,
                    isLast: false,
                    color: Colors.amber,
                  ),
                  if (b.endTime != null)
                    _buildTimelineItem(
                      theme,
                      time: _formatTime(b.endTime),
                      label: 'Break Ended',
                      description: 'Duration: ${_formatBreakDuration(b.duration)}',
                      isFirst: false,
                      isLast: isLastBreak,
                      color: Colors.teal,
                    ),
                ],
              );
            }).toList(),
            if (entry.endTime != null)
              _buildTimelineItem(
                theme,
                time: _formatTime(entry.endTime),
                label: 'Clock Out',
                description: 'Day completed',
                isFirst: false,
                isLast: true,
                color: Colors.teal,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    ThemeData theme, {
    required String time,
    required String label,
    String? description,
    required bool isFirst,
    required bool isLast,
    Color? color,
  }) {
    final dotColor = color ?? theme.colorScheme.primary;

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.onSurface.withOpacity(0.1),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (description != null)
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveTodaySalarySummary extends StatefulWidget {
  final List<TimeEntry> entries;
  final UserSettings settings;

  const _LiveTodaySalarySummary({
    required this.entries,
    required this.settings,
  });

  @override
  State<_LiveTodaySalarySummary> createState() => _LiveTodaySalarySummaryState();
}

class _LiveTodaySalarySummaryState extends State<_LiveTodaySalarySummary> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _LiveTodaySalarySummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startTimerIfNeeded();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimerIfNeeded() {
    final hasActiveEntry = widget.entries.any((e) => e.startTime != null && e.endTime == null);
    if (hasActiveEntry) {
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  String _formatHoursMins(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else if (seconds > 0) {
      return '${seconds}s';
    } else {
      return '0h';
    }
  }

  Widget _buildSalaryRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.entries;
    final settings = widget.settings;

    final today = DateTime.now();
    final todayEntryIndex = entries.indexWhere(
      (e) => e.startTime != null &&
             e.startTime!.year == today.year &&
             e.startTime!.month == today.month &&
             e.startTime!.day == today.day,
    );
    final todayEntry = todayEntryIndex != -1 ? entries[todayEntryIndex] : null;

    final todayAttendance = todayEntry != null
        ? SalaryCalculationService.calculateAttendanceDuration(todayEntry)
        : Duration.zero;
    final rawShortfall = todayEntry != null
        ? SalaryCalculationService.calculateShortfall(todayEntry, settings.requiredDailyDurationHours)
        : Duration.zero;
    final todayShortfall = SalaryCalculationService.applyRounding(rawShortfall, settings.roundingMethod);
    final todayOvertime = todayEntry != null
        ? SalaryCalculationService.calculateOvertime(todayEntry, settings.requiredDailyDurationHours)
        : Duration.zero;

    final requiredDailyHours = todayEntry?.workType == WorkType.halfDay
        ? settings.requiredDailyDurationHours / 2.0
        : settings.requiredDailyDurationHours;
    final estimatedDeduction = SalaryCalculationService.calculateEstimatedDeduction(
      shortfall: todayShortfall,
      monthlySalary: settings.monthlySalary,
      requiredDailyHours: settings.requiredDailyDurationHours,
      payrollDays: settings.payrollDays,
      deductionMethod: settings.salaryDeductionMethod,
      roundingMethod: RoundingMethod.exact,
    );

    return Card(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TODAY\'S ESTIMATED SALARY IMPACT',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 16),
            _buildSalaryRow(theme, 'Required Hours', '${requiredDailyHours.toStringAsFixed(1)}h'),
            _buildSalaryRow(theme, 'Worked (Attendance)', _formatHoursMins(todayAttendance)),
            _buildSalaryRow(theme, 'Shortfall', _formatHoursMins(todayShortfall), valueColor: todayShortfall > Duration.zero ? Colors.red : null),
            _buildSalaryRow(theme, 'Overtime', '+${_formatHoursMins(todayOvertime)}', valueColor: todayOvertime > Duration.zero ? Colors.green : null),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated Deduction',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹${estimatedDeduction.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Widget to update and display the working duration live every second
class _LiveDurationText extends StatefulWidget {
  final TimeEntry entry;
  final String Function(Duration) formatDuration;
  final TextStyle? style;

  const _LiveDurationText({
    required this.entry,
    required this.formatDuration,
    this.style,
  });

  @override
  State<_LiveDurationText> createState() => _LiveDurationTextState();
}

class _LiveDurationTextState extends State<_LiveDurationText> {
  late Timer _timer;
  Duration _currentDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDuration();
    });
  }

  @override
  void didUpdateWidget(covariant _LiveDurationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateDuration();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateDuration() {
    setState(() {
      _currentDuration = TimeCalculator.calculateWorkingDuration(widget.entry);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.formatDuration(_currentDuration),
      style: widget.style?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class LiveHeaderClock extends StatefulWidget {
  const LiveHeaderClock({super.key});

  @override
  State<LiveHeaderClock> createState() => _LiveHeaderClockState();
}

class _LiveHeaderClockState extends State<LiveHeaderClock> {
  late Timer _timer;
  String _timeStr = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    setState(() {
      _timeStr = DateFormat('hh:mm:ss a').format(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _timeStr,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _LiveTargetProgressCard extends StatefulWidget {
  final TimeEntry entry;
  final double expectedWorkingHours;

  const _LiveTargetProgressCard({
    required this.entry,
    required this.expectedWorkingHours,
  });

  @override
  State<_LiveTargetProgressCard> createState() => _LiveTargetProgressCardState();
}

class _LiveTargetProgressCardState extends State<_LiveTargetProgressCard> {
  Timer? _timer;
  Duration _currentWorking = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void didUpdateWidget(covariant _LiveTargetProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    if (mounted) {
      setState(() {
        _currentWorking = TimeCalculator.calculateWorkingDuration(widget.entry);
      });
    }
  }

  String _formatHhMm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHalfDay = widget.entry.workType == WorkType.halfDay;
    final effectiveHours = isHalfDay ? widget.expectedWorkingHours / 2.0 : widget.expectedWorkingHours;
    final targetDuration = Duration(milliseconds: (effectiveHours * 3600 * 1000).toInt());

    final progress = targetDuration.inSeconds > 0
        ? (_currentWorking.inSeconds / targetDuration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final isCompleted = _currentWorking >= targetDuration;
    final remaining = targetDuration > _currentWorking ? targetDuration - _currentWorking : Duration.zero;
    final overtime = _currentWorking > targetDuration ? _currentWorking - targetDuration : Duration.zero;

    final barColor = isHalfDay
        ? (isCompleted ? Colors.green : Colors.amber.shade700)
        : (isCompleted ? Colors.green : theme.colorScheme.primary);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHalfDay
            ? Colors.amber.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHalfDay
              ? Colors.amber.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isHalfDay ? Icons.hourglass_bottom : Icons.timer_outlined,
                    size: 16,
                    color: isHalfDay ? Colors.amber.shade800 : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isHalfDay ? 'HALF DAY TARGET' : 'DAILY WORK TARGET',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isHalfDay ? Colors.amber.shade900 : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCompleted ? Colors.green.shade700 : (isHalfDay ? Colors.amber.shade900 : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatHhMm(_currentWorking)} / ${_formatHhMm(targetDuration)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isCompleted)
                Text(
                  overtime > Duration.zero ? '+${_formatHhMm(overtime)} Overtime 🎉' : 'Target Reached! 🎉',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                )
              else
                Text(
                  '${_formatHhMm(remaining)} remaining',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
