import 'package:flutter/material.dart';

class UserFreeTime {
  final int? id; // Make id nullable
  final int? userId; // Add userId if your API supports it
  final String day;
  final String startTime;
  final String endTime;
  final bool isOffDay;

  UserFreeTime({
    this.id, // Allow null for new entries
    this.userId,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.isOffDay,
  });

  factory UserFreeTime.fromJson(Map<String, dynamic> json) {
    return UserFreeTime(
      id: json['id'],
      userId: json['user_id'], // Parse userId if available
      day: json['day'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      isOffDay: json['is_off_day'] == true, // Assuming 1 for true, 0 for false
    );
  }

  // Helper method to convert TimeOfDay to formatted string
  static String stringFromTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // Helper method to create TimeOfDay from formatted string HH:mm
  static TimeOfDay? timeOfDayFromString(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) {
      return null; // Invalid format
    }
    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null; // Parsing error
    }
  }
}
