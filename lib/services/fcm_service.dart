import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flex_reminder/services/api_functions/api_config.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:permission_handler/permission_handler.dart';

class FcmService {
  // Singleton instance
  static FcmService? _instance;
  static FcmService get instance {
    _instance ??= FcmService._internal();
    return _instance!;
  }

  // Private constructor
  FcmService._internal();

  // Factory constructor that returns the same instance
  factory FcmService() => instance;

  // إضافة متغير لتتبع التهيئة
  bool _isInitialized = false;

  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();
  final NotificationService _notificationService = NotificationService();
  // متغيرات تتبع حالة التطبيق والرسائل
  static bool _isAppInForeground = true;
  static final Set<String> _processedMessages = <String>{};
  static const int _maxProcessedMessages = 100;
  static final Map<int, DateTime> _lastProcessedTime = <int, DateTime>{};
  static const Duration _processDelay = Duration(seconds: 2);

  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  // دالة للتحقق من حالة التهيئة
  bool get isInitialized => _isInitialized;

  void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey.currentContext!);

      if (scaffoldMessenger.mounted) {
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
        print('ScaffoldMessenger غير متاح، تم تجاهل SnackBar: $message');
      }
    } else {
      print('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    }
  }

  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      print('FCM Message: $message');
    }

    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  static bool _isDuplicateMessage(String messageId) {
    if (_processedMessages.contains(messageId)) {
      print('رسالة مكررة تم تجاهلها: $messageId');
      return true;
    }

    _processedMessages.add(messageId);

    if (_processedMessages.length > _maxProcessedMessages) {
      final oldMessages = _processedMessages
          .take(_processedMessages.length - _maxProcessedMessages);
      _processedMessages.removeAll(oldMessages);
    }

    return false;
  }

  static bool _shouldProcessReminder(int reminderId) {
    final now = DateTime.now();
    final lastProcessed = _lastProcessedTime[reminderId];

    if (lastProcessed != null &&
        now.difference(lastProcessed) < _processDelay) {
      print('تم تأخير معالجة التذكير $reminderId لتجنب التكرار');
      return false;
    }

    _lastProcessedTime[reminderId] = now;

    _lastProcessedTime.removeWhere(
        (key, value) => now.difference(value) > const Duration(minutes: 5));

    return true;
  }

  Future<bool> requestAllPermissions() async {
    try {
      print('🔐 طلب الأذونات المطلوبة...');

      // طلب إذن الإشعارات من Firebase
      NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      print('📱 حالة إذن الإشعارات: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _safeShowMessage('تم رفض إذن الإشعارات', color: Colors.red);
        return false;
      }

      // طلب أذونات إضافية للأندرويد
      if (!kIsWeb) {
        // إذن الإشعارات
        final notificationStatus = await Permission.notification.request();
        print('📢 إذن الإشعارات: $notificationStatus');

        // إذن تجاهل تحسين البطارية
        final batteryStatus =
            await Permission.ignoreBatteryOptimizations.request();
        print('🔋 إذن تحسين البطارية: $batteryStatus');

        // إذن الجدولة الدقيقة للتنبيهات
        final scheduleStatus = await Permission.scheduleExactAlarm.request();
        print('⏰ إذن الجدولة الدقيقة: $scheduleStatus');

        _permissionsGranted = notificationStatus.isGranted;
      } else {
        _permissionsGranted =
            settings.authorizationStatus == AuthorizationStatus.authorized;
      }

      if (_permissionsGranted) {
        _safeShowMessage('تم منح جميع الأذونات بنجاح', color: Colors.green);
      } else {
        _safeShowMessage('بعض الأذونات غير ممنوحة', color: Colors.orange);
      }

      return _permissionsGranted;
    } catch (e) {
      print('❌ خطأ في طلب الأذونات: $e');
      _safeShowMessage('خطأ في طلب الأذونات: $e', color: Colors.red);
      return false;
    }
  }

  Future<Map<String, dynamic>> init() async {
    if (_isInitialized) {
      print('FCM Service already initialized');
      final fcmToken = await _storage.read(key: 'fcmToken');
      return {
        'fcmToken': fcmToken,
        'message': 'FCM Service already initialized',
        'permissionsGranted': _permissionsGranted,
      };
    }

    try {
      // طلب الأذونات أولاً
      final permissionsGranted = await requestAllPermissions();
      if (!permissionsGranted) {
        _safeShowMessage('لم يتم منح الأذونات اللازمة', color: Colors.orange);
      }

      final fcmToken = await getAccessToken();
      if (fcmToken != null) {
        _safeShowMessage("تم الحصول على FCM Token بنجاح", color: Colors.green);
        await _storage.write(key: 'fcmToken', value: fcmToken);
      } else {
        _safeShowMessage("فشل في الحصول على FCM Token", color: Colors.red);
        return {
          'fcmToken': null,
          'message': 'فشل في الحصول على FCM Token',
          'permissionsGranted': false,
        };
      }

      String message = await sendFcmTokenToBackend();

      if (!kIsWeb) {
        final userId = await _getUserId();
        if (userId != null) {
          await subscribeToTopic('user_$userId');
        } else {
          print('لم يتم العثور على user_id في التخزين الآمن');
          _safeShowMessage('لم يتم العثور على معرف المستخدم',
              color: Colors.orange);
        }
      } else {
        print('الاشتراك في المواضيع غير مدعوم في منصة الويب');
      }

      await _setupMessageHandlers();
      _setupAppLifecycleListener();

      print('✅ تم تهيئة FCM المحسن بنجاح');
      _isInitialized = true;

      return {
        'fcmToken': fcmToken,
        'message': message,
        'permissionsGranted': permissionsGranted,
      };
    } catch (e) {
      _safeShowMessage('فشل في تهيئة FCM: $e', color: Colors.red);
      return {
        'fcmToken': null,
        'message': 'فشل في تهيئة FCM: $e',
        'permissionsGranted': false,
      };
    }
  }

  static Future<void> _processMessage(RemoteMessage message,
      {required bool isBackground}) async {
    try {
      final String title =
          message.data['title'] ?? message.notification?.title ?? '';
      final String body =
          message.data['body'] ?? message.notification?.body ?? '';
      final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

      print('Title: $title');
      print('Body: $body');
      print('Is Background: $isBackground');

      if (title.isEmpty || body.isEmpty) {
        print('بيانات الرسالة غير مكتملة');
        if (!isBackground) {
          FcmService.instance._safeShowMessage('بيانات الرسالة غير مكتملة',
              color: Colors.orange);
        }
        return;
      }

      int? reminderId;
      try {
        reminderId = int.parse(body.trim());
      } catch (e) {
        print('body ليس رقماً، سيتم التعامل معه كإشعار عادي: $body');
        await _handleGeneralNotification(title, body, data, isBackground);
        return;
      }

      if (reminderId == null || reminderId <= 0) {
        print('معرف التذكير غير صحيح: $reminderId');
        return;
      }

      if (!_shouldProcessReminder(reminderId)) {
        return;
      }

      print('=== بدء معالجة التذكير $reminderId - العملية: $title ===');

      final remindersNotifier = RemindersNotifier.instance;

      bool operationSuccess = false;
      String successMessage = '';
      String errorMessage = '';

      switch (title.toLowerCase().trim()) {
        case 'reschedule':
          try {
            await remindersNotifier.handleRescheduleFromFcm(reminderId);
            operationSuccess = true;
            successMessage = 'تم إعادة جدولة التذكير رقم $reminderId';
          } catch (e) {
            errorMessage = 'فشل في إعادة جدولة التذكير رقم $reminderId: $e';
          }
          break;

        case 'update':
          try {
            await remindersNotifier.handleUpdateFromFcm(reminderId);
            operationSuccess = true;
            successMessage = 'تم تحديث التذكير رقم $reminderId';
          } catch (e) {
            errorMessage = 'فشل في تحديث التذكير رقم $reminderId: $e';
          }
          break;

        case 'new':
          try {
            await remindersNotifier.handleNewReminderFromFcm(reminderId);
            operationSuccess = true;
            successMessage = 'تم إضافة تذكير جديد رقم $reminderId';
          } catch (e) {
            errorMessage = 'فشل في إضافة التذكير الجديد رقم $reminderId: $e';
          }
          break;

        case 'markas_read':
        case 'mark_as_read':
          try {
            await remindersNotifier.handleMarkAsReadFromFcm(reminderId);
            operationSuccess = true;
            successMessage = 'تم وضع علامة "مقروء" على التذكير رقم $reminderId';
          } catch (e) {
            errorMessage =
                'فشل في وضع علامة "مقروء" على التذكير رقم $reminderId: $e';
          }
          break;

        case 'delete':
          try {
            await remindersNotifier.deleteReminderComprehensive(reminderId);
            //  operationSuccess = true;
            // successMessage = 'تم حذف التذكير رقم $reminderId';
          } catch (e) {
            errorMessage = 'فشل في حذف التذكير رقم $reminderId: $e';
          }
          break;

        default:
          print('نوع العملية غير مدعوم: $title');
          await _handleGeneralNotification(title, body, data, isBackground);
          return;
      }

      if (operationSuccess) {
        print('✅ $successMessage');

        if (!isBackground) {
          FcmService.instance
              ._safeShowMessage(successMessage, color: Colors.green);
        }

        if (isBackground) {
          await _sendGenericNotification(
            'تم بنجاح',
            successMessage,
            data,
          );
        }
      } else {
        print('❌ $errorMessage');

        if (!isBackground) {
          FcmService.instance._safeShowMessage(errorMessage, color: Colors.red);
        }

        if (isBackground) {
          await _sendGenericNotification(
            'خطأ في العملية',
            errorMessage,
            data,
          );
        }
      }
    } catch (e) {
      print('خطأ عام في معالجة الرسالة: $e');

      if (!isBackground) {
        FcmService.instance
            ._safeShowMessage('خطأ في معالجة الرسالة: $e', color: Colors.red);
      } else {
        await _sendGenericNotification(
          'خطأ في المعالجة',
          'حدث خطأ أثناء معالجة الرسالة',
          message.data,
        );
      }
    }
  }

  static Future<void> _handleGeneralNotification(String title, String body,
      Map<String, dynamic> data, bool isBackground) async {
    print('=== معالجة إشعار عام ===');
    print('Title: $title');
    print('Body: $body');
    print('Is Background: $isBackground');

    if (isBackground) {
      await _sendGenericNotification(title, body, data);
    } else {
      FcmService.instance._safeShowMessage('$title: $body', color: Colors.blue);
    }
  }

  static Future<void> _sendGenericNotification(
      String title, String body, Map<String, dynamic> data) async {
    try {
      print('📢 إرسال إشعار محلي: $title - $body');

      await NotificationService.instance.scheduleNotification(
        title: title,
        body: body,
        channelKey: 'scheduled_channel',
        payload: data.cast<String, String>(),
      );
    } catch (e) {
      print('❌ خطأ في إرسال الإشعار المحلي: $e');
    }
  }

  Future<String?> _getUserId() async {
    try {
      return await _storage.read(key: 'user_id');
    } catch (e) {
      print('خطأ في الحصول على user_id: $e');
      return null;
    }
  }

  void _handleNavigationLogic(RemoteMessage message, String userTopic) {
    try {
      final String title =
          message.data['title'] ?? message.notification?.title ?? '';
      final String body =
          message.data['body'] ?? message.notification?.body ?? '';

      print('=== معالجة منطق التنقل ===');
      print('نوع العملية: $title');
      print('معرف التذكير: $body');
      print('الموضوع: $userTopic');

      switch (title.toLowerCase().trim()) {
        case 'reschedule':
          print('🔄 التنقل إلى صفحة إعادة الجدولة');
          break;
        case 'update':
          print('✏️ التنقل إلى صفحة تحديث التذكير');
          break;
        case 'new':
          print('🆕 التنقل إلى صفحة التذكيرات الجديدة');
          break;
        case 'markas_read':
        case 'mark_as_read':
          print('✅ التنقل إلى صفحة التذكيرات المقروءة');
          break;
        case 'delete':
          print('🗑️ التنقل إلى الصفحة الرئيسية');
          break;
        default:
          print('📱 التنقل العام للإشعار');
      }
    } catch (e) {
      print('❌ خطأ في معالجة منطق التنقل: $e');
    }
  }

  Future<String?> getAccessToken() async {
    try {
      if (kIsWeb) {
        return await _firebaseMessaging.getToken(
          vapidKey: 'your-vapid-key-here',
        );
      }

      final jsonString = await rootBundle.loadString(
        'assets/flex-reminders-app-7e58d9767343.json',
      );

      final accountCredentials =
          auth.ServiceAccountCredentials.fromJson(jsonString);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client =
          await auth.clientViaServiceAccount(accountCredentials, scopes);
      _safeShowMessage(client.credentials.accessToken.data,
          color: Colors.green);
      return client.credentials.accessToken.data;
    } catch (e) {
      print('خطأ في الحصول على Access Token: $e');
      try {
        return await _firebaseMessaging.getToken();
      } catch (fallbackError) {
        print('خطأ في الحصول على التوكن البديل: $fallbackError');
        return null;
      }
    }
  }

  Future<void> _setupMessageHandlers() async {
    String? userId = await _storage.read(key: 'user_id');
    final userTopic = userId != null ? 'user_$userId' : 'unknown_user';

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('تم استلام رسالة أثناء تشغيل التطبيق: ${message.messageId}');
      print('الموضوع المستهدف: $userTopic');
      print('بيانات الرسالة: ${message.data}');

      if (message.data.containsKey('topic') &&
          message.data['topic'] == userTopic) {
        print('تم استلام رسالة من الموضوع الصحيح: ${message.data['topic']}');
      }

      _handleForegroundMessage(message);

      final topicMessage =
          message.data['topic'] ?? 'تم استلام رسالة من الموضوع: $userTopic';
      _safeShowMessage(topicMessage, color: Colors.green);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('تم فتح التطبيق من خلال الإشعار: ${message.messageId}');
      print('الموضوع: $userTopic');
      print('بيانات الرسالة: ${message.data}');

      _handleMessageOpenedApp(message);
      _handleNavigationLogic(message, userTopic);
    });

    RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      print('📬 تم فتح التطبيق من إشعار منهي');
      await _handleMessageOpenedApp(initialMessage);
      _handleNavigationLogic(initialMessage, userTopic);
    }

    _firebaseMessaging.onTokenRefresh.listen((String newToken) {
      print('🔄 تم تحديث FCM Token');
      _storage.write(key: 'fcmToken', value: newToken);
      sendFcmTokenToBackend();
    });

    print('✅ تم تعيين معالجات الرسائل');
  }

  void _setupAppLifecycleListener() {
    print('تم تعيين مراقب دورة حياة التطبيق');
  }

  // دالة معالجة الرسائل في المقدمة
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('=== معالجة رسالة مقدمة ===');
    print('Message ID: ${message.messageId}');
    print('Data: ${message.data}');
    print('Notification: ${message.notification?.toMap()}');

    _isAppInForeground = true;

    if (message.messageId != null && _isDuplicateMessage(message.messageId!)) {
      return;
    }

    try {
      await _processMessage(message, isBackground: false);
    } catch (e) {
      print('خطأ في معالجة الرسالة في المقدمة: $e');
      _safeShowMessage('خطأ في معالجة الرسالة', color: Colors.red);
    }
  }

  // دالة معالجة النقر على الإشعار
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    print('=== تم فتح التطبيق من الإشعار ===');
    print('Message ID: ${message.messageId}');

    _isAppInForeground = true;

    if (message.messageId != null &&
        _isDuplicateMessage('opened_${message.messageId!}')) {
      return;
    }

    try {
      await _processMessage(message, isBackground: false);
      _safeShowMessage('تم فتح التطبيق من الإشعار', color: Colors.blue);
    } catch (e) {
      print('خطأ في معالجة فتح التطبيق من الإشعار: $e');
      _safeShowMessage('خطأ في معالجة الإشعار', color: Colors.red);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      print('الاشتراك في المواضيع غير مدعوم في منصة الويب');
      _safeShowMessage('الاشتراك في المواضيع غير مدعوم في منصة الويب',
          color: Colors.orange);
      return;
    }

    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      _safeShowMessage('تم الاشتراك في الموضوع: $topic', color: Colors.blue);
    } catch (e) {
      _safeShowMessage('خطأ في الاشتراك في الموضوع: $e', color: Colors.red);
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      print('إلغاء الاشتراك من المواضيع غير مدعوم في منصة الويب');
      _safeShowMessage('إلغاء الاشتراك من المواضيع غير مدعوم في منصة الويب',
          color: Colors.orange);
      return;
    }

    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      _safeShowMessage('تم إلغاء الاشتراك من الموضوع: $topic',
          color: Colors.orange);
    } catch (e) {
      _safeShowMessage('خطأ في إلغاء الاشتراك من الموضوع: $e',
          color: Colors.red);
    }
  }

  Future<String> sendFcmTokenToBackend() async {
    try {
      String? token = await _storage.read(key: 'auth_token');
      String? fcmToken = await _storage.read(key: 'fcmToken');
      String? userId = await _storage.read(key: 'user_id');

      if (token == null) {
        const message = 'توكن المصادقة غير موجود. يرجى تسجيل الدخول مرة أخرى';
        _safeShowMessage(message, color: Colors.red);
        return message;
      }

      if (fcmToken == null) {
        const message = 'توكن FCM غير موجود';
        _safeShowMessage(message, color: Colors.red);
        return message;
      }

      final response = await http.post(
        Uri.parse('$API_BASE_URL/fcm/subscribe'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'token': fcmToken,
          'topic': 'user_$userId',
          'user_id': userId,
          'platform': 'mobile_app'
        }),
      );

      if (response.statusCode == 200) {
        const message = 'تم إرسال التوكن إلى الخادم بنجاح';
        _safeShowMessage(message, color: Colors.green);
        return message;
      } else {
        final message =
            'فشل في إرسال التوكن إلى الخادم: ${response.statusCode}';
        _safeShowMessage(message, color: Colors.red);
        return message;
      }
    } catch (e) {
      final message = 'خطأ في إرسال التوكن إلى الخادم: $e';
      _safeShowMessage(message, color: Colors.red);
      return message;
    }
  }

  Future<bool> isTokenValid() async {
    final token = await _storage.read(key: 'auth_token');
    return token != null && token.isNotEmpty;
  }

  Future<void> resubscribeToUserTopic() async {
    if (kIsWeb) {
      print('إعادة الاشتراك في المواضيع غير مدعومة في منصة الويب');
      return;
    }

    try {
      final userId = await _getUserId();
      if (userId != null) {
        await subscribeToTopic('user_$userId');
        print('تم إعادة الاشتراك في الموضوع: user_$userId');
      } else {
        print('لم يتم العثور على user_id لإعادة الاشتراك');
      }
    } catch (e) {
      print('خطأ في إعادة الاشتراك في الموضوع: $e');
    }
  }

  Future<String?> getCurrentUserTopic() async {
    final userId = await _getUserId();
    return userId != null ? 'user_$userId' : null;
  }

  Future<void> refreshFcmToken() async {
    try {
      final newToken = await getAccessToken();
      if (newToken != null) {
        await _storage.write(key: 'fcmToken', value: newToken);
        await sendFcmTokenToBackend();
      }
    } catch (e) {
      print('خطأ في تحديث FCM Token: $e');
    }
  }

  Future<void> logout() async {
    try {
      if (!kIsWeb) {
        final userId = await _getUserId();
        if (userId != null) {
          await unsubscribeFromTopic('user_$userId');
        }
      }

      await _storage.delete(key: 'fcmToken');
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_id');

      print('تم تسجيل الخروج وإلغاء FCM Token');
    } catch (e) {
      print('خطأ في تسجيل الخروج: $e');
    }
  }

  static Future<void> processMessage(RemoteMessage message,
      {required bool isBackground}) async {
    await _processMessage(message, isBackground: isBackground);
  }

  static Future<void> sendGenericNotification(
      String title, String body, Map<String, dynamic> data) async {
    await _sendGenericNotification(title, body, data);
  }

  static bool isDuplicateMessage(String messageId) {
    return _isDuplicateMessage(messageId);
  }

  static bool shouldProcessReminder(int reminderId) {
    return _shouldProcessReminder(reminderId);
  }

  static Future<void> handleGeneralNotification(String title, String body,
      Map<String, dynamic> data, bool isBackground) async {
    await _handleGeneralNotification(title, body, data, isBackground);
  }

  static void resetInstance() {
    _instance = null;
  }
}
