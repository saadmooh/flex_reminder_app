/// نموذج الاستجابة لقائمة التذكيرات
import 'package:flex_reminder/models/reminder.dart';

class RemindersResponse {
  List<Reminder> reminders;
  List<String> categories;
  List<String> complexities;
  List<String> domains;
  int? total;
  int? currentPage;
  int? lastPage;
  bool success;
  bool hasUpdates;

  RemindersResponse({
    required this.reminders,
    required this.categories,
    required this.complexities,
    required this.domains,
    this.total,
    this.currentPage,
    this.lastPage,
    this.success = true,
    this.hasUpdates = true,
  });

  factory RemindersResponse.fromJson(Map<String, dynamic> json) {
    List<Reminder> remindersList;
    if (json['reminders'] is List) {
      remindersList = (json['reminders'] as List<dynamic>)
          .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (json['reminders'] is Map<String, dynamic>) {
      remindersList = [Reminder.fromJson(json['reminders'])];
    } else {
      remindersList = [];
    }

    List<String> categoriesList = (json['categories'] as List<dynamic>?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty) // Filter out empty strings
            .toList() ??
        [];

    List<String> complexitiesList = (json['complexities'] as List<dynamic>?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty) // Filter out empty strings
            .toList() ??
        [];

    List<String> domainsList = (json['domains'] as List<dynamic>?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty) // Filter out empty strings
            .toList() ??
        []; // Default to empty list if domains is null

    return RemindersResponse(
      reminders: remindersList,
      categories: categoriesList,
      complexities: complexitiesList,
      domains: domainsList,
      total: json['total'] as int?,
      currentPage: json['current_page'] as int?,
      lastPage: json['last_page'] as int?,
      success: json['success'] as bool? ?? true,
      hasUpdates: json['has_updates'] as bool? ?? true,
    );
  }

  /// تحويل كائن RemindersResponse إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'reminders': reminders.map((r) => r.toJson()).toList(),
      'categories': categories,
      'complexities': complexities,
      'domains': domains, // Include domains in JSON
      if (total != null) 'total': total,
      if (currentPage != null) 'current_page': currentPage,
      if (lastPage != null) 'last_page': lastPage,
      'success': success,
      'has_updates': hasUpdates,
    };
  }
}
