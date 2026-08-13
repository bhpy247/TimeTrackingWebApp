import '../entities/monthly_goal.dart';

abstract class MonthlyGoalRepository {
  Future<MonthlyGoal?> getGoalForMonth(DateTime month);
  Future<void> saveGoal(MonthlyGoal goal);
}
