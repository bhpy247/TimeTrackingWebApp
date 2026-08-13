import '../entities/holiday.dart';

abstract class HolidayRepository {
  Future<List<Holiday>> getHolidays();
  Future<void> saveHoliday(Holiday holiday);
  Future<void> deleteHoliday(int id);
}
