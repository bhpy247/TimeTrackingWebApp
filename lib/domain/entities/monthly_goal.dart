class MonthlyGoal {
  final int? id;
  final DateTime month; // Store as first day of month (e.g. 2026-08-01)
  final double targetHours;

  const MonthlyGoal({
    this.id,
    required this.month,
    required this.targetHours,
  });

  MonthlyGoal copyWith({
    int? id,
    DateTime? month,
    double? targetHours,
  }) {
    return MonthlyGoal(
      id: id ?? this.id,
      month: month ?? this.month,
      targetHours: targetHours ?? this.targetHours,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'month': month.toIso8601String(),
      'targetHours': targetHours,
    };
  }

  factory MonthlyGoal.fromJson(Map<String, dynamic> json) {
    return MonthlyGoal(
      id: json['id'] as int?,
      month: DateTime.parse(json['month'] as String),
      targetHours: (json['targetHours'] as num).toDouble(),
    );
  }
}
