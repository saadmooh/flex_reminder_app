import 'dart:convert';

class Reminder {
  final int id;
  final int userId;
  final String? url;
  final String title;
  final String? content;
  final String? imageUrl;
  String? importance;
  final List<String> scheduledTimes;
  String? nextReminderTime;
  final int isOpened;
  final String? createdAt;
  final String? updatedAt;
  final String? category;
  final String? complexity;
  final String? domain;

  Reminder({
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

  Reminder copyWith({
    int? id,
    int? userId,
    String? title,
    String? content,
    String? url,
    String? importance,
    List<String>? scheduledTimes,
    String? nextReminderTime,
    String? category,
    String? complexity,
    String? domain,
    String? imageUrl,
    String? createdAt,
    String? updatedAt,
    int? isOpened,
  }) {
    return Reminder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      url: url ?? this.url,
      importance: importance ?? this.importance,
      scheduledTimes: scheduledTimes ?? this.scheduledTimes,
      nextReminderTime: nextReminderTime ?? this.nextReminderTime,
      category: category ?? this.category,
      complexity: complexity ?? this.complexity,
      domain: domain ?? this.domain,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOpened: isOpened ?? this.isOpened,
    );
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    try {
      int parseInt(dynamic value) {
        if (value == null) return 0;
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? 0;
        return 0;
      }

      String? parseString(dynamic value) {
        if (value == null) return null;
        return value.toString().trim();
      }

      List<String> parseScheduledTimes(dynamic value) {
        if (value == null) return [];
        if (value is String) {
          try {
            final List<dynamic> parsed = jsonDecode(value) as List<dynamic>? ?? [];
            return parsed.map((e) => e.toString().trim()).toList();
          } catch (e) {
            print('Error parsing scheduled_times: $e');
            return [value.toString().trim()];
          }
        }
        if (value is List) {
          return value.map((e) => e.toString().trim()).toList();
        }
        return [value.toString().trim()];
      }

      return Reminder(
        id: parseInt(json['id']),
        userId: parseInt(json['user_id']),
        url: parseString(json['url']),
        title: parseString(json['title']) ?? '',
        content: parseString(json['content']),
        imageUrl: parseString(json['image_url']),
        importance: parseString(json['importance']),
        scheduledTimes: parseScheduledTimes(json['scheduled_times']),
        nextReminderTime: parseString(json['next_reminder_time']),
        isOpened: parseInt(json['is_opened']),
        createdAt: parseString(json['created_at']),
        updatedAt: parseString(json['updated_at']),
        category: parseString(json['category']),
        complexity: parseString(json['complexity']),
        domain: parseString(json['domain']),
      );
    } catch (e) {
      print('Error parsing Reminder: $e');
      print('Problematic JSON: $json');
      rethrow;
    }
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