import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flex_reminder/services/api_functions/api_config.dart';
import 'package:flex_reminder/services/notification_service.dart';

class FcmService {
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();
  final NotificationService _notificationService = NotificationService();

  Future<void> init() async {
    await _firebaseMessaging.requestPermission();
    final fcmToken = await _firebaseMessaging.getToken();
    print("FCM Token: $fcmToken");
    await _storage.write(key: 'fcmToken', value: fcmToken);
    
   // String? userId = await _storage.read(key: 'userId');
   String? userId = '111';
    if (userId != null) {
      subscribeToTopic('user_$userId');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        _notificationService.scheduleNotification(
          title: message.notification!.title ?? 'New Message',
          body: message.notification!.body ?? '',
          channelKey: 'scheduled_channel',
        );
      }
    });
  }

  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
     print('Unsubscribed from topic: $topic');
  }

  Future<void> sendFcmTokenToBackend() async {
    String? token = await _storage.read(key: 'token');
    String? fcmToken = await _storage.read(key: 'fcmToken');

    if (token != null && fcmToken != null) {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/subscribe'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fcm_token': fcmToken}),
      );

      if (response.statusCode == 200) {
        print('FCM token sent to backend successfully');
      } else {
        print('Failed to send FCM token to backend: ${response.body}');
      }
    }
  }
}
