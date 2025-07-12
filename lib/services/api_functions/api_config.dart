import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../globals.dart';

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

    if (await _checkInternetConnectivity() == false) {
      return false;
    }

    try {
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
    } catch (e) {
      print('Error checking token validity: $e');
      return false;
    }
  }

  Future<bool> _checkInternetConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      // Optionally, show a user-friendly message
      // For example, using a SnackBar or a dialog
      ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
        const SnackBar(
          content: Text('No internet connection'),
        ),
      );
      debugPrint('No internet connection');
      return false;
    }
    return true;
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
