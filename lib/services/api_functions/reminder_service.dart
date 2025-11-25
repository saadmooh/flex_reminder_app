import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import '../../utils/consts.dart';
import 'api_config.dart';

class ReminderService {
  final ApiConfig _apiConfig;

  ReminderService(this._apiConfig);

  Future<List<int>> getRemindersIds() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${AppConstants.API_BASE_URL}/getRemindersIds');
    final token = await _apiConfig.getToken();

    final response = await http.get(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    print('Reminders IDs Response: ${response.body}');

    if (response.statusCode == 200) {
      final decodedData = json.decode(response.body) as List<dynamic>;
      return decodedData.map((id) => id as int).toList();
    } else {
      try {
        final errorData = json.decode(response.body) as Map<String, dynamic>?;
        throw Exception(errorData?['message'] ??
            'Failed to fetch reminder IDs: ${response.statusCode}');
      } catch (e) {
        throw Exception(
            'Failed to parse response: ${response.statusCode} - ${response.body}');
      }
    }
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
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final queryParameters = {
      'page': page.toString(),
      'perPage': perPage.toString(),
      if (searchQuery.isNotEmpty) 'search': searchQuery,
      if (category != null && category != 'All') 'category': category,
      if (complexity != null && complexity != 'All') 'complexity': complexity,
      if (domain != null && domain != 'All') 'domain': domain,
      if (forceFetch) 'forceFetch': 'true',
      if (excludeIds.isNotEmpty) 'ids': excludeIds.join(','),
    };

    final url = Uri.parse('${AppConstants.API_BASE_URL}/reminders')
        .replace(queryParameters: queryParameters);
    final token = await _apiConfig.getToken();

    final response = await http.get(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 10));

    print('Fetch Reminders Response: ${response.body}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = json.decode(response.body);
      return RemindersResponse.fromJson(responseData);
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized. Please log in again.');
    } else {
      throw Exception('Failed to load reminders: ${response.statusCode}');
    }
  }

  Future<void> deleteReminder(int id) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${AppConstants.API_BASE_URL}/deleteReminder/$id');
    final token = await _apiConfig.getToken();

    final response = await http.get(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    print('Delete Reminder Response: ${response.body}');

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to delete reminder.');
    }
  }

  Future<Reminder> getReminder(String postUrl) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    try {
      final url =
          Uri.parse('${AppConstants.API_BASE_URL}/reminder?url=$postUrl');
      final token = await _apiConfig.getToken();
      final response = await http.get(
        url,
        headers: {
          'X-API-Password': AppConstants.API_PASSWORD,
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      print('Get Reminder Response: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Empty response received');
        }
        try {
          final decodedData = json.decode(response.body);
          return Reminder.fromJson(decodedData);
        } on FormatException catch (e) {
          print('JSON parsing error: ${response.body}');
          throw Exception('Invalid response format: ${e.message}');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Reminder not found');
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Failed to load reminder');
        } catch (e) {
          throw Exception('Failed to load reminder: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error in getReminder: $e');
      rethrow;
    }
  }

  Future<Reminder> getReminderById(int postId) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }

    try {
      final url =
          Uri.parse('${AppConstants.API_BASE_URL}/reminderById?id=$postId');
      final token = await _apiConfig.getToken();
      final response = await http.get(
        url,
        headers: {
          'X-API-Password': AppConstants.API_PASSWORD,
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Get Reminder By ID Response: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Empty response received');
        }
        try {
          final decodedData = json.decode(response.body);

          // التحقق من وجود خاصية reminder في الاستجابة
          if (decodedData['reminder'] != null) {
            return Reminder.fromJson(decodedData['reminder']);
          } else {
            throw Exception('No reminder data found in response');
          }
        } on FormatException catch (e) {
          print('JSON parsing error: ${response.body}');
          throw Exception('Invalid response format: ${e.message}');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Reminder not found');
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Failed to load reminder');
        } catch (e) {
          throw Exception('Failed to load reminder: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error in getReminderById: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reschedulePost(
      String postUrl, String importance) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${AppConstants.API_BASE_URL}/reschedule-post');
    final token = await _apiConfig.getToken();

    final Map<String, Map<String, String>> importanceOptions = {
      'day': {'en': 'Day', 'ar': 'يوم'},
      'week': {'en': 'Week', 'ar': 'أسبوع'},
      'month': {'en': 'Month', 'ar': 'شهر'},
    };

    final importanceData =
        importanceOptions[importance] ?? {'en': 'Day', 'ar': 'يوم'};

    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'url': postUrl,
        'importance': importanceData['en'],
        'importance_ar': importanceData['ar'],
      }),
    );

    print('Reschedule Post Response: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return responseData;
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to reschedule post.');
    }
  }

  Future<Map<String, dynamic>> updateReminder(Reminder reminder) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${AppConstants.API_BASE_URL}/update-reminder');
    final token = await _apiConfig.getToken();

    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'id': reminder.id,
        'next_reminder_time': reminder.nextReminderTime,
        'title': reminder.title,
        'content': reminder.content,
        'importance': reminder.importance,
      }),
    );

    print('Update Reminder Response: ${response.body}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to update reminder.');
    }
  }

  Future<Map<String, dynamic>> savePost(Map<String, dynamic> data) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No token found');
    }

    final DateTime now = DateTime.now();
    final Duration offset = now.timeZoneOffset;

    final int hours = offset.inHours;
    final int minutes = offset.inMinutes.remainder(60);

    final String formattedTimezone =
        '${hours >= 0 ? '+' : ''}${hours.toString().padLeft(2, '0')}:${minutes.abs().toString().padLeft(2, '0')}';

    data['timezone_offset'] = formattedTimezone;
    data['timezone_name'] = now.timeZoneName;

    print('Save Post Request: $data');
    final response = await http.post(
      Uri.parse('${AppConstants.API_BASE_URL}/save-post'),
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(data),
    );

    print('Save Post Response: ${response.body}');

    return json.decode(response.body);
  }
}
