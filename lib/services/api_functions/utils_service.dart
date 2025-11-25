import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/consts.dart';
import '../../globals.dart'; // navigatorKey
import 'api_config.dart';
import 'exceptions.dart'; // تم استيراد الاستثناء الجديد
import '../authentication_service.dart'; // تأكد من المسار الصحيح

class UtilsService {
  final ApiConfig _apiConfig;

  UtilsService(this._apiConfig);

  // طلب عام (GET/POST)
  Future<Map<String, dynamic>> request(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
  }) async {
    if (!await _apiConfig.checkTokenValidity()) {
      await _handleInvalidToken();
      throw Exception('الجلسة منتهية الصلاحية');
    }

    final uri = Uri.parse('${AppConstants.API_BASE_URL}/$endpoint');
    http.Response response;

    try {
      // إضافة التوكن في الهيدر إذا كان متوفراً
      final headers = {
        'X-API-Password': AppConstants.API_PASSWORD,
      };

      final token = await _apiConfig.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      if (method == 'POST') {
        headers['Content-Type'] = 'application/json';
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(data),
        );
      } else {
        response = await http.get(uri, headers: headers);
      }
    } catch (e) {
      throw Exception('فشل الاتصال بالخادم');
    }

    print('Request: $method $endpoint → ${response.statusCode}');
    final responseData = jsonDecode(response.body);

    if (responseData is Map<String, dynamic> &&
        responseData['success'] == false &&
        responseData['message'] == 'no_valid_subscription') {
      // استدعاء طريقة تسجيل الخروج العامة
      await handleNoValidSubscription();
      // إطلاق استثناء مخصص لمنع عرض رسالة الخطأ في الواجهة
      throw NoValidSubscriptionException('لا يوجد اشتراك صالح');
    }

    return {
      'statusCode': response.statusCode,
      'data': responseData,
    };
  }

  // معالجة توكن منتهي
  Future<void> _handleInvalidToken() async {
    await _performBasicCleanup();
    await _triggerFullLogout();
  }

  // معالجة انتهاء الاشتراك (تم تغييرها إلى عامة)
  Future<void> handleNoValidSubscription() async {
    await _performBasicCleanup();
    await _triggerFullLogout(
      showMessage: true,
      message: 'انتهى اشتراكك، يرجى التجديد للمتابعة',
    );
  }

  // تسجيل الخروج الكامل (محاكاة لضغط زر تسجيل الخروج)
  Future<void> _triggerFullLogout({
    bool showMessage = false,
    String? message,
  }) async {
    try {
      // استخدام navigatorKey.currentState للوصول إلى الـ context
      final navigator = navigatorKey.currentState;

      if (navigator != null && navigator.mounted) {
        final context = navigator.context;

        // محاكاة ضغط زر تسجيل الخروج في UpperAppBar
        try {
          final authService = AuthenticationService(context);
          await authService.logout();
        } catch (e) {
          print('Auth logout error: $e');
          // في حالة فشل تسجيل الخروج من AuthenticationService،
          // نقوم بالتنظيف والانتقال يدوياً
          await _performBasicCleanup();

          // عرض الرسالة إذا لزم الأمر
          if (showMessage && navigator.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message ?? 'تم تسجيل الخروج بنجاح'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // الانتقال إلى صفحة تسجيل الدخول
          navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
        }
      } else {
        // fallback: إذا فشل كل شيء
        print(
            '⚠️ Navigator not available, forcing navigation via Navigator.of');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!
                .pushNamedAndRemoveUntil('/auth', (_) => false);
          }
        });
      }
    } catch (e) {
      print('Critical logout error: $e');
      // آخر محاولة للانتقال
      try {
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/auth', (_) => false);
      } catch (navError) {
        print('Final navigation attempt failed: $navError');
      }
    }
  }

  // تنظيف أساسي للبيانات المحلية
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

  // جلب وقت الخادم
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

  // جلب إعدادات API
  Future<Map<String, dynamic>> getApiConfig() async {
    if (!await _apiConfig.checkTokenValidity()) {
      await _handleInvalidToken();
      throw Exception('الجلسة منتهية');
    }

    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${AppConstants.API_BASE_URL}/api-credentials'),
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(response.body);
    if (data['success'] == false &&
        data['message'] == 'no_valid_subscription') {
      await handleNoValidSubscription(); // استخدام الطريقة العامة
      throw NoValidSubscriptionException('لا يوجد اشتراك صالح');
    }

    return response.statusCode == 200
        ? data
        : throw Exception('فشل جلب الإعدادات');
  }

  // جلب بيانات API
  Future<Map<String, dynamic>> getApiCredentials() async {
    if (!await _apiConfig.checkTokenValidity()) {
      await _handleInvalidToken();
      throw Exception('الجلسة منتهية');
    }

    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${AppConstants.API_BASE_URL}/api-credentials'),
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(response.body);
    if (data['success'] == false &&
        data['message'] == 'no_valid_subscription') {
      await handleNoValidSubscription(); // استخدام الطريقة العامة
      throw NoValidSubscriptionException('لا يوجد اشتراك صالح');
    }

    return response.statusCode == 200
        ? data
        : throw Exception('فشل جلب البيانات');
  }
}
