import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/time_calculator.dart';

class ReportService {
  ReportService._();

  static Future<Uint8List> generateCSV(
    List<TimeEntry> entries, {
    String? title,
  }) async {
    final sortedEntries = List<TimeEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));

    final List<List<dynamic>> rows = [];
    
    // Optional Title header
    if (title != null && title.isNotEmpty) {
      rows.add([title]);
      rows.add([]);
    }

    // Header
    rows.add([
      'Date',
      'Work Type',
      'Start Time',
      'End Time',
      'Breaks (mins)',
      'Working Hours (dec)',
      'Working Hours (formatted)',
      'Notes'
    ]);

    for (final entry in sortedEntries) {
      final working = TimeCalculator.calculateWorkingDuration(entry);
      final breaksDuration = TimeCalculator.calculateBreakDuration(entry);
      
      final dateStr = DateFormat('yyyy-MM-dd').format(entry.date);
      final startTimeStr = entry.startTime != null ? DateFormat('HH:mm').format(entry.startTime!) : '';
      final endTimeStr = entry.endTime != null ? DateFormat('HH:mm').format(entry.endTime!) : '';
      
      final workingHoursDec = working.inMinutes / 60.0;
      final workingHoursFormatted = '${working.inHours}h ${working.inMinutes % 60}m';

      rows.add([
        dateStr,
        entry.workType.name.toUpperCase(),
        startTimeStr,
        endTimeStr,
        breaksDuration.inMinutes,
        workingHoursDec.toStringAsFixed(2),
        workingHoursFormatted,
        entry.notes ?? '',
      ]);
    }

    final csvString = Csv().encode(rows);
    return Uint8List.fromList(csvString.codeUnits);
  }

  static Future<Uint8List> generatePDF(
    List<TimeEntry> entries,
    DateTime? month,
    UserSettings settings, {
    String? title,
    String? periodLabel,
  }) async {
    final pdf = pw.Document();

    final sortedEntries = List<TimeEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    
    final effectiveTitle = title ?? (month != null ? 'Monthly Time Tracking Report' : 'Time Tracking Report');
    final effectivePeriod = periodLabel ?? (month != null ? DateFormat('MMMM yyyy').format(month) : 'All Records (${sortedEntries.length} entries)');
    
    final totalDuration = TimeCalculator.calculateMonthlyTotal(sortedEntries);
    final averageDuration = TimeCalculator.calculateMonthlyAverage(sortedEntries);

    int presentCount = 0;
    int wfhCount = 0;
    int leaveCount = 0;
    int holidayCount = 0;

    for (final entry in sortedEntries) {
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
    }

    final workingDaysCount = presentCount + wfhCount;
    final totalHoursStr = '${totalDuration.inHours}h ${totalDuration.inMinutes % 60}m';
    final averageHoursStr = '${averageDuration.inHours}h ${averageDuration.inMinutes % 60}m';

    // Load Unicode fonts (Roboto) to support all currency symbols and Unicode characters offline & online
    pw.Font? ttfRegular;
    pw.Font? ttfBold;
    try {
      final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      ttfRegular = pw.Font.ttf(regularData);
      ttfBold = pw.Font.ttf(boldData);
    } catch (_) {
      try {
        ttfRegular = await PdfGoogleFonts.robotoRegular();
        ttfBold = await PdfGoogleFonts.robotoBold();
      } catch (_) {
        // Fallback if font network and assets are unavailable
      }
    }

    final pageTheme = (ttfRegular != null && ttfBold != null)
        ? pw.ThemeData.withFont(
            base: ttfRegular,
            bold: ttfBold,
          )
        : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pageTheme,
        build: (pw.Context context) {
          return [
            // Title Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(effectiveTitle, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(effectivePeriod, style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Summary Section
            pw.Text('SUMMARY STATISTICS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfStatCard('Total Hours', totalHoursStr),
                _buildPdfStatCard('Daily Avg', averageHoursStr),
                _buildPdfStatCard('Days Worked', '$workingDaysCount days'),
                _buildPdfStatCard('WFH Days', '$wfhCount days'),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfStatCard('Leave Days', '$leaveCount days'),
                _buildPdfStatCard('Holidays', '$holidayCount days'),
                _buildPdfStatCard('Expected / Day', '${settings.expectedWorkingHours}h'),
                _buildPdfStatCard('Total Expected', '${settings.expectedWorkingHours * workingDaysCount}h'),
              ],
            ),
            pw.SizedBox(height: 24),

            // Daily Logs Table
            pw.Text('DAILY ACTIVITY LOG (${sortedEntries.length} RECORDS)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 8),
            if (sortedEntries.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                alignment: pw.Alignment.center,
                child: pw.Text('No time entries found for this report period.', style: const pw.TextStyle(color: PdfColors.grey600)),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Type', 'Clock In', 'Clock Out', 'Breaks', 'Net Duration', 'Notes'],
                data: sortedEntries.map((entry) {
                  final dateStr = DateFormat('MMM d, yyyy (EEE)').format(entry.date);
                  final typeStr = entry.workType.name.toUpperCase();
                  final startStr = entry.startTime != null ? DateFormat('hh:mm a').format(entry.startTime!) : '--:--';
                  final endStr = entry.endTime != null ? DateFormat('hh:mm a').format(entry.endTime!) : '--:--';
                  
                  final breaksDuration = TimeCalculator.calculateBreakDuration(entry);
                  final netDuration = TimeCalculator.calculateWorkingDuration(entry);

                  final breakStr = breaksDuration > Duration.zero ? '${breaksDuration.inMinutes}m' : '-';
                  final netStr = netDuration > Duration.zero ? '${netDuration.inHours}h ${netDuration.inMinutes % 60}m' : '-';

                  return [
                    dateStr,
                    typeStr,
                    startStr,
                    endStr,
                    breakStr,
                    netStr,
                    entry.notes ?? '',
                  ];
                }).toList(),
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfStatCard(String label, String value) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
        ],
      ),
    );
  }
}
