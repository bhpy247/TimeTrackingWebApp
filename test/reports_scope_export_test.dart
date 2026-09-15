import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetracking/domain/entities/time_entry.dart';
import 'package:timetracking/domain/repositories/time_entry_repository.dart';
import 'package:timetracking/presentation/providers/providers.dart';
import 'package:timetracking/presentation/screens/reports_screen.dart';

class FakeTimeEntryRepository implements TimeEntryRepository {
  final List<TimeEntry> entries;

  FakeTimeEntryRepository(this.entries);

  @override
  Future<TimeEntry?> getTodayEntry() async => null;

  @override
  Future<TimeEntry?> getEntryById(int id) async => null;

  @override
  Future<List<TimeEntry>> getEntriesForMonth(DateTime month) async {
    return entries
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList();
  }

  @override
  Future<List<TimeEntry>> getAllEntries() async => entries;

  @override
  Future<TimeEntry> clockIn(DateTime time, {WorkType workType = WorkType.office}) =>
      throw UnimplementedError();

  @override
  Future<TimeEntry> clockOut(DateTime time) => throw UnimplementedError();

  @override
  Future<TimeEntry> startBreak(DateTime time) => throw UnimplementedError();

  @override
  Future<TimeEntry> endBreak(DateTime time) => throw UnimplementedError();

  @override
  Future<void> saveEntry(TimeEntry entry) async {}

  @override
  Future<void> deleteEntry(int id) async {}
}

void main() {
  testWidgets('ReportsScreen switches to All Records and shows all 11 entries',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();

    // 1 entry in current month
    final currentMonthEntry = TimeEntry(
      id: 1,
      date: DateTime(now.year, now.month, 1),
      startTime: DateTime(now.year, now.month, 1, 9, 0),
      endTime: DateTime(now.year, now.month, 1, 17, 0),
      workType: WorkType.office,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 10 entries in previous month
    final prevMonthEntries = List.generate(10, (i) {
      final day = i + 1;
      return TimeEntry(
        id: i + 2,
        date: DateTime(now.year, now.month - 1, day),
        startTime: DateTime(now.year, now.month - 1, day, 9, 0),
        endTime: DateTime(now.year, now.month - 1, day, 17, 0),
        workType: WorkType.office,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    final allEntries = [currentMonthEntry, ...prevMonthEntries];
    expect(allEntries.length, 11);

    final fakeRepo = FakeTimeEntryRepository(allEntries);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          timeEntryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const MaterialApp(
          home: ReportsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // In Monthly mode (default), only 1 entry for the current month is visible
    expect(find.text('Export PDF (1)'), findsOneWidget);
    expect(find.text('Export CSV (1)'), findsOneWidget);
    expect(find.text('ACTIVITY LOG (1 RECORDS)'), findsOneWidget);

    // Switch to All Records mode
    final allRecordsSegment = find.text('All Records');
    expect(allRecordsSegment, findsOneWidget);
    await tester.tap(allRecordsSegment);
    await tester.pumpAndSettle();

    // Now all 11 records are visible and ready for export
    expect(find.text('Export PDF (11)'), findsOneWidget);
    expect(find.text('Export CSV (11)'), findsOneWidget);
    expect(find.text('ACTIVITY LOG (11 RECORDS)'), findsOneWidget);
  });
}
