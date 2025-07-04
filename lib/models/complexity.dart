class Complexity {
  final int? id;
  final String? level;

  Complexity({this.id, this.level});

  factory Complexity.fromJson(Map<String, dynamic> json) {
    return Complexity(
      id: json['id'] as int?,
      level: json['level'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'level': level,
    };
  }
}
