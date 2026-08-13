import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/usecases/time_calculator.dart';
import '../providers/providers.dart';

class DailyDetailScreen extends ConsumerStatefulWidget {
  final DateTime date; // Local midnight representing the day

  const DailyDetailScreen({super.key, required this.date});

  @override
  ConsumerState<DailyDetailScreen> createState() => _DailyDetailScreenState();
}


class _DailyDetailScreenState extends ConsumerState<DailyDetailScreen> {
  bool _isLoading = true;
  TimeEntry? _entry;
  WorkType _workType = WorkType.office;
  DateTime? _startTime;
  DateTime? _endTime;
  final List<BreakEntry> _breaks = [];
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDayData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDayData() async {
    final repo = ref.read(timeEntryRepositoryProvider);
    final entries = await repo.getAllEntries();
    
    // Find matching entry for this date
    TimeEntry? matching;
    try {
      matching = entries.firstWhere((e) =>
          e.date.year == widget.date.year &&
          e.date.month == widget.date.month &&
          e.date.day == widget.date.day);
    } catch (_) {
      matching = null;
    }

    if (mounted) {
      setState(() {
        _entry = matching;
        _workType = matching?.workType ?? WorkType.office;
        _startTime = matching?.startTime;
        _endTime = matching?.endTime;
        _breaks.clear();
        if (matching?.breaks != null) {
          _breaks.addAll(matching!.breaks);
        }
        _notesController.text = matching?.notes ?? '';
        _isLoading = false;
      });
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'Not set';
    return DateFormat('hh:mm a').format(dt);
  }

  String _formatDuration(Duration d) {
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

  Future<void> _selectTime(bool isStart) async {
    final initialDateTime = (isStart ? _startTime : _endTime) ?? DateTime.now();
    final TimeOfDay initialTime = TimeOfDay.fromDateTime(initialDateTime);

    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (selectedTime != null && mounted) {
      setState(() {
        final newDateTime = DateTime(
          widget.date.year,
          widget.date.month,
          widget.date.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        if (isStart) {
          _startTime = newDateTime;
        } else {
          _endTime = newDateTime;
        }
      });
    }
  }

  Future<void> _addBreak() async {
    final TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 13, minute: 0),
      helpText: 'Select Break Start Time',
    );
    if (start == null) return;

    final TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 13, minute: 45),
      helpText: 'Select Break End Time',
    );
    if (end == null) return;

    if (mounted) {
      setState(() {
        _breaks.add(BreakEntry(
          startTime: DateTime(widget.date.year, widget.date.month, widget.date.day, start.hour, start.minute),
          endTime: DateTime(widget.date.year, widget.date.month, widget.date.day, end.hour, end.minute),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      });
    }
  }

  Future<void> _save() async {
    final repo = ref.read(timeEntryRepositoryProvider);

    // If start time is set, construct the entry
    final newEntry = TimeEntry(
      id: _entry?.id,
      date: widget.date,
      startTime: _startTime,
      endTime: _endTime,
      workType: _workType,
      notes: _notesController.text,
      breaks: _breaks,
      createdAt: _entry?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await repo.saveEntry(newEntry);
    ref.invalidate(todayTimeEntryProvider);
    ref.invalidate(currentMonthEntriesProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry saved successfully.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    if (_entry?.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this time entry? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final repo = ref.read(timeEntryRepositoryProvider);
      await repo.deleteEntry(_entry!.id!);
      ref.invalidate(todayTimeEntryProvider);
      ref.invalidate(currentMonthEntriesProvider);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry deleted.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Dummy entry for calculation previews
    final previewEntry = TimeEntry(
      date: widget.date,
      startTime: _startTime,
      endTime: _endTime,
      workType: _workType,
      breaks: _breaks,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final gross = TimeCalculator.calculateGrossDuration(previewEntry);
    final breakDuration = TimeCalculator.calculateBreakDuration(previewEntry);
    final working = TimeCalculator.calculateWorkingDuration(previewEntry);
    final overtime = TimeCalculator.calculateOvertime(previewEntry, settings.expectedWorkingHours);
    final shortfall = TimeCalculator.calculateShortfall(previewEntry, settings.expectedWorkingHours);

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEE, d MMMM yyyy').format(widget.date)),
        actions: [
          if (_entry != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Work Type Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WORK TYPE', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: WorkType.values.map((type) {
                      final isSelected = _workType == type;
                      
                      IconData icon;
                      String label;
                      switch (type) {
                        case WorkType.office:
                          icon = Icons.business;
                          label = 'Office';
                          break;
                        case WorkType.wfh:
                          icon = Icons.home_outlined;
                          label = 'WFH';
                          break;
                        case WorkType.leave:
                          icon = Icons.beach_access_outlined;
                          label = 'Leave';
                          break;
                        case WorkType.holiday:
                          icon = Icons.star_outline;
                          label = 'Holiday';
                          break;
                      }

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _workType = type;
                                if (_workType == WorkType.leave || _workType == WorkType.holiday) {
                                  _startTime = null;
                                  _endTime = null;
                                  _breaks.clear();
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                                    : theme.colorScheme.surfaceVariant.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 20,
                                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Working Hours Inputs (Only if Office / WFH)
          if (_workType == WorkType.office || _workType == WorkType.wfh) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIME INTERVALS', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start Time'),
                      subtitle: Text(_formatTime(_startTime)),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () => _selectTime(true),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End Time'),
                      subtitle: Text(_formatTime(_endTime)),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () => _selectTime(false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Breaks Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('BREAKS', style: theme.textTheme.labelMedium),
                        TextButton.icon(
                          onPressed: _addBreak,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Break'),
                        ),
                      ],
                    ),
                    if (_breaks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No breaks added.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ..._breaks.map((b) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Break duration: ${_formatDuration(b.duration)}'),
                            subtitle: Text('${_formatTime(b.startTime)} → ${_formatTime(b.endTime)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _breaks.remove(b);
                                });
                              },
                            ),
                          )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Calculations Summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CALCULATION SUMMARY', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 16),
                    _buildCalculationRow(theme, 'Gross Duration', _formatDuration(gross)),
                    _buildCalculationRow(theme, 'Break Duration', '- ${_formatDuration(breakDuration)}'),
                    const Divider(),
                    _buildCalculationRow(
                      theme,
                      'Actual Work Duration',
                      _formatDuration(working),
                      valueColor: theme.colorScheme.primary,
                      isBold: true,
                    ),
                    if (overtime > Duration.zero)
                      _buildCalculationRow(theme, 'Overtime', '+ ${_formatDuration(overtime)}', valueColor: Colors.green)
                    else if (shortfall > Duration.zero)
                      _buildCalculationRow(theme, 'Shortfall', '- ${_formatDuration(shortfall)}', valueColor: Colors.red),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Notes
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAILY NOTES', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Add notes about WFH, leaves, projects, or tasks completed...',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          ElevatedButton(
            onPressed: _save,
            child: const Text('SAVE ENTRY'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
