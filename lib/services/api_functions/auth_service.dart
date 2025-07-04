import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final ApiConfig _apiConfig;
  final NotificationService _notificationService = NotificationService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthService(this._apiConfig) {
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    await _notificationService.init();
  }

  Future<Map<String, dynamic>> register(
      String name, String email, String password,
      {String language = 'en'}) async {
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/register');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'name': name,
        'email': email,
        'password': password,
        'language': language,
      },
    );

    final responseData = json.decode(response.body);
    print('Register Response: $responseData');

    if (response.statusCode == 201) {
      return {
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors'] ??
            'Registration failed.',
      };
    }
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String language = 'en'}) async {
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/login');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'email': email,
        'password': password,
        'device_name': 'mobile_app',
      },
    );

    final responseData = json.decode(response.body);
    print('Login Response: $responseData');

    if (response.statusCode == 200) {
      return {
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'statusCode': response.statusCode,
        'data': responseData,
      };
    }
  }

  Future<void> logout() async {
    try {
      print('Starting logout process...');
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'last_check_result');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      print('Successfully cleared auth_token, last_check_result, and user_id');
    } catch (e) {
      print('Error during logout: $e');
      await _storage.deleteAll();
      print('Cleared all storage as fallback');
    }
  }

  Future<void> verifyEmail(String email, String code) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/verify-email');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'code': code}),
    );

    print('Verify Email Response: ${response.body}');

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Verification failed.');
    }
  }

  Future<void> resendVerificationCode(String email) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/resend-verification');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );

    print('Resend Verification Response: ${response.body}');

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
          errorData['message'] ?? 'Failed to resend verification code.');
    }
  }
}
