import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/consts.dart';
import '../../globals.dart'; // navigatorKey
import 'api_config.dart';
import 'exceptions.dart';
import '../authentication_service.dart';

class UtilsService {
  final ApiConfig _apiConfig;

  UtilsService(this._apiConfig);

  // Getter to access ApiConfig from other services
  ApiConfig get apiConfig => _apiConfig;

  // Generic request method (GET/POST)
 Future<Map<String, dynamic>> request(
  String method,
  String endpoint, {
  Map<String, dynamic>? data,
  String contentType = 'application/json',
}) async {
  if (!await _apiConfig.checkTokenValidity()) {
    await _handleInvalidToken();
    throw Exception('Session expired');
  }

  // إنشاء URI مع query parameters للـ GET
  Uri uri;
  if (method == 'GET' && data != null && data.isNotEmpty) {
    uri = Uri.parse('${AppConstants.API_BASE_URL}/$endpoint')
        .replace(queryParameters: data.map((key, value) => MapEntry(key, value.toString())));
  } else {
    uri = Uri.parse('${AppConstants.API_BASE_URL}/$endpoint');
  }

  http.Response response;

  try {
    final headers = {
      'X-API-Password': AppConstants.API_PASSWORD,
    };

    final token = await _apiConfig.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (method == 'POST') {
      headers['Content-Type'] = contentType;
      response = await http.post(
        uri,
        headers: headers,
        body: contentType == 'application/x-www-form-urlencoded'
            ? data
            : jsonEncode(data),
      );
    } else {
      response = await http.get(uri, headers: headers);
    }
  } catch (e) {
    throw Exception('Failed to connect to server');
  }

  print('Request: $method $endpoint → ${response.statusCode}');
  final responseData = jsonDecode(response.body);

  if (responseData is Map<String, dynamic> &&
      responseData['success'] == false &&
      responseData['message'] == 'no_valid_subscription') {
    print('🚨 Server returned: no_valid_subscription');
    print('📍 Endpoint: $endpoint | Method: $method');
    await handleNoValidSubscription();
    throw NoValidSubscriptionException('No valid subscription');
  }

  return {
    'statusCode': response.statusCode,
    'data': responseData,
  };
}

  // Handle expired token
  Future<void> _handleInvalidToken() async {
    await _performBasicCleanup();
    await _triggerFullLogout();
  }

  // Handle subscription expiration
  Future<void> handleNoValidSubscription() async {
    try {
      print('⚠️ ========== NO VALID SUBSCRIPTION DETECTED ==========');
      print('📤 Initiating complete logout and cleanup process');
      
      final navigator = navigatorKey.currentState;

      if (navigator != null && navigator.mounted) {
        final context = navigator.context;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Your subscription has expired, please renew to continue'),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );

        print('🔄 Calling AuthenticationService.logout() for comprehensive cleanup');
        print('   → This will: Reset RevenueCat, Cancel notifications, Clear cache, Sign out');
        
        final authService = AuthenticationService(context);
        await authService.logout();
        
        print('✅ Complete logout finished - User redirected to auth screen');
        print('========== SUBSCRIPTION EXPIRY LOGOUT COMPLETE ==========');
      } else {
        print('⚠️ Navigator not available, forcing navigation via PostFrameCallback');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey.currentState != null) {
            print('🔄 Executing fallback navigation to /auth');
            navigatorKey.currentState!
                .pushNamedAndRemoveUntil('/auth', (_) => false);
            print('✅ Fallback navigation complete');
          }
        });
      }
    } catch (e) {
      print('❌ Critical error in handleNoValidSubscription: $e');
      try {
        print('🚨 Attempting emergency navigation to /auth');
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/auth', (_) => false);
        print('✅ Emergency navigation successful');
      } catch (navError) {
        print('❌ Final navigation attempt failed: $navError');
      }
    }
  }

  // Full logout (simulating logout button press)
  Future<void> _triggerFullLogout({
    bool showMessage = false,
    String? message,
  }) async {
    try {
      final navigator = navigatorKey.currentState;

      if (navigator != null && navigator.mounted) {
        final context = navigator.context;

        try {
          final authService = AuthenticationService(context);
          await authService.logout();
        } catch (e) {
          print('Auth logout error: $e');
          await _performBasicCleanup();

          if (showMessage && navigator.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message ?? 'Logged out successfully'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
        }
      } else {
        print('⚠️ Navigator not available, forcing navigation');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!
                .pushNamedAndRemoveUntil('/auth', (_) => false);
          }
        });
      }
    } catch (e) {
      print('Critical logout error: $e');
      try {
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/auth', (_) => false);
      } catch (navError) {
        print('Final navigation attempt failed: $navError');
      }
    }
  }

  // Basic cleanup of local data
  Future<void> _performBasicCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await _apiConfig.storage.delete(key: 'token');
      await _apiConfig.storage.delete(key: 'refresh_token');
      print('Basic cleanup done');
    } catch (e) {
      print('Cleanup error: $e');
    }
  }

  // Get server time
  Future<DateTime> getServerTime() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.API_BASE_URL}/server-time'),
        headers: {
          'X-API-Password': AppConstants.API_PASSWORD,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['server_time'] != null) {
          final serverDate = DateTime.parse(data['server_time']);
          await _apiConfig.storage.write(
            key: AppConstants.LAST_SERVER_TIME_KEY,
            value: serverDate.toIso8601String(),
          );
          return serverDate;
        }
      }
    } catch (e) {
      print('Server time error: $e');
    }

    final lastTimeStr =
        await _apiConfig.storage.read(key: AppConstants.LAST_SERVER_TIME_KEY);
    return lastTimeStr != null ? DateTime.parse(lastTimeStr) : DateTime.now();
  }

  // Get API configuration
  Future<Map<String, dynamic>> getApiConfig() async {
    final responseMap = await request('GET', 'api-credentials');
    if (responseMap['statusCode'] != 200) {
      throw Exception('Failed to fetch settings');
    }
    return responseMap['data'];
  }

  // Get API credentials
  Future<Map<String, dynamic>> getApiCredentials() async {
    final responseMap = await request('GET', 'api-credentials');
    if (responseMap['statusCode'] != 200) {
      throw Exception('Failed to fetch data');
    }
    return responseMap['data'];
  }
}