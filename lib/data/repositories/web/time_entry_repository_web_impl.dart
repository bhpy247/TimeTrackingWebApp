import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

class TimeEntryRepositoryWebImpl implements TimeEntryRepository {
  final SharedPreferences _prefs;
  static const String _key = 'time_entries_web';

  TimeEntryRepositoryWebImpl(this._prefs);

  Future<List<TimeEntry>> _loadEntries() async {
    final data = _prefs.getString(_key);
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((e) => TimeEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveEntries(List<TimeEntry> entries) async {
    final jsonList = entries.map((e) => e.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(jsonList));
  }

  @override
  Future<TimeEntry?> getTodayEntry() async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final entries = await _loadEntries();
    try {
      return entries.firstWhere((e) =>
          e.date.year == todayMidnight.year &&
          e.date.month == todayMidnight.month &&
          e.date.day == todayMidnight.day);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TimeEntry?> getEntryById(int id) async {
    final entries = await _loadEntries();
    try {
      return entries.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<TimeEntry>> getEntriesForMonth(DateTime month) async {
    final entries = await _loadEntries();
    return entries
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList();
  }

  @override
  Future<List<TimeEntry>> getAllEntries() async {
    final entries = await _loadEntries();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Future<TimeEntry> clockIn(DateTime time, {WorkType workType = WorkType.office}) async {
    final todayMidnight = DateTime(time.year, time.month, time.day);
    final entries = await _loadEntries();

    final existingIndex = entries.indexWhere((e) =>
        e.date.year == todayMidnight.year &&
        e.date.month == todayMidnight.month &&
        e.date.day == todayMidnight.day);

    if (existingIndex != -1) {
      final existing = entries[existingIndex];
      if (existing.startTime != null) {
        throw StateError("Already clocked in today.");
      }
      final updated = existing.copyWith(
        startTime: time,
        workType: workType,
        updatedAt: DateTime.now(),
      );
      entries[existingIndex] = updated;
      await _saveEntries(entries);
      return updated;
    }

    final newId = entries.isEmpty
        ? 1
        : (entries.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    final newEntry = TimeEntry(
      id: newId,
      date: todayMidnight,
      startTime: time,
      workType: workType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    entries.add(newEntry);
    await _saveEntries(entries);
    return newEntry;
  }

  @override
  Future<TimeEntry> clockOut(DateTime time) async {
    final entries = await _loadEntries();
    final todayMidnight = DateTime(time.year, time.month, time.day);
    final index = entries.indexWhere((e) =>
        e.date.year == todayMidnight.year &&
        e.date.month == todayMidnight.month &&
        e.date.day == todayMidnight.day);

    if (index == -1 || entries[index].startTime == null) {
      throw StateError("Cannot clock out: No active clock-in entry found.");
    }
    final existing = entries[index];
    if (existing.endTime != null) {
      throw StateError("Already clocked out today.");
    }

    var updatedBreaks = List<BreakEntry>.from(existing.breaks);
    if (existing.isOnBreak) {
      final activeBreakIndex = updatedBreaks.indexWhere((b) => b.endTime == null);
      if (activeBreakIndex != -1) {
        updatedBreaks[activeBreakIndex] = updatedBreaks[activeBreakIndex].copyWith(
          endTime: time,
          updatedAt: DateTime.now(),
        );
      }
    }

    final updated = existing.copyWith(
      endTime: time,
      breaks: updatedBreaks,
      updatedAt: DateTime.now(),
    );
    entries[index] = updated;
    await _saveEntries(entries);
    return updated;
  }

  @override
  Future<TimeEntry> startBreak(DateTime time) async {
    final entries = await _loadEntries();
    final todayMidnight = DateTime(time.year, time.month, time.day);
    final index = entries.indexWhere((e) =>
        e.date.year == todayMidnight.year &&
        e.date.month == todayMidnight.month &&
        e.date.day == todayMidnight.day);

    if (index == -1 || entries[index].startTime == null || entries[index].endTime != null) {
      throw StateError("Cannot start break: Must be clocked in and not clocked out.");
    }
    final existing = entries[index];
    if (existing.isOnBreak) {
      throw StateError("Already on break.");
    }

    final newBreakId = existing.breaks.isEmpty
        ? 1
        : (existing.breaks.map((b) => b.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    final newBreak = BreakEntry(
      id: newBreakId,
      timeEntryId: existing.id,
      startTime: time,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final updatedBreaks = List<BreakEntry>.from(existing.breaks)..add(newBreak);
    final updated = existing.copyWith(
      breaks: updatedBreaks,
      updatedAt: DateTime.now(),
    );
    entries[index] = updated;
    await _saveEntries(entries);
    return updated;
  }

  @override
  Future<TimeEntry> endBreak(DateTime time) async {
    final entries = await _loadEntries();
    final todayMidnight = DateTime(time.year, time.month, time.day);
    final index = entries.indexWhere((e) =>
        e.date.year == todayMidnight.year &&
        e.date.month == todayMidnight.month &&
        e.date.day == todayMidnight.day);

    if (index == -1 || !entries[index].isOnBreak) {
      throw StateError("Cannot end break: No active break found.");
    }
    final existing = entries[index];
    final updatedBreaks = List<BreakEntry>.from(existing.breaks);
    final activeBreakIndex = updatedBreaks.indexWhere((b) => b.endTime == null);
    if (activeBreakIndex != -1) {
      updatedBreaks[activeBreakIndex] = updatedBreaks[activeBreakIndex].copyWith(
        endTime: time,
        updatedAt: DateTime.now(),
      );
    }
    final updated = existing.copyWith(
      breaks: updatedBreaks,
      updatedAt: DateTime.now(),
    );
    entries[index] = updated;
    await _saveEntries(entries);
    return updated;
  }

  @override
  Future<void> saveEntry(TimeEntry entry) async {
    final entries = await _loadEntries();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = entry.copyWith(updatedAt: DateTime.now());
    } else {
      final newId = entries.isEmpty
          ? 1
          : (entries.map((e) => e.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
      entries.add(entry.copyWith(id: newId, updatedAt: DateTime.now()));
    }
    await _saveEntries(entries);
  }

  @override
  Future<void> deleteEntry(int id) async {
    final entries = await _loadEntries();
    entries.removeWhere((e) => e.id == id);
    await _saveEntries(entries);
  }
}
