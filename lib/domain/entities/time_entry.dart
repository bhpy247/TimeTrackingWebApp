enum WorkType { office, wfh, leave, holiday, halfDay }

class BreakEntry {
  final int? id;
  final int? timeEntryId;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BreakEntry({
    this.id,
    this.timeEntryId,
    required this.startTime,
    this.endTime,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => endTime == null;

  Duration get duration {
    if (endTime == null) {
      return DateTime.now().difference(startTime);
    }
    return endTime!.difference(startTime);
  }

  BreakEntry copyWith({
    int? id,
    int? timeEntryId,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BreakEntry(
      id: id ?? this.id,
      timeEntryId: timeEntryId ?? this.timeEntryId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timeEntryId': timeEntryId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BreakEntry.fromJson(Map<String, dynamic> json) {
    return BreakEntry(
      id: json['id'] as int?,
      timeEntryId: json['timeEntryId'] as int?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class TimeEntry {
  final int? id;
  final DateTime date; // Only date component matters (stored as local midnight)
  final DateTime? startTime;
  final DateTime? endTime;
  final WorkType workType;
  final String? notes;
  final List<BreakEntry> breaks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TimeEntry({
    this.id,
    required this.date,
    this.startTime,
    this.endTime,
    this.workType = WorkType.office,
    this.notes,
    this.breaks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isWorking => startTime != null && endTime == null && !isOnBreak;

  bool get isOnBreak => breaks.isNotEmpty && breaks.last.isActive;

  BreakEntry? get activeBreak => isOnBreak ? breaks.last : null;

  TimeEntry copyWith({
    int? id,
    DateTime? date,
    DateTime? startTime,
    DateTime? endTime,
    WorkType? workType,
    String? notes,
    List<BreakEntry>? breaks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      workType: workType ?? this.workType,
      notes: notes ?? this.notes,
      breaks: breaks ?? this.breaks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'workType': workType.name,
      'notes': notes,
      'breaks': breaks.map((b) => b.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    return TimeEntry(
      id: json['id'] as int?,
      date: DateTime.parse(json['date'] as String),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime'] as String) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      workType: WorkType.values.firstWhere((e) => e.name == json['workType']),
      notes: json['notes'] as String?,
      breaks: (json['breaks'] as List<dynamic>?)
              ?.map((b) => BreakEntry.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
