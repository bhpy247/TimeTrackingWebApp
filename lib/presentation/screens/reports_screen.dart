import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/file_saver/file_saver.dart' as saver;
import '../../domain/entities/time_entry.dart';
import '../../domain/usecases/time_calculator.dart';
import '../../services/report/report_service.dart';
import '../providers/providers.dart';

final selectedReportMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
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
    final selectedMonth = ref.watch(selectedReportMonthProvider);
    final entriesAsync = ref.watch(currentMonthEntriesProvider); // Refers to database provider cached month
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    final monthStr = DateFormat('MMMM yyyy').format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        centerTitle: true,
      ),
      body: entriesAsync.when(
        data: (allEntries) {
          // Filter entries for the selected month specifically (allEntries from provider is today-reactive, let's filter)
          final entries = allEntries
              .where((e) => e.date.year == selectedMonth.year && e.date.month == selectedMonth.month)
              .toList();

          final totalDays = _getDaysInMonth(selectedMonth);

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
          final expectedMonthHours = workingDays * settings.expectedWorkingHours;

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
              // Month Switcher Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      ref.read(selectedReportMonthProvider.notifier).state =
                          DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
                    },
                  ),
                  Text(
                    monthStr,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      ref.read(selectedReportMonthProvider.notifier).state =
                          DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Export actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final csvBytes = await ReportService.generateCSV(entries);
                        await saver.saveAndShareFile(
                          csvBytes,
                          'time_report_${DateFormat('yyyy_MM').format(selectedMonth)}.csv',
                          'text/csv',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('CSV Report downloaded successfully.')),
                        );
                      },
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Export CSV'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final pdfBytes = await ReportService.generatePDF(entries, selectedMonth, settings);
                        await saver.saveAndShareFile(
                          pdfBytes,
                          'time_report_${DateFormat('yyyy_MM').format(selectedMonth)}.pdf',
                          'application/pdf',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PDF Report generated and downloaded.')),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Export PDF'),
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
                      _buildRowDetail(theme, 'Expected Hours', '${expectedMonthHours.toStringAsFixed(1)} hours'),
                      _buildRowDetail(theme, 'Average / Day', _formatDuration(averageDuration)),
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
                            'No time entries for this month.',
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
                              width: 600,
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

                                        return BarTooltipItem(
                                          'Day ${group.x.toInt()}\n',
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
                                          if (val.toInt() <= 0 || val.toInt() > totalDays) {
                                            return const SizedBox.shrink();
                                          }
                                          if (val.toInt() % 5 == 0 || val.toInt() == 1 || val.toInt() == totalDays) {
                                            return Text('${val.toInt()}', style: const TextStyle(fontSize: 8));
                                          }
                                          return const SizedBox.shrink();
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
                                  barGroups: List.generate(totalDays, (i) {
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

  Widget _buildRowDetail(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
