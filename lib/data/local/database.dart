import 'package:drift/drift.dart';
import '../../domain/entities/time_entry.dart';

// Import conditional connection setup
import 'connection/connection.dart' as impl;

part 'database.g.dart';

@DataClassName('TimeEntrySchema')
class TimeEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get workType => textEnum<WorkType>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('BreakEntrySchema')
class BreakEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get timeEntryId => integer().references(TimeEntries, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('HolidaySchema')
class Holidays extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get name => text()();
}

@DataClassName('MonthlyGoalSchema')
class MonthlyGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get month => dateTime()();
  RealColumn get targetHours => real()();
}

@DriftDatabase(tables: [TimeEntries, BreakEntries, Holidays, MonthlyGoals])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(impl.connect());

  AppDatabase.withExecutor(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        // Enable foreign key support on SQLite native databases
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
