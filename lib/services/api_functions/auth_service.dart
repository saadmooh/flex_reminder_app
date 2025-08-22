// services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AuthService {
  final ApiConfig _apiConfig;

  AuthService(this._apiConfig);

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String language = 'en',
  }) async {
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
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Registration failed.',
      };
    }
  }

  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String language = 'en',
  }) async {
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
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Login failed.',
      };
    }
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
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

    final responseData = json.decode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': responseData};
    } else {
      return {
        'success': false,
        'error': responseData['message'] ?? 'Verification failed.'
      };
    }
  }

  Future<Map<String, dynamic>> resendVerificationCode(String email) async {
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

    final responseData = json.decode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': responseData};
    } else {
      return {
        'success': false,
        'error': responseData['message'] ?? 'Failed to resend code.'
      };
    }
  }

  Future<Map<String, dynamic>> logout() async {
    final token = await _apiConfig.getToken();
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/logout');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return {'success': true};
    } else {
      return {'success': false, 'error': 'Logout failed on server'};
    }
  }

  Future<bool> checkTokenValidity() async {
    final token = await _apiConfig.getToken();
    if (token == null || token.isEmpty) return false;

    final url = Uri.parse('${ApiConfig.API_BASE_URL}/check-token');
    final response = await http.get(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    return response.statusCode == 200;
  }
}