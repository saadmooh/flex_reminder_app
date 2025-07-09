import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flex_reminder/services/api_functions/api_config.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/globals.dart';

class FcmService {
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();
  final NotificationService _notificationService = NotificationService();

  void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey.currentContext!);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } else {
      print('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    }
  }

  Future<Map<String, dynamic>> init() async {
    try {
      // الحصول على FCM token
      final fcmToken = await _firebaseMessaging.getToken();
      _showSnackBar("تم الحصول على FCM Token بنجاح", Colors.green);
      await _storage.write(key: 'fcmToken', value: fcmToken);

      // إرسال التوكن إلى الباكند
      String message = await sendFcmTokenToBackend();

      // الاشتراك في موضوع user_111
      await subscribeToTopic('user_111');

      // إرجاع التوكن ورسالة الحالة
      return {
        'fcmToken': fcmToken,
        'message': message,
      };
    } catch (e) {
      _showSnackBar('فشل في تهيئة FCM: $e', Colors.red);
      return {
        'fcmToken': null,
        'message': 'فشل في تهيئة FCM: $e',
      };
    }
  }

  // دالة معالجة الرسائل في الخلفية
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('Handling a background message: ${message.messageId}');
    print('Background message data: ${message.data}');

    // إرسال إشعار فوري في الخلفية
    await NotificationService().scheduleNotification(
      title: message.data['title'] ?? 'إشعار جديد',
      body: message.data['body'] ?? 'تم استلام بيانات جديدة',
      channelKey: 'scheduled_channel',
      payload: message.data.cast<String, String>(),
    );
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      _showSnackBar('تم الاشتراك في الموضوع: $topic', Colors.blue);
    } catch (e) {
      _showSnackBar('خطأ في الاشتراك في الموضوع: $e', Colors.red);
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      _showSnackBar('تم إلغاء الاشتراك من الموضوع: $topic', Colors.orange);
    } catch (e) {
      _showSnackBar('خطأ في إلغاء الاشتراك من الموضوع: $e', Colors.red);
    }
  }

  Future<String> sendFcmTokenToBackend() async {
    String? token = await _storage.read(key: 'token');
    String? fcmToken = await _storage.read(key: 'fcmToken');

    if (token != null && fcmToken != null) {
      try {
        final response = await http.post(
          Uri.parse('$API_BASE_URL/subscribe'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'fcm_token': fcmToken}),
        );

        if (response.statusCode == 200) {
          _showSnackBar('تم إرسال التوكن إلى الخادم بنجاح', Colors.green);
          return 'تم إرسال التوكن إلى الخادم بنجاح';
        } else {
          _showSnackBar('فشل في إرسال التوكن إلى الخادم', Colors.red);
          return 'فشل في إرسال التوكن إلى الخادم: ${response.body}';
        }
      } catch (e) {
        _showSnackBar('خطأ في إرسال التوكن إلى الخادم', Colors.red);
        return 'خطأ في إرسال التوكن إلى الخادم: $e';
      }
    } else {
      _showSnackBar('لا يمكن إرسال التوكن: توكن المصادقة أو توكن FCM غير موجود', Colors.red);
      return 'لا يمكن إرسال التوكن: توكن المصادقة أو توكن FCM غير موجود';
    }
  }
}