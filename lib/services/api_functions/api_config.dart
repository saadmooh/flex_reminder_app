import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiConfig {
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  FlutterSecureStorage get storage => _storage;

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<bool> checkTokenValidity() async {
    final token = await getToken();
    if (token == null) return false;

    final response = await http.get(
      Uri.parse('$API_BASE_URL/verify-token'),
      headers: {
        'X-API-Password': API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    final data = jsonDecode(response.body);
    print('checkTokenValidity:$data');
    return response.statusCode == 200 && data['valid'] == true;
  }

  Future<int?> getCurrentUserId() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        return payload['sub'] as int?;
      }
      return null;
    } catch (e) {
      print('Error decoding token: $e');
      return null;
    }
  }
}
