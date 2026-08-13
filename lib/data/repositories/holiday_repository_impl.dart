import 'package:drift/drift.dart';
import '../../domain/entities/holiday.dart' as entity;
import '../../domain/repositories/holiday_repository.dart';
import '../local/database.dart';
import '../local/database_mappers.dart';

class HolidayRepositoryImpl implements HolidayRepository {
  final AppDatabase _db;

  HolidayRepositoryImpl(this._db);

  @override
  Future<List<entity.Holiday>> getHolidays() async {
    final query = _db.select(_db.holidays)..orderBy([(h) => OrderingTerm(expression: h.date)]);
    final schemas = await query.get();
    return schemas.map(DatabaseMappers.mapHoliday).toList();
  }

  @override
  Future<void> saveHoliday(entity.Holiday holiday) async {
    if (holiday.id != null) {
      final companion = HolidaysCompanion(
        id: Value(holiday.id!),
        date: Value(holiday.date),
        name: Value(holiday.name),
      );
      await _db.update(_db.holidays).replace(companion);
    } else {
      final companion = HolidaysCompanion.insert(
        date: holiday.date,
        name: holiday.name,
      );
      await _db.into(_db.holidays).insert(companion);
    }
  }

  @override
  Future<void> deleteHoliday(int id) async {
    await (_db.delete(_db.holidays)..where((h) => h.id.equals(id))).go();
  }
}
