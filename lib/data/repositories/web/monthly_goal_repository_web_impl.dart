import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/monthly_goal.dart';
import '../../../domain/repositories/monthly_goal_repository.dart';

class MonthlyGoalRepositoryWebImpl implements MonthlyGoalRepository {
  final SharedPreferences _prefs;
  static const String _key = 'monthly_goals_web';

  MonthlyGoalRepositoryWebImpl(this._prefs);

  Future<List<MonthlyGoal>> _loadGoals() async {
    final data = _prefs.getString(_key);
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((e) => MonthlyGoal.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveGoals(List<MonthlyGoal> goals) async {
    final jsonList = goals.map((e) => e.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(jsonList));
  }

  @override
  Future<MonthlyGoal?> getGoalForMonth(DateTime month) async {
    final goals = await _loadGoals();
    final startOfMonth = DateTime(month.year, month.month, 1);
    try {
      return goals.firstWhere(
          (g) => g.month.year == startOfMonth.year && g.month.month == startOfMonth.month);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveGoal(MonthlyGoal goal) async {
    final goals = await _loadGoals();
    final startOfMonth = DateTime(goal.month.year, goal.month.month, 1);
    final index = goals.indexWhere(
        (g) => g.month.year == startOfMonth.year && g.month.month == startOfMonth.month);

    if (index != -1) {
      goals[index] = goal.copyWith(month: startOfMonth);
    } else {
      final newId = goals.isEmpty
          ? 1
          : (goals.map((g) => g.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
      goals.add(goal.copyWith(id: newId, month: startOfMonth));
    }
    await _saveGoals(goals);
  }
}
