class Holiday {
  final int? id;
  final DateTime date;
  final String name;

  const Holiday({
    this.id,
    required this.date,
    required this.name,
  });

  Holiday copyWith({
    int? id,
    DateTime? date,
    String? name,
  }) {
    return Holiday(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'name': name,
    };
  }

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      id: json['id'] as int?,
      date: DateTime.parse(json['date'] as String),
      name: json['name'] as String,
    );
  }
}
