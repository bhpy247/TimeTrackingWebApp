import '../entities/time_entry.dart';

abstract class TimeEntryRepository {
  Future<TimeEntry?> getTodayEntry();
  Future<TimeEntry?> getEntryById(int id);
  Future<List<TimeEntry>> getEntriesForMonth(DateTime month);
  Future<List<TimeEntry>> getAllEntries();
  Future<TimeEntry> clockIn(DateTime time, {WorkType workType = WorkType.office});
  Future<TimeEntry> clockOut(DateTime time);
  Future<TimeEntry> startBreak(DateTime time);
  Future<TimeEntry> endBreak(DateTime time);
  Future<void> saveEntry(TimeEntry entry);
  Future<void> deleteEntry(int id);
}
