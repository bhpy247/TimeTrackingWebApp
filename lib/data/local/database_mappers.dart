import '../../domain/entities/time_entry.dart' as entity;
import '../../domain/entities/holiday.dart' as entity;
import '../../domain/entities/monthly_goal.dart' as entity;
import 'database.dart';

class DatabaseMappers {
  DatabaseMappers._();

  static entity.BreakEntry mapBreakEntry(BreakEntrySchema schema) {
    return entity.BreakEntry(
      id: schema.id,
      timeEntryId: schema.timeEntryId,
      startTime: schema.startTime,
      endTime: schema.endTime,
      createdAt: schema.createdAt,
      updatedAt: schema.updatedAt,
    );
  }

  static entity.TimeEntry mapTimeEntry(TimeEntrySchema schema, List<BreakEntrySchema> breakSchemas) {
    return entity.TimeEntry(
      id: schema.id,
      date: schema.date,
      startTime: schema.startTime,
      endTime: schema.endTime,
      workType: schema.workType,
      notes: schema.notes,
      breaks: breakSchemas.map(mapBreakEntry).toList(),
      createdAt: schema.createdAt,
      updatedAt: schema.updatedAt,
    );
  }

  static entity.Holiday mapHoliday(HolidaySchema schema) {
    return entity.Holiday(
      id: schema.id,
      date: schema.date,
      name: schema.name,
    );
  }

  static entity.MonthlyGoal mapMonthlyGoal(MonthlyGoalSchema schema) {
    return entity.MonthlyGoal(
      id: schema.id,
      month: schema.month,
      targetHours: schema.targetHours,
    );
  }
}
