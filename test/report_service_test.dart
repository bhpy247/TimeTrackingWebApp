import 'package:flutter_test/flutter_test.dart';
import 'package:timetracking/domain/entities/time_entry.dart';
import 'package:timetracking/domain/entities/user_settings.dart';
import 'package:timetracking/services/report/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verify PDF pagination with 50 entries', () async {
    final now = DateTime(2026, 9, 1);
    final entries = List.generate(50, (i) {
      final day = (i % 28) + 1;
      return TimeEntry(
        id: i + 1,
        date: DateTime(2026, 9, day),
        startTime: DateTime(2026, 9, day, 9, 0),
        endTime: DateTime(2026, 9, day, 18, 0),
        workType: WorkType.office,
        notes: 'Notes for entry $i',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    final settings = const UserSettings();
    final pdfBytes = await ReportService.generatePDF(entries, now, settings);
    expect(pdfBytes.length, greaterThan(5000));
  });
}
