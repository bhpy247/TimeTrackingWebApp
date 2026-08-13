import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/holiday.dart';
import '../../../domain/repositories/holiday_repository.dart';

class HolidayRepositoryWebImpl implements HolidayRepository {
  final SharedPreferences _prefs;
  static const String _key = 'holidays_web';

  HolidayRepositoryWebImpl(this._prefs);

  Future<List<Holiday>> _loadHolidays() async {
    final data = _prefs.getString(_key);
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((e) => Holiday.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveHolidays(List<Holiday> holidays) async {
    final jsonList = holidays.map((e) => e.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(jsonList));
  }

  @override
  Future<List<Holiday>> getHolidays() async {
    final list = await _loadHolidays();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<void> saveHoliday(Holiday holiday) async {
    final list = await _loadHolidays();
    if (holiday.id != null) {
      final index = list.indexWhere((h) => h.id == holiday.id);
      if (index != -1) {
        list[index] = holiday;
      }
    } else {
      final newId = list.isEmpty
          ? 1
          : (list.map((h) => h.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
      list.add(holiday.copyWith(id: newId));
    }
    await _saveHolidays(list);
  }

  @override
  Future<void> deleteHoliday(int id) async {
    final list = await _loadHolidays();
    list.removeWhere((h) => h.id == id);
    await _saveHolidays(list);
  }
}
