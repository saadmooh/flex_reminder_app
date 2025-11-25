import 'dart:convert';

class SavedPost {
  final int id;
  final int userId;
  final String? url;
  final String title;
  final String? content;
  final String? imageUrl;
  final String? importance;
  final List<String> scheduledTimes;
  final String? nextReminderTime;
  final int isOpened;
  final String? createdAt;
  final String? updatedAt;
  final String? category;
  final String? complexity;
  final String? domain;

  SavedPost({
    required this.id,
    required this.userId,
    this.url,
    required this.title,
    this.content,
    this.imageUrl,
    this.importance,
    required this.scheduledTimes,
    required this.nextReminderTime,
    required this.isOpened,
    this.createdAt,
    this.updatedAt,
    this.category,
    this.complexity,
    this.domain,
  });

  factory SavedPost.fromJson(Map<String, dynamic> json) {
    return SavedPost(
      id: json['id'],
      userId: json['user_id'],
      url: json['url'],
      title: json['title'] ?? '',
      content: json['content'],
      imageUrl: json['image_url'],
      importance: json['importance'],
      scheduledTimes: _parseScheduledTimes(json['scheduled_times']),
      nextReminderTime: json['next_reminder_time'],
      isOpened: json['is_opened'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      category: json['category'],
      complexity: json['complexity'],
      domain: json['domain'],
    );
  }

  static List<String> _parseScheduledTimes(dynamic value) {
    if (value == null) return [];
    if (value is String) {
      try {
        final decoded = jsonDecode(value) as List<dynamic>?;
        return decoded?.map((e) => e.toString()).toList() ?? [];
      } catch (e) {
        return [value.toString()]; // إذا فشل التحليل، اعتبره قيمة مفردة
      }
    }
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [value.toString()]; // حالة فشل أخرى
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'url': url,
      'title': title,
      'content': content,
      'image_url': imageUrl,
      'importance': importance,
      'scheduled_times': jsonEncode(scheduledTimes),
      'next_reminder_time': nextReminderTime,
      'is_opened': isOpened,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'category': category,
      'complexity': complexity,
      'domain': domain,
    };
  }
}
