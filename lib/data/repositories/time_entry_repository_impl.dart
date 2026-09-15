import 'package:drift/drift.dart';
import '../../domain/entities/time_entry.dart' as entity;
import '../../domain/repositories/time_entry_repository.dart';
import '../local/database.dart';
import '../local/database_mappers.dart';

class TimeEntryRepositoryImpl implements TimeEntryRepository {
  final AppDatabase _db;

  TimeEntryRepositoryImpl(this._db);

  @override
  Future<entity.TimeEntry?> getTodayEntry() async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    
    final query = _db.select(_db.timeEntries)..where((t) => t.date.equals(todayMidnight));
    final schema = await query.getSingleOrNull();
    if (schema == null) return null;

    final breakQuery = _db.select(_db.breakEntries)..where((b) => b.timeEntryId.equals(schema.id));
    final breakSchemas = await breakQuery.get();

    return DatabaseMappers.mapTimeEntry(schema, breakSchemas);
  }

  @override
  Future<entity.TimeEntry?> getEntryById(int id) async {
    final query = _db.select(_db.timeEntries)..where((t) => t.id.equals(id));
    final schema = await query.getSingleOrNull();
    if (schema == null) return null;

    final breakQuery = _db.select(_db.breakEntries)..where((b) => b.timeEntryId.equals(schema.id));
    final breakSchemas = await breakQuery.get();

    return DatabaseMappers.mapTimeEntry(schema, breakSchemas);
  }

  @override
  Future<List<entity.TimeEntry>> getEntriesForMonth(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 1).subtract(const Duration(seconds: 1));

    final query = _db.select(_db.timeEntries)
      ..where((t) => t.date.isBetweenValues(startOfMonth, endOfMonth))
      ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    
    final schemas = await query.get();
    
    final List<entity.TimeEntry> results = [];
    for (final schema in schemas) {
      final breakQuery = _db.select(_db.breakEntries)..where((b) => b.timeEntryId.equals(schema.id));
      final breakSchemas = await breakQuery.get();
      results.add(DatabaseMappers.mapTimeEntry(schema, breakSchemas));
    }
    return results;
  }

  @override
  Future<List<entity.TimeEntry>> getAllEntries() async {
    final query = _db.select(_db.timeEntries)
      ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    final schemas = await query.get();
    final List<entity.TimeEntry> results = [];
    for (final schema in schemas) {
      final breakQuery = _db.select(_db.breakEntries)..where((b) => b.timeEntryId.equals(schema.id));
      final breakSchemas = await breakQuery.get();
      results.add(DatabaseMappers.mapTimeEntry(schema, breakSchemas));
    }
    return results;
  }

  @override
  Future<entity.TimeEntry> clockIn(DateTime time, {entity.WorkType workType = entity.WorkType.office}) async {
    final todayMidnight = DateTime(time.year, time.month, time.day);
    
    final existing = await getTodayEntry();
    if (existing != null) {
      if (existing.startTime != null) {
        throw StateError("Already clocked in today.");
      }
      
      final updatedSchema = TimeEntriesCompanion(
        startTime: Value(time),
        workType: Value(workType),
        updatedAt: Value(DateTime.now()),
      );
      await (_db.update(_db.timeEntries)..where((t) => t.id.equals(existing.id!))).write(updatedSchema);
      return (await getTodayEntry())!;
    }

    final companion = TimeEntriesCompanion.insert(
      date: todayMidnight,
      startTime: Value(time),
      workType: workType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final id = await _db.into(_db.timeEntries).insert(companion);
    return (await getEntryById(id))!;
  }

  @override
  Future<entity.TimeEntry> clockOut(DateTime time) async {
    final existing = await getTodayEntry();
    if (existing == null || existing.startTime == null) {
      throw StateError("Cannot clock out: No active clock-in entry found.");
    }
    if (existing.endTime != null) {
      throw StateError("Already clocked out today.");
    }

    if (existing.isOnBreak) {
      await endBreak(time);
    }

    final updatedSchema = TimeEntriesCompanion(
      endTime: Value(time),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.timeEntries)..where((t) => t.id.equals(existing.id!))).write(updatedSchema);
    return (await getTodayEntry())!;
  }

  @override
  Future<entity.TimeEntry> startBreak(DateTime time) async {
    final existing = await getTodayEntry();
    if (existing == null || existing.startTime == null || existing.endTime != null) {
      throw StateError("Cannot start break: Must be clocked in and not clocked out.");
    }
    if (existing.isOnBreak) {
      throw StateError("Already on break.");
    }

    final companion = BreakEntriesCompanion.insert(
      timeEntryId: existing.id!,
      startTime: time,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.into(_db.breakEntries).insert(companion);
    return (await getTodayEntry())!;
  }

  @override
  Future<entity.TimeEntry> endBreak(DateTime time) async {
    final existing = await getTodayEntry();
    if (existing == null || !existing.isOnBreak) {
      throw StateError("Cannot end break: No active break found.");
    }

    final activeBreak = existing.activeBreak!;
    final updatedBreakCompanion = BreakEntriesCompanion(
      endTime: Value(time),
      updatedAt: Value(DateTime.now()),
    );

    await (_db.update(_db.breakEntries)..where((b) => b.id.equals(activeBreak.id!))).write(updatedBreakCompanion);
    return (await getTodayEntry())!;
  }

  @override
  Future<void> saveEntry(entity.TimeEntry entry) async {
    await _db.transaction(() async {
      int entryId;
      if (entry.id == null) {
        final companion = TimeEntriesCompanion.insert(
          date: entry.date,
          startTime: Value(entry.startTime),
          endTime: Value(entry.endTime),
          workType: entry.workType,
          notes: Value(entry.notes),
          createdAt: entry.createdAt,
          updatedAt: DateTime.now(),
        );
        entryId = await _db.into(_db.timeEntries).insert(companion);
      } else {
        entryId = entry.id!;
        final companion = TimeEntriesCompanion(
          id: Value(entry.id!),
          date: Value(entry.date),
          startTime: Value(entry.startTime),
          endTime: Value(entry.endTime),
          workType: Value(entry.workType),
          notes: Value(entry.notes),
          createdAt: Value(entry.createdAt),
          updatedAt: Value(DateTime.now()),
        );
        await _db.update(_db.timeEntries).replace(companion);
      }

      await (_db.delete(_db.breakEntries)..where((b) => b.timeEntryId.equals(entryId))).go();

      for (final b in entry.breaks) {
        final breakCompanion = BreakEntriesCompanion.insert(
          timeEntryId: entryId,
          startTime: b.startTime,
          endTime: Value(b.endTime),
          createdAt: b.createdAt,
          updatedAt: DateTime.now(),
        );
        await _db.into(_db.breakEntries).insert(breakCompanion);
      }
    });
  }

  @override
  Future<void> deleteEntry(int id) async {
    await (_db.delete(_db.timeEntries)..where((t) => t.id.equals(id))).go();
  }
}
