import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/entities/time_entry.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/time_calculator.dart';

class ReportService {
  ReportService._();

  static Future<Uint8List> generateCSV(List<TimeEntry> entries) async {
    final List<List<dynamic>> rows = [];
    
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

    for (final entry in entries) {
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
    DateTime month,
    UserSettings settings,
  ) async {
    final pdf = pw.Document();
    
    final monthName = DateFormat('MMMM yyyy').format(month);
    final totalDuration = TimeCalculator.calculateMonthlyTotal(entries);
    final averageDuration = TimeCalculator.calculateMonthlyAverage(entries);

    int presentCount = 0;
    int wfhCount = 0;
    int leaveCount = 0;
    int holidayCount = 0;

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
    }

    final workingDaysCount = presentCount + wfhCount;
    final totalHoursStr = '${totalDuration.inHours}h ${totalDuration.inMinutes % 60}m';
    final averageHoursStr = '${averageDuration.inHours}h ${averageDuration.inMinutes % 60}m';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Title
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Monthly Time Tracking Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text(monthName, style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700)),
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
                _buildPdfStatCard('Expected Month', '${settings.expectedWorkingHours * workingDaysCount}h'),
              ],
            ),
            pw.SizedBox(height: 24),

            // Daily Logs Table
            pw.Text('DAILY ACTIVITY LOG', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Type', 'Clock In', 'Clock Out', 'Breaks', 'Net Duration', 'Notes'],
              data: entries.map((entry) {
                final dateStr = DateFormat('MMM d (EEE)').format(entry.date);
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
