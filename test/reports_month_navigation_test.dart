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
  testWidgets('ReportsScreen displays calculations when navigating to previous month',
      (WidgetTester tester) async {
    // Set a large screen size to ensure all cards in ListView are rendered
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final prevMonthDate = DateTime(now.year, now.month - 1, 15);

    // Create an entry in the previous month (9.5 hours)
    final prevMonthEntry = TimeEntry(
      id: 1,
      date: DateTime(prevMonthDate.year, prevMonthDate.month, prevMonthDate.day),
      startTime: DateTime(prevMonthDate.year, prevMonthDate.month, prevMonthDate.day, 10, 0),
      endTime: DateTime(prevMonthDate.year, prevMonthDate.month, prevMonthDate.day, 19, 30),
      workType: WorkType.office,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final fakeRepo = FakeTimeEntryRepository([prevMonthEntry]);

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

    // Initial render: current month (has 0 entries)
    await tester.pumpAndSettle();
    expect(find.text('No time entries for this month.'), findsOneWidget);
    expect(find.text('Days worked'), findsOneWidget);
    expect(find.text('0h 0m'), findsWidgets); // Total hours worked for current month is 0

    // Tap previous month button (chevron_left)
    final prevButton = find.byIcon(Icons.chevron_left);
    expect(prevButton, findsOneWidget);
    await tester.tap(prevButton);
    await tester.pumpAndSettle();

    // Now previous month should show calculations for the previous month's entry
    expect(find.text('No time entries for this month.'), findsNothing);
    expect(find.text('9h 30m'), findsWidgets); // Total Hours Worked: 9h 30m
    expect(find.text('1'), findsWidgets); // 1 day worked, 1 office day
  });
}
