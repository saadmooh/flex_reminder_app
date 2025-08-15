// خدمة API مبسطة للعمل في الخلفية
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundApiService {
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';

  // دالة للحصول على التوكن من SharedPreferences
  static Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token');
    } catch (e) {
      print('❌ Error getting auth token: $e');
      return null;
    }
  }

  // دالة مبسطة لإعادة جدولة المنشور
  static Future<Map<String, dynamic>?> reschedulePost(
    String postUrl, 
    String importance
  ) async {
    try {
      print('🔄 Background reschedule request for: $postUrl');

      final authToken = await _getAuthToken();
      if (authToken == null) {
        print('❌ No auth token available for background request');
        return null;
      }

      final response = await http.post(
        Uri.parse('$API_BASE_URL/reschedule'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'url': postUrl,
          'importance': importance,
          'password': API_PASSWORD,
        }),
      ).timeout(
        const Duration(seconds: 30), // timeout للأمان
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      print('📡 Background API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        print('✅ Background reschedule successful');
        return responseData;
      } else {
        print('❌ Background reschedule failed: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }

    } catch (e) {
      print('❌ Background reschedule error: $e');
      return null;
    }
  }

  // دالة مبسطة للحصول على تفاصيل التذكير
  static Future<Map<String, dynamic>?> getReminderDetails(int reminderId) async {
    try {
      final authToken = await _getAuthToken();
      if (authToken == null) return null;

      final response = await http.get(
        Uri.parse('$API_BASE_URL/reminders/$reminderId'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;

    } catch (e) {
      print('❌ Error getting reminder details: $e');
      return null;
    }
  }

  // دالة للتحقق من الاتصال بالإنترنت
  static Future<bool> hasInternetConnection() async {
    try {
      final response = await http.head(
        Uri.parse('https://www.google.com'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}