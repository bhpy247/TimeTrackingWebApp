import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/local/database.dart';
import '../../data/repositories/holiday_repository_impl.dart';
import '../../data/repositories/monthly_goal_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/time_entry_repository_impl.dart';
import '../../data/repositories/web/holiday_repository_web_impl.dart';
import '../../data/repositories/web/monthly_goal_repository_web_impl.dart';
import '../../data/repositories/web/time_entry_repository_web_impl.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/repositories/holiday_repository.dart';
import '../../domain/repositories/monthly_goal_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/time_entry_repository.dart';

// Database & SharedPreferences (SharedPreferences overridden in main.dart)
final databaseProvider = Provider<AppDatabase>((ref) {
  if (kIsWeb) {
    throw UnsupportedError('Database should not be accessed on Web platform.');
  }
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences was not initialized in ProviderScope overrides');
});

// Repository Providers
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsRepositoryImpl(prefs);
});

final timeEntryRepositoryProvider = Provider<TimeEntryRepository>((ref) {
  if (kIsWeb) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return TimeEntryRepositoryWebImpl(prefs);
  } else {
    final db = ref.watch(databaseProvider);
    return TimeEntryRepositoryImpl(db);
  }
});

final monthlyGoalRepositoryProvider = Provider<MonthlyGoalRepository>((ref) {
  if (kIsWeb) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return MonthlyGoalRepositoryWebImpl(prefs);
  } else {
    final db = ref.watch(databaseProvider);
    return MonthlyGoalRepositoryImpl(db);
  }
});

final holidayRepositoryProvider = Provider<HolidayRepository>((ref) {
  if (kIsWeb) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return HolidayRepositoryWebImpl(prefs);
  } else {
    final db = ref.watch(databaseProvider);
    return HolidayRepositoryImpl(db);
  }
});

// Settings Notifier Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, UserSettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return SettingsNotifier(repo);
});

class SettingsNotifier extends StateNotifier<UserSettings> {
  final SettingsRepository _repository;

  SettingsNotifier(this._repository) : super(_repository.getSettings());

  Future<void> updateSettings(UserSettings settings) async {
    await _repository.saveSettings(settings);
    state = settings;
  }
}

// Today's Time Entry Notifier Provider
final todayTimeEntryProvider = StateNotifierProvider<TimeTrackingNotifier, AsyncValue<TimeEntry?>>((ref) {
  final repo = ref.watch(timeEntryRepositoryProvider);
  return TimeTrackingNotifier(repo);
});

class TimeTrackingNotifier extends StateNotifier<AsyncValue<TimeEntry?>> {
  final TimeEntryRepository _repository;

  TimeTrackingNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadTodayEntry();
  }

  Future<void> loadTodayEntry() async {
    try {
      final entry = await _repository.getTodayEntry();
      state = AsyncValue.data(entry);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> clockIn({WorkType workType = WorkType.office}) async {
    try {
      state = const AsyncValue.loading();
      final entry = await _repository.clockIn(DateTime.now(), workType: workType);
      state = AsyncValue.data(entry);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      // Reload to restore previous state if clock in fails
      loadTodayEntry();
    }
  }

  Future<void> clockOut() async {
    try {
      state = const AsyncValue.loading();
      final entry = await _repository.clockOut(DateTime.now());
      state = AsyncValue.data(entry);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      loadTodayEntry();
    }
  }

  Future<void> startBreak() async {
    try {
      state = const AsyncValue.loading();
      final entry = await _repository.startBreak(DateTime.now());
      state = AsyncValue.data(entry);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      loadTodayEntry();
    }
  }

  Future<void> endBreak() async {
    try {
      state = const AsyncValue.loading();
      final entry = await _repository.endBreak(DateTime.now());
      state = AsyncValue.data(entry);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      loadTodayEntry();
    }
  }

  Future<void> updateNotes(String notes) async {
    final current = state.value;
    if (current == null) return;
    try {
      final updated = current.copyWith(notes: notes);
      await _repository.saveEntry(updated);
      state = AsyncValue.data(updated);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      loadTodayEntry();
    }
  }
}

// Provider for fetching current month's entries to update monthly summary
final currentMonthEntriesProvider = FutureProvider<List<TimeEntry>>((ref) {
  final repo = ref.watch(timeEntryRepositoryProvider);
  ref.watch(todayTimeEntryProvider); // Triggers recalculation on clock in/out
  return repo.getEntriesForMonth(DateTime.now());
});

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final monthlyCalendarEntriesProvider = FutureProvider.family<List<TimeEntry>, DateTime>((ref, month) {
  final repo = ref.watch(timeEntryRepositoryProvider);
  ref.watch(todayTimeEntryProvider); // Automatically reload when today's entry changes
  return repo.getEntriesForMonth(month);
});
