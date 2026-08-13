import 'package:drift/drift.dart';
import '../../domain/entities/monthly_goal.dart' as entity;
import '../../domain/repositories/monthly_goal_repository.dart';
import '../local/database.dart';
import '../local/database_mappers.dart';

class MonthlyGoalRepositoryImpl implements MonthlyGoalRepository {
  final AppDatabase _db;

  MonthlyGoalRepositoryImpl(this._db);

  @override
  Future<entity.MonthlyGoal?> getGoalForMonth(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final query = _db.select(_db.monthlyGoals)..where((m) => m.month.equals(startOfMonth));
    final schema = await query.getSingleOrNull();
    if (schema == null) return null;
    return DatabaseMappers.mapMonthlyGoal(schema);
  }

  @override
  Future<void> saveGoal(entity.MonthlyGoal goal) async {
    final startOfMonth = DateTime(goal.month.year, goal.month.month, 1);
    final query = _db.select(_db.monthlyGoals)..where((m) => m.month.equals(startOfMonth));
    final existing = await query.getSingleOrNull();

    if (existing != null) {
      final companion = MonthlyGoalsCompanion(
        id: Value(existing.id),
        month: Value(startOfMonth),
        targetHours: Value(goal.targetHours),
      );
      await _db.update(_db.monthlyGoals).replace(companion);
    } else {
      final companion = MonthlyGoalsCompanion.insert(
        month: startOfMonth,
        targetHours: goal.targetHours,
      );
      await _db.into(_db.monthlyGoals).insert(companion);
    }
  }
}
