// lib/services/api_functions/reminder_service.dart

import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
//import '../utils_service.dart'; // استيراد UtilsService
import 'exceptions.dart'; // للاطلاق الاستثناء
import 'utils_service.dart';

class ReminderService {
  final UtilsService _utilsService;

  ReminderService(this._utilsService);

  Future<List<int>> getRemindersIds() async {
    final response = await _utilsService.request('GET', 'getRemindersIds');
    
    // UtilsService تتعامل مع أخطاء الاشتراك، لذا نحتاج فقط للتحقق من نجاح الطلب
    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data is List<dynamic>) {
        return data.map((id) => id as int).toList();
      }
    }
    
    // إذا لم يكن 200 أو لم تكن قائمة، فهناك خطأ ما
    throw Exception(response['data']['message'] ?? 'Failed to fetch reminder IDs');
  }

  Future<RemindersResponse> fetchReminders({
    int page = 1,
    int perPage = 4,
    String searchQuery = '',
    String? category,
    String? complexity,
    String? domain,
    bool forceFetch = false,
    List<int> excludeIds = const [],
  }) async {
    final queryParams = {
      'page': page.toString(),
      'perPage': perPage.toString(),
      if (searchQuery.isNotEmpty) 'search': searchQuery,
      if (category != null && category != 'All') 'category': category,
      if (complexity != null && complexity != 'All') 'complexity': complexity,
      if (domain != null && domain != 'All') 'domain': domain,
      if (forceFetch) 'forceFetch': 'true',
      if (excludeIds.isNotEmpty) 'ids': excludeIds.join(','),
    };

    final response = await _utilsService.request('GET', 'reminders', data: queryParams);
    
    if (response['statusCode'] == 200) {
      return RemindersResponse.fromJson(response['data']);
    } else if (response['statusCode'] == 401) {
      throw Exception('Unauthorized. Please log in again.');
    } else {
      throw Exception('Failed to load reminders: ${response['statusCode']}');
    }
  }

  Future<void> deleteReminder(int id) async {
    final response = await _utilsService.request('GET', 'deleteReminder/$id');
    
    // الطلب ناجح إذا كان الكود 200
    if (response['statusCode'] != 200) {
      throw Exception(response['data']['message'] ?? 'Failed to delete reminder.');
    }
    // لا حاجة لإرجاع قيمة في حالة النجاح
  }

  Future<Reminder> getReminder(String postUrl) async {
    final response = await _utilsService.request('GET', 'reminder', data: {'url': postUrl});
    
    if (response['statusCode'] == 200) {
      return Reminder.fromJson(response['data']);
    } else if (response['statusCode'] == 404) {
      throw Exception('Reminder not found');
    } else {
      throw Exception('Failed to load reminder: ${response['statusCode']}');
    }
  }

  Future<Reminder> getReminderById(int postId) async {
    final response = await _utilsService.request('GET', 'reminderById', data: {'id': postId.toString()});
    
    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data['reminder'] != null) {
        return Reminder.fromJson(data['reminder']);
      } else {
        throw Exception('No reminder data found in response');
      }
    } else if (response['statusCode'] == 404) {
      throw Exception('Reminder not found');
    } else {
      throw Exception('Failed to load reminder: ${response['statusCode']}');
    }
  }

  Future<Map<String, dynamic>> reschedulePost(
      String postUrl, String importance) async {
    
    final Map<String, Map<String, String>> importanceOptions = {
      'day': {'en': 'Day', 'ar': 'يوم'},
      'week': {'en': 'Week', 'ar': 'أسبوع'},
      'month': {'en': 'Month', 'ar': 'شهر'},
    };

    final importanceData =
        importanceOptions[importance] ?? {'en': 'Day', 'ar': 'يوم'};

    final requestBody = {
      'url': postUrl,
      'importance': importanceData['en'],
      'importance_ar': importanceData['ar'],
    };

    final response = await _utilsService.request('POST', 'reschedule-post', data: requestBody);
    
    if (response['statusCode'] == 200 || response['statusCode'] == 201) {
      return response['data'];
    } else {
      throw Exception(response['data']['message'] ?? 'Failed to reschedule post.');
    }
  }

  Future<Map<String, dynamic>> updateReminder(Reminder reminder) async {
    final requestBody = {
      'id': reminder.id,
      'next_reminder_time': reminder.nextReminderTime,
      'title': reminder.title,
      'content': reminder.content,
      'importance': reminder.importance,
    };

    final response = await _utilsService.request('POST', 'update-reminder', data: requestBody);
    
    if (response['statusCode'] == 200) {
      return response['data'];
    } else {
      throw Exception(response['data']['message'] ?? 'Failed to update reminder.');
    }
  }

  Future<Map<String, dynamic>> savePost(Map<String, dynamic> data) async {
    final DateTime now = DateTime.now();
    final Duration offset = now.timeZoneOffset;

    final int hours = offset.inHours;
    final int minutes = offset.inMinutes.remainder(60);

    final String formattedTimezone =
        '${hours >= 0 ? '+' : ''}${hours.toString().padLeft(2, '0')}:${minutes.abs().toString().padLeft(2, '0')}';

    data['timezone_offset'] = formattedTimezone;
    data['timezone_name'] = now.timeZoneName;

    final response = await _utilsService.request('POST', 'save-post', data: data);
    
    // UtilsService.request تطلق استثناء إذا كان هناك خطأ اشتراك، لذا نعيد البيانات مباشرة
    return response['data'];
  }
}