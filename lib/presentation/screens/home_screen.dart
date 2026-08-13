import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/usecases/time_calculator.dart';
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

              // Monthly Summary Card
              monthEntriesAsync.when(
                data: (entries) => _buildMonthlySummary(theme, entries, settings.expectedWorkingHours),
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

    String statusText = 'NOT CLOCKED IN';
    Color statusColor = Colors.grey;
    if (isClockedOut) {
      statusText = 'CLOCKED OUT';
      statusColor = Colors.teal;
    } else if (isOnBreak) {
      statusText = 'ON BREAK';
      statusColor = Colors.amber;
    } else if (isClockedIn) {
      statusText = 'WORKING';
      statusColor = theme.colorScheme.primary;
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
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
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
            const SizedBox(height: 24),

            // Live working duration timer
            if (entry != null && entry.startTime != null)
              _LiveDurationText(
                entry: entry,
                formatDuration: _formatDuration,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              )
            else
              Text(
                '00h 00m 00s',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 24),

            // Controls
            if (!isClockedIn) ...[
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
                label: const Text('CLOCK IN'),
                style: theme.elevatedButtonTheme.style,
              ),
            ] else if (!isClockedOut) ...[
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
            ] else ...[
              // Already Clocked Out today
              Text(
                'You completed your work for today! 🎉',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
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

  Widget _buildMonthlySummary(ThemeData theme, List<TimeEntry> entries, double expectedHours) {
    final totalDuration = TimeCalculator.calculateMonthlyTotal(entries);
    final averageDuration = TimeCalculator.calculateMonthlyAverage(entries);

    // Sum up overtime
    Duration totalOvertime = Duration.zero;
    for (final entry in entries) {
      totalOvertime += TimeCalculator.calculateOvertime(entry, expectedHours);
    }

    String formatDurationSummary(Duration d) {
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

    final totalHoursStr = formatDurationSummary(totalDuration);
    final averageHoursStr = formatDurationSummary(averageDuration);
    final overtimeStr = '+${formatDurationSummary(totalOvertime)}';

    final now = DateTime.now();
    final monthName = DateFormat('MMMM').format(now);

    return Card(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthName.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryStat(theme, totalHoursStr, 'Total Hours'),
                _buildSummaryStat(theme, averageHoursStr, 'Average'),
                _buildSummaryStat(theme, overtimeStr, 'Overtime', color: Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(ThemeData theme, String value, String label, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
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
