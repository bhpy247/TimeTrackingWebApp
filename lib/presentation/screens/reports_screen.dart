import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/file_saver/file_saver.dart' as saver;
import '../../domain/entities/time_entry.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/time_calculator.dart';
import '../../domain/usecases/salary_calculation_service.dart';
import '../../services/report/report_service.dart';
import '../providers/providers.dart';
import 'daily_detail_screen.dart';

enum ReportScope { month, allTime, customRange }

final reportScopeProvider = StateProvider<ReportScope>((ref) => ReportScope.month);

final selectedReportMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final reportCustomDateRangeProvider = StateProvider<DateTimeRange?>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month, now.day),
  );
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  int _getDaysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(reportScopeProvider);
    final selectedMonth = ref.watch(selectedReportMonthProvider);
    final customRange = ref.watch(reportCustomDateRangeProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    // Watch relevant provider based on scope
    final AsyncValue<List<TimeEntry>> entriesAsync = scope == ReportScope.month
        ? ref.watch(monthlyEntriesProvider(selectedMonth))
        : ref.watch(allEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        centerTitle: true,
      ),
      body: entriesAsync.when(
        data: (rawEntries) {
          // Filter entries depending on active scope
          List<TimeEntry> entries;
          String scopeLabel;
          String filePrefix;

          if (scope == ReportScope.month) {
            entries = rawEntries
                .where((e) => e.date.year == selectedMonth.year && e.date.month == selectedMonth.month)
                .toList();
            scopeLabel = DateFormat('MMMM yyyy').format(selectedMonth);
            filePrefix = 'time_report_${DateFormat('yyyy_MM').format(selectedMonth)}';
          } else if (scope == ReportScope.allTime) {
            entries = List<TimeEntry>.from(rawEntries);
            scopeLabel = 'All Records (${entries.length} entries)';
            filePrefix = 'time_report_all_records';
          } else {
            final start = customRange?.start ?? DateTime(selectedMonth.year, selectedMonth.month, 1);
            final end = customRange?.end ?? DateTime(selectedMonth.year, selectedMonth.month, selectedMonth.day);
            final startMidnight = DateTime(start.year, start.month, start.day);
            final endMidnight = DateTime(end.year, end.month, end.day, 23, 59, 59);

            entries = rawEntries.where((e) {
              return e.date.isAfter(startMidnight.subtract(const Duration(seconds: 1))) &&
                  e.date.isBefore(endMidnight.add(const Duration(seconds: 1)));
            }).toList();
            scopeLabel = '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';
            filePrefix = 'time_report_${DateFormat('yyyyMMdd').format(start)}_${DateFormat('yyyyMMdd').format(end)}';
          }

          // Sort entries chronologically for display
          entries.sort((a, b) => a.date.compareTo(b.date));

          final totalDays = scope == ReportScope.month ? _getDaysInMonth(selectedMonth) : entries.length;

          // Salary & Attendance calculations
          Duration monthlyAttendance = Duration.zero;
          Duration monthlyShortfall = Duration.zero;
          Duration monthlySalaryOvertime = Duration.zero;

          for (final entry in entries) {
            monthlyAttendance += SalaryCalculationService.calculateAttendanceDuration(entry);
            final rawShortfall = SalaryCalculationService.calculateShortfall(entry, settings.requiredDailyDurationHours);
            final roundedShortfall = SalaryCalculationService.applyRounding(rawShortfall, settings.roundingMethod);
            monthlyShortfall += roundedShortfall;
            monthlySalaryOvertime += SalaryCalculationService.calculateOvertime(entry, settings.requiredDailyDurationHours);
          }

          final requiredMonthHours = settings.payrollDays * settings.requiredDailyDurationHours;
          final estimatedDeduction = SalaryCalculationService.calculateEstimatedDeduction(
            shortfall: monthlyShortfall,
            monthlySalary: settings.monthlySalary,
            requiredDailyHours: settings.requiredDailyDurationHours,
            payrollDays: settings.payrollDays,
            deductionMethod: settings.salaryDeductionMethod,
            roundingMethod: RoundingMethod.exact,
          );
          final estimatedPayableSalary = settings.monthlySalary - estimatedDeduction;

          // Calculate dynamic Y-axis maximum based on actual logged hours
          final maxHours = entries.isEmpty
              ? 0.0
              : entries
                  .map((e) => TimeCalculator.calculateWorkingDuration(e).inMinutes / 60.0)
                  .fold<double>(0.0, (max, val) => val > max ? val : max);
          
          final chartMaxY = maxHours == 0.0
              ? 8.0
              : maxHours <= 0.1
                  ? 0.1 // 6 mins max
                  : maxHours <= 1.0
                      ? 1.0 // 1 hour max
                      : maxHours <= 4.0
                          ? 4.0 // 4 hours max
                          : (maxHours + 1.0).ceilToDouble();

          // Calculations
          final totalDuration = TimeCalculator.calculateMonthlyTotal(entries);
          final averageDuration = TimeCalculator.calculateMonthlyAverage(entries);

          int presentCount = 0;
          int wfhCount = 0;
          int leaveCount = 0;
          int holidayCount = 0;
          int lateArrivals = 0;
          int earlyDepartures = 0;

          Duration longestDuration = Duration.zero;
          Duration shortestDuration = const Duration(hours: 24);
          TimeEntry? longestEntry;
          TimeEntry? shortestEntry;

          double startMinsTotal = 0;
          double endMinsTotal = 0;
          int startCount = 0;
          int endCount = 0;

          for (final entry in entries) {
            switch (entry.workType) {
              case WorkType.office:
                presentCount++;
                break;
              case WorkType.wfh:
                wfhCount++;
                break;
              case WorkType.leave:
                leaveCount++;
                break;
              case WorkType.holiday:
                holidayCount++;
                break;
            }

            if (entry.startTime != null) {
              final working = TimeCalculator.calculateWorkingDuration(entry);
              
              // Longest/Shortest
              if (working > longestDuration) {
                longestDuration = working;
                longestEntry = entry;
              }
              if (working < shortestDuration && working > Duration.zero) {
                shortestDuration = working;
                shortestEntry = entry;
              }

              // Avg Start/End times
              startMinsTotal += entry.startTime!.hour * 60 + entry.startTime!.minute;
              startCount++;

              if (entry.endTime != null) {
                endMinsTotal += entry.endTime!.hour * 60 + entry.endTime!.minute;
                endCount++;

                // Late arrival / Early departure counts
                final late = TimeCalculator.calculateLateArrival(entry, settings.expectedStartTime);
                final early = TimeCalculator.calculateEarlyDeparture(entry, settings.expectedEndTime);
                if (late > const Duration(minutes: 5)) lateArrivals++;
                if (early > const Duration(minutes: 5)) earlyDepartures++;
              }
            }
          }

          final workingDays = presentCount + wfhCount;
          final expectedHours = workingDays * settings.expectedWorkingHours;

          // Average times
          TimeOfDay? avgStartTime;
          if (startCount > 0) {
            final avgStartMins = (startMinsTotal / startCount).round();
            avgStartTime = TimeOfDay(hour: avgStartMins ~/ 60, minute: avgStartMins % 60);
          }
          TimeOfDay? avgEndTime;
          if (endCount > 0) {
            final avgEndMins = (endMinsTotal / endCount).round();
            avgEndTime = TimeOfDay(hour: avgEndMins ~/ 60, minute: avgEndMins % 60);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Scope Selector (Month vs All Records vs Custom Range)
              SegmentedButton<ReportScope>(
                segments: const [
                  ButtonSegment(
                    value: ReportScope.month,
                    label: Text('Monthly'),
                    icon: Icon(Icons.calendar_month, size: 18),
                  ),
                  ButtonSegment(
                    value: ReportScope.allTime,
                    label: Text('All Records'),
                    icon: Icon(Icons.all_inbox, size: 18),
                  ),
                  ButtonSegment(
                    value: ReportScope.customRange,
                    label: Text('Range'),
                    icon: Icon(Icons.date_range, size: 18),
                  ),
                ],
                selected: {scope},
                onSelectionChanged: (newSelection) {
                  ref.read(reportScopeProvider.notifier).state = newSelection.first;
                },
              ),
              const SizedBox(height: 16),

              // Period Switcher Header
              if (scope == ReportScope.month)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous month',
                          onPressed: () {
                            final prevMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                            ref.read(selectedReportMonthProvider.notifier).state = prevMonth;
                            ref.read(selectedMonthProvider.notifier).state = prevMonth;
                          },
                        ),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedMonth,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              helpText: 'SELECT REPORT MONTH',
                            );
                            if (picked != null) {
                              final newMonth = DateTime(picked.year, picked.month, 1);
                              ref.read(selectedReportMonthProvider.notifier).state = newMonth;
                              ref.read(selectedMonthProvider.notifier).state = newMonth;
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  scopeLabel,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next month',
                          onPressed: () {
                            final nextMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                            ref.read(selectedReportMonthProvider.notifier).state = nextMonth;
                            ref.read(selectedMonthProvider.notifier).state = nextMonth;
                          },
                        ),
                      ],
                    ),
                  ),
                )
              else if (scope == ReportScope.customRange)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            scopeLabel,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              initialDateRange: customRange ??
                                  DateTimeRange(
                                    start: DateTime(selectedMonth.year, selectedMonth.month, 1),
                                    end: DateTime.now(),
                                  ),
                            );
                            if (picked != null) {
                              ref.read(reportCustomDateRangeProvider.notifier).state = picked;
                            }
                          },
                          icon: const Icon(Icons.date_range, size: 18),
                          label: const Text('Change Range'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.all_inbox_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'All-Time History: ${entries.length} records across all dates',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Export actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final filename = '$filePrefix.csv';
                        const mimeType = 'text/csv';
                        final csvBytes = await ReportService.generateCSV(
                          entries,
                          title: 'Time Tracking Report - $scopeLabel',
                        );
                        final location = await saver.saveAndShareFile(
                          csvBytes,
                          filename,
                          mimeType,
                        );
                        if (!context.mounted) return;
                        await _showExportSuccessDialog(
                          context,
                          filename: filename,
                          location: location,
                          recordCount: entries.length,
                          isPdf: false,
                          bytes: csvBytes,
                          mimeType: mimeType,
                        );
                      },
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text('Export CSV (${entries.length})'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final filename = '$filePrefix.pdf';
                        const mimeType = 'application/pdf';
                        final pdfBytes = await ReportService.generatePDF(
                          entries,
                          scope == ReportScope.month ? selectedMonth : null,
                          settings,
                          title: scope == ReportScope.month
                              ? 'Monthly Time Tracking Report'
                              : 'Time Tracking Report',
                          periodLabel: scopeLabel,
                        );
                        final location = await saver.saveAndShareFile(
                          pdfBytes,
                          filename,
                          mimeType,
                        );
                        if (!context.mounted) return;
                        await _showExportSuccessDialog(
                          context,
                          filename: filename,
                          location: location,
                          recordCount: entries.length,
                          isPdf: true,
                          bytes: pdfBytes,
                          mimeType: mimeType,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text('Export PDF (${entries.length})'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 1. Attendance overview card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ATTENDANCE OVERVIEW', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildReportStatItem(theme, '$workingDays', 'Days worked'),
                          _buildReportStatItem(theme, '$presentCount', 'Office'),
                          _buildReportStatItem(theme, '$wfhCount', 'WFH'),
                          _buildReportStatItem(theme, '$leaveCount', 'Leave'),
                          _buildReportStatItem(theme, '$holidayCount', 'Holidays'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Work Hours card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WORKING HOURS', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 16),
                      _buildRowDetail(theme, 'Total Hours Worked', _formatDuration(totalDuration)),
                      _buildRowDetail(theme, 'Expected Hours', '${expectedHours.toStringAsFixed(1)} hours'),
                      _buildRowDetail(theme, 'Average / Day', _formatDuration(averageDuration)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Salary & Attendance Impact Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ESTIMATED SALARY & ATTENDANCE IMPACT', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 16),
                      _buildRowDetail(theme, 'Monthly Salary', '₹${settings.monthlySalary.toStringAsFixed(0)}'),
                      _buildRowDetail(theme, 'Required Hours', '${requiredMonthHours.toStringAsFixed(1)} hours'),
                      _buildRowDetail(theme, 'Actual Attendance', _formatHoursMins(monthlyAttendance)),
                      _buildRowDetail(
                        theme,
                        'Shortfall',
                        _formatHoursMins(monthlyShortfall),
                        valueColor: monthlyShortfall > Duration.zero ? Colors.red : null,
                      ),
                      _buildRowDetail(
                        theme,
                        'Overtime',
                        '+${_formatHoursMins(monthlySalaryOvertime)}',
                        valueColor: monthlySalaryOvertime > Duration.zero ? Colors.green : null,
                      ),
                      const Divider(),
                      _buildRowDetail(
                        theme,
                        'Estimated Deduction',
                        '₹${estimatedDeduction.toStringAsFixed(0)}',
                        valueColor: estimatedDeduction > 0 ? Colors.red : null,
                        isBold: true,
                      ),
                      _buildRowDetail(
                        theme,
                        'Est. Payable Salary',
                        '₹${estimatedPayableSalary.toStringAsFixed(0)}',
                        valueColor: theme.colorScheme.primary,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Daily Hours Chart Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DAILY HOURS CHART', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 20),
                      if (entries.isEmpty)
                        Container(
                          height: 200,
                          alignment: Alignment.center,
                          child: Text(
                            scope == ReportScope.month
                                ? 'No time entries for this month.'
                                : 'No time entries for this period.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.4),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16, right: 16),
                            child: SizedBox(
                              width: scope == ReportScope.month
                                  ? 600
                                  : (entries.length * 35.0).clamp(400.0, 1500.0),
                              height: 200,
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: chartMaxY * 1.15, // Add a 15% top buffer to prevent label clipping
                                  barTouchData: BarTouchData(
                                    enabled: true,
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipColor: (group) => theme.colorScheme.inverseSurface,
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        final hours = rod.toY;
                                        final duration = Duration(minutes: (hours * 60).round());
                                        
                                        String formatted;
                                        if (duration == Duration.zero) {
                                          formatted = '0h';
                                        } else {
                                          final h = duration.inHours;
                                          final m = duration.inMinutes % 60;
                                          final s = duration.inSeconds % 60;
                                          if (h > 0) {
                                            formatted = '${h}h ${m}m';
                                          } else if (m > 0) {
                                            formatted = '${m}m';
                                          } else {
                                            formatted = '${s}s';
                                          }
                                        }

                                        String labelText;
                                        if (scope == ReportScope.month) {
                                          labelText = 'Day ${group.x.toInt()}\n';
                                        } else {
                                          final idx = group.x.toInt() - 1;
                                          if (idx >= 0 && idx < entries.length) {
                                            labelText = '${DateFormat('MMM d').format(entries[idx].date)}\n';
                                          } else {
                                            labelText = 'Entry ${group.x.toInt()}\n';
                                          }
                                        }

                                        return BarTooltipItem(
                                          labelText,
                                          TextStyle(
                                            color: theme.colorScheme.onInverseSurface,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: formatted,
                                              style: TextStyle(
                                                color: theme.brightness == Brightness.dark
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.onInverseSurface,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    show: true,
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (val, meta) {
                                          if (scope == ReportScope.month) {
                                            if (val.toInt() <= 0 || val.toInt() > totalDays) {
                                              return const SizedBox.shrink();
                                            }
                                            if (val.toInt() % 5 == 0 || val.toInt() == 1 || val.toInt() == totalDays) {
                                              return Text('${val.toInt()}', style: const TextStyle(fontSize: 8));
                                            }
                                            return const SizedBox.shrink();
                                          } else {
                                            final idx = val.toInt() - 1;
                                            if (idx >= 0 && idx < entries.length) {
                                              return Text(DateFormat('d/M').format(entries[idx].date),
                                                  style: const TextStyle(fontSize: 8));
                                            }
                                            return const SizedBox.shrink();
                                          }
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 35,
                                        getTitlesWidget: (value, meta) {
                                          if (value == 0.0) return const Text('0', style: TextStyle(fontSize: 8));
                                          if (chartMaxY <= 0.1) {
                                            final mins = (value * 60).round();
                                            return Text('${mins}m', style: const TextStyle(fontSize: 8));
                                          }
                                          if (chartMaxY <= 1.0) {
                                            final mins = (value * 60).round();
                                            return Text('${mins}m', style: const TextStyle(fontSize: 8));
                                          }
                                          // Format whole hours as e.g. "8h" instead of "8.0h" to save space
                                          final isInteger = value.truncateToDouble() == value;
                                          final formatted = isInteger ? value.toInt().toString() : value.toStringAsFixed(1);
                                          return Text('${formatted}h', style: const TextStyle(fontSize: 8));
                                        },
                                      ),
                                    ),
                                  ),
                                  gridData: const FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  barGroups: scope == ReportScope.month
                                      ? List.generate(totalDays, (i) {
                                          final day = i + 1;
                                          double valY = 0.0;
                                          try {
                                            final dayEntry = entries.firstWhere((e) => e.date.day == day);
                                            valY = TimeCalculator.calculateWorkingDuration(dayEntry).inMinutes / 60.0;
                                          } catch (_) {}

                                          return BarChartGroupData(
                                            x: day,
                                            barRods: [
                                              BarChartRodData(
                                                toY: valY,
                                                color: theme.colorScheme.primary,
                                                width: 8,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ],
                                          );
                                        })
                                      : List.generate(entries.length, (i) {
                                          final entry = entries[i];
                                          final valY = TimeCalculator.calculateWorkingDuration(entry).inMinutes / 60.0;
                                          return BarChartGroupData(
                                            x: i + 1,
                                            barRods: [
                                              BarChartRodData(
                                                toY: valY,
                                                color: theme.colorScheme.primary,
                                                width: 10,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ],
                                          );
                                        }),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Work Patterns Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WORKING PATTERNS', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 16),
                      _buildRowDetail(theme, 'Avg Start Time', avgStartTime != null ? _formatTimeOfDay(avgStartTime) : '--:--'),
                      _buildRowDetail(theme, 'Avg End Time', avgEndTime != null ? _formatTimeOfDay(avgEndTime) : '--:--'),
                      _buildRowDetail(theme, 'Late Arrivals (> 5m)', '$lateArrivals times'),
                      _buildRowDetail(theme, 'Early Departures (> 5m)', '$earlyDepartures times'),
                      _buildRowDetail(
                        theme,
                        'Longest Day',
                        longestEntry != null
                            ? '${_formatDuration(longestDuration)} (${DateFormat('MMM d').format(longestEntry.date)})'
                            : '--:--',
                      ),
                      _buildRowDetail(
                        theme,
                        'Shortest Day',
                        shortestEntry != null
                            ? '${_formatDuration(shortestDuration)} (${DateFormat('MMM d').format(shortestEntry.date)})'
                            : '--:--',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Daily Activity Logs Section (List of records included in this report)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ACTIVITY LOG (${entries.length} RECORDS)', style: theme.textTheme.labelMedium),
                          if (entries.isNotEmpty)
                            Text(
                              'Tap record to edit',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No activity logs recorded for this period.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final entry = entries[i];
                            final netDuration = TimeCalculator.calculateWorkingDuration(entry);
                            final formattedNet = _formatDuration(netDuration);
                            final inTime = entry.startTime != null ? DateFormat('hh:mm a').format(entry.startTime!) : '--:--';
                            final outTime = entry.endTime != null ? DateFormat('hh:mm a').format(entry.endTime!) : '--:--';

                            Color badgeColor;
                            switch (entry.workType) {
                              case WorkType.office:
                                badgeColor = Colors.blue;
                                break;
                              case WorkType.wfh:
                                badgeColor = Colors.teal;
                                break;
                              case WorkType.leave:
                                badgeColor = Colors.orange;
                                break;
                              case WorkType.holiday:
                                badgeColor = Colors.purple;
                                break;
                            }

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              onTap: () async {
                                final res = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => DailyDetailScreen(date: entry.date),
                                  ),
                                );
                                if (res == true) {
                                  ref.invalidate(monthlyEntriesProvider);
                                  ref.invalidate(allEntriesProvider);
                                }
                              },
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: badgeColor.withOpacity(0.4)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  DateFormat('d\nMMM').format(entry.date),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: badgeColor,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    DateFormat('EEEE').format(entry.date),
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.workType.name.toUpperCase(),
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'In: $inTime  •  Out: $outTime${entry.notes != null && entry.notes!.isNotEmpty ? '\n${entry.notes}' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                              ),
                              trailing: Text(
                                formattedNet,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading report: $err')),
      ),
    );
  }

  Widget _buildReportStatItem(ThemeData theme, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
      ],
    );
  }

  Widget _buildRowDetail(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
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

  Future<void> _showExportSuccessDialog(
    BuildContext context, {
    required String filename,
    required String location,
    required int recordCount,
    required bool isPdf,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 36),
        ),
        title: Text(
          isPdf ? 'PDF Report Ready' : 'CSV Report Ready',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your report has been generated and saved.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isPdf ? Icons.picture_as_pdf : Icons.table_chart, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('• Records: $recordCount entries included', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('• Saved to: $location', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await saver.shareDownloadedFile(
                location,
                subject: isPdf ? 'Time Tracking PDF Report' : 'Time Tracking CSV Report',
                text: 'Time Tracking Report: $filename ($recordCount entries)',
                bytes: bytes,
                filename: filename,
              );
            },
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Share'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await saver.openDownloadedFile(
                location,
                mimeType: mimeType,
                bytes: bytes,
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

