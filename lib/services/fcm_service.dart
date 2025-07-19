import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'; // للتحقق من منصة الويب
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/services/api_functions/api_config.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/services/api_service.dart';


class FcmService {
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  final ApiService _apiService = ApiService();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();
  final NotificationService _notificationService = NotificationService();

  static void _showSnackBar(String message, Color backgroundColor) {
    // التحقق من أن التطبيق نشط ومتاح
    if (navigatorKey.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey.currentContext!);

      // التحقق من أن ScaffoldMessenger متاح
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

  // دالة للتحقق من حالة التطبيق قبل عرض الرسائل
  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      print('FCM Message: $message');
    }
    
    // محاولة عرض SnackBar مع معالجة الأخطاء
    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  // دالة للتحقق من حالة التطبيق قبل عرض الرسائل (Static version)
  static void _safeShowMessageStatic(String message, {Color? color}) {
    if (kDebugMode) {
      print('FCM Message: $message');
    }
    
    // محاولة عرض SnackBar مع معالجة الأخطاء
    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  // دالة للحصول على user_id من التخزين الآمن
  Future<String?> _getUserId() async {
    try {
      return await _storage.read(key: 'user_id');
    } catch (e) {
      print('خطأ في الحصول على user_id: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> init() async {
    try {
      // طلب الأذونات أولاً
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('تم منح أذونات الإشعارات');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('تم منح أذونات مؤقتة للإشعارات');
      } else {
        print('لم يتم منح أذونات الإشعارات');
        return {
          'fcmToken': null,
          'message': 'لم يتم منح أذونات الإشعارات',
        };
      }

      // الحصول على FCM token
      final fcmToken = await getAccessToken();
      if (fcmToken != null) {
        _safeShowMessage("تم الحصول على FCM Token بنجاح", color: Colors.green);
        await _storage.write(key: 'fcmToken', value: fcmToken);
      } else {
        _safeShowMessage("فشل في الحصول على FCM Token", color: Colors.red);
        return {
          'fcmToken': null,
          'message': 'فشل في الحصول على FCM Token',
        };
      }

      // إرسال التوكن إلى الباكند
      String message = await sendFcmTokenToBackend();

      // الاشتراك في موضوع المستخدم باستخدام user_id المخزن
      if (!kIsWeb) {
        final userId = await _getUserId();
        if (userId != null) {
          await subscribeToTopic('user_$userId');
        } else {
          print('لم يتم العثور على user_id في التخزين الآمن');
          _safeShowMessage('لم يتم العثور على معرف المستخدم', color: Colors.orange);
        }
      } else {
        print('الاشتراك في المواضيع غير مدعوم في منصة الويب');
      }

      // إعداد معالجات الرسائل
      await _setupMessageHandlers();

      return {
        'fcmToken': fcmToken,
        'message': message,
      };
    } catch (e) {
      _safeShowMessage('فشل في تهيئة FCM: $e', color: Colors.red);
      return {
        'fcmToken': null,
        'message': 'فشل في تهيئة FCM: $e',
      };
    }
  }

  Future<String?> getAccessToken() async {
    try {
      // في حالة الويب، استخدم Firebase token مباشرة
      if (kIsWeb) {
        return await _firebaseMessaging.getToken(
          vapidKey: 'your-vapid-key-here', // يجب إضافة VAPID key للويب
        );
      }

      // للمنصات الأخرى، استخدم Service Account
      final jsonString = await rootBundle.loadString(
        'assets/flex-reminders-app-7e58d9767343.json',
      );

      final accountCredentials = auth.ServiceAccountCredentials.fromJson(jsonString);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
      _safeShowMessage(client.credentials.accessToken.data, color: Colors.green);
     // print('تم الحصول على Access Token: ${client.credentials.accessToken.data}')
      return client.credentials.accessToken.data;
    } catch (e) {
      print('خطأ في الحصول على Access Token: $e');
      // محاولة الحصول على التوكن بطريقة بديلة
      try {
        return await _firebaseMessaging.getToken();
      } catch (fallbackError) {
        print('خطأ في الحصول على التوكن البديل: $fallbackError');
        return null;
      }
    }
  }

  // إعداد معالجات الرسائل
 Future<void> _setupMessageHandlers() async {
  final userId = await _getUserId();
  final userTopic = userId != null ? 'user_$userId' : 'unknown_user';
  
  // 1. معالج الرسائل عند فتح التطبيق (Foreground)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('تم استلام رسالة أثناء تشغيل التطبيق: ${message.messageId}');
    print('الموضوع المستهدف: $userTopic');
    print('بيانات الرسالة: ${message.data}');
    
    // التحقق من أن الرسالة مرسلة للموضوع الصحيح
    if (message.data.containsKey('topic') && message.data['topic'] == userTopic) {
      print('تم استلام رسالة من الموضوع الصحيح: ${message.data['topic']}');
    }
    
    // معالجة الرسالة في المقدمة (نفس منطق الخلفية)
    _handleForegroundMessage(message);
    
    // إظهار رسالة تأكيد للمستخدم
    _safeShowMessage('تم استلام رسالة جديدة من الموضوع: $userTopic', color: Colors.green);
  });

  // 2. معالج الرسائل عند النقر على الإشعار
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('تم فتح التطبيق من خلال الإشعار: ${message.messageId}');
    print('الموضوع: $userTopic');
    print('بيانات الرسالة: ${message.data}');
    
    // معالجة الرسالة عند فتح التطبيق
    _handleOpenedAppMessage(message);
  });

  // 3. معالجة الرسائل المؤجلة (عند فتح التطبيق لأول مرة)
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('تم فتح التطبيق من رسالة مؤجلة: ${initialMessage.messageId}');
    _handleOpenedAppMessage(initialMessage);
  }
  
  // ملاحظة: Background Handler يتم تسجيله في main.dart
}

// معالج الرسائل في المقدمة
void _handleForegroundMessage(RemoteMessage message) {
  // عرض الإشعار داخل التطبيق
 // معالجة البيانات (نفس منطق الخلفية)
  _processMessageData(message);
}

// معالج فتح التطبيق من الإشعار
void _handleOpenedAppMessage(RemoteMessage message) {
  // معالجة البيانات
  _processMessageData(message);
  
  // يمكنك إضافة منطق التنقل هنا
  if (message.data.containsKey('route')) {
    // Navigator.pushNamed(navigatorKey.currentContext!, message.data['route']);
  }
}

// معالج البيانات الموحد
void _processMessageData(RemoteMessage message) {
  try {
    final String title = message.data['title'] ?? message.notification?.title ?? '';
    final String body = message.data['body'] ?? message.notification?.body ?? '';
    
    if (title.isEmpty || body.isEmpty) {
      print('بيانات الرسالة غير مكتملة');
      return;
    }
    
    int? reminderId;
    try {
      reminderId = int.parse(body);
    } catch (e) {
      print('خطأ في تحويل body إلى رقم: $e');
      return;
    }
    
    if (reminderId == null) {
      print('معرف التذكير غير صحيح');
      return;
    }
    
    _safeShowMessage('Foreground: معالجة العملية $title للتذكير $reminderId');
    
    // إنشاء instance من RemindersNotifier
    final remindersNotifier = RemindersNotifier();
    
    // معالجة الرسالة حسب النوع
    switch (title.toLowerCase()) {
      case 'reschedule':
        _handleReschedule(remindersNotifier, reminderId);
        break;
      case 'update':
        _handleUpdate(remindersNotifier, reminderId);
        break;
      case 'new':
        _handleNew(remindersNotifier, reminderId);
        break;
      case 'delete':
        _handleDelete(remindersNotifier, reminderId);
        break;
      case 'markasread':
        _handleMarkAsRead(remindersNotifier, reminderId);
        break;
      default:
        print('نوع العملية غير مدعوم: $title');
    }
  } catch (e) {
    print('خطأ في معالجة البيانات: $e');
  }
}
  // معالجة عملية إعادة الجدولة
static Future<void> _handleReschedule(RemindersNotifier notifier,
      int reminderId) async {
    try {
      print('معالجة إعادة جدولة التذكير: $reminderId');

      // تحديث التذكير من السيرفر
      await notifier.updateSingleReminder(reminderId);

      // إظهار رسالة للمستخدم
      _safeShowMessageStatic('تم إعادة جدولة التذكير - تم تحديث موعد التذكير رقم $reminderId', color: Colors.green);

      print('تم إعادة جدولة التذكير $reminderId بنجاح');
    } catch (e) {
      print('خطأ في معالجة إعادة الجدولة: $e');

      // إظهار رسالة خطأ
      _safeShowMessageStatic('خطأ في إعادة الجدولة - فشل في إعادة جدولة التذكير رقم $reminderId', color: Colors.red);
    }
  }

  // معالجة عملية التحديث
  // معالجة عملية التحديث
static Future<void> _handleUpdate(RemindersNotifier notifier, int reminderId) async {

    print('معالجة تحديث التذكير: $reminderId');
    
    // إنشاء instance جديد من ApiService داخل الدالة الثابتة
    final apiService = ApiService();
    
    // جلب التذكير المحدث من السيرفر
    final updatedReminder = await apiService.getReminderById(reminderId);
    _safeShowMessageStatic(updatedReminder.id.toString());
    
    // تحديث التذكير من السيرفر
    await notifier.updateSingleReminder(reminderId);

    // إظهار رسالة للمستخدم
    _safeShowMessageStatic('تم تحديث التذكير - تم تحديث التذكير رقم $reminderId', color: Colors.green);

    print('تم تحديث التذكير $reminderId بنجاح');
 
}
  // معالجة التذكير الجديد
static Future<void> _handleNew(RemindersNotifier notifier, int reminderId) async {
    try {
      print('معالجة تذكير جديد: $reminderId');

      // تحديث التذكير من السيرفر (سيتم إضافته للقائمة المناسبة)
      await notifier.updateSingleReminder(reminderId);

      // جلب التذكير لعرض العنوان في الإشعار
      final reminder = await notifier.getReminderById(reminderId);

      if (reminder != null) {
        // إظهار رسالة للمستخدم
        _safeShowMessageStatic('تذكير جديد - ${reminder.title.isNotEmpty ? reminder.title : 'تم إضافة تذكير جديد'}', color: Colors.blue);

        print('تم معالجة التذكير الجديد $reminderId بنجاح');
      } else {
        print('فشل في جلب التذكير الجديد $reminderId');

        // إظهار رسالة عامة
        _safeShowMessageStatic('تذكير جديد - تم إضافة تذكير جديد رقم $reminderId', color: Colors.blue);
      }
    } catch (e) {
      print('خطأ في معالجة التذكير الجديد: $e');

      // إظهار رسالة خطأ
      _safeShowMessageStatic('خطأ في التذكير الجديد - فشل في معالجة التذكير الجديد رقم $reminderId', color: Colors.red);
    }
  }

  // معالجة حذف التذكير
static Future<void> _handleDelete(RemindersNotifier notifier, int reminderId) async {
    try {
      print('معالجة حذف التذكير: $reminderId');

      // حذف التذكير من القوائم المحلية والتخزين المؤقت
      await notifier.deleteReminderLocally(reminderId);

      // إظهار رسالة للمستخدم
      _safeShowMessageStatic('تم حذف التذكير - تم حذف التذكير رقم $reminderId', color: Colors.orange);

      print('تم حذف التذكير $reminderId بنجاح');
    } catch (e) {
      print('خطأ في معالجة حذف التذكير: $e');

      // إظهار رسالة خطأ
      _safeShowMessageStatic('خطأ في الحذف - فشل في حذف التذكير رقم $reminderId', color: Colors.red);
    }
  }

  // معالجة تحديد التذكير كمقروء
  static Future<void> _handleMarkAsRead(RemindersNotifier notifier, int reminderId) async {
    try {
      print('معالجة تحديد التذكير كمقروء: $reminderId');

      // تحديث التذكير من السيرفر (سيتم نقله للقائمة المقروءة)
      await notifier.updateSingleReminder(reminderId);

      // إظهار رسالة للمستخدم
      _safeShowMessageStatic('تم تحديد التذكير كمقروء - تم تحديد التذكير رقم $reminderId كمقروء', color: Colors.green);

      print('تم تحديد التذكير $reminderId كمقروء بنجاح');
    } catch (e) {
      print('خطأ في معالجة تحديد التذكير كمقروء: $e');

      // إظهار رسالة خطأ
      _safeShowMessageStatic('خطأ في التحديد كمقروء - فشل في تحديد التذكير رقم $reminderId كمقروء', color: Colors.red);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    // التحقق من أن المنصة تدعم الاشتراك في المواضيع
    if (kIsWeb) {
      print('الاشتراك في المواضيع غير مدعوم في منصة الويب');
      _safeShowMessage('الاشتراك في المواضيع غير مدعوم في منصة الويب', color: Colors.orange);
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
      _safeShowMessage('إلغاء الاشتراك من المواضيع غير مدعوم في منصة الويب', color: Colors.orange);
      return;
    }

    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      _safeShowMessage('تم إلغاء الاشتراك من الموضوع: $topic', color: Colors.orange);
    } catch (e) {
      _safeShowMessage('خطأ في إلغاء الاشتراك من الموضوع: $e', color: Colors.red);
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
        body: jsonEncode({'token': fcmToken,'topic': 'user_$userId','user_id':userId,'platform':'mobile_app'}),
      );

      if (response.statusCode == 200) {
        const message = 'تم إرسال التوكن إلى الخادم بنجاح';
        _safeShowMessage(message, color: Colors.green);
        return message;
      } else {
        final message = 'فشل في إرسال التوكن إلى الخادم: ${response.statusCode}';
        _safeShowMessage(message, color: Colors.red);
        return message;
      }
    } catch (e) {
      final message = 'خطأ في إرسال التوكن إلى الخادم: $e';
      _safeShowMessage(message, color: Colors.red);
      return message;
    }
  }

  // دالة للتحقق من حالة التوكن
  Future<bool> isTokenValid() async {
    final token = await _storage.read(key: 'auth_token');
    return token != null && token.isNotEmpty;
  }

  // دالة لإعادة الاشتراك في موضوع المستخدم (مفيدة عند تحديث التطبيق)
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

  // دالة للتحقق من حالة الاشتراك
  Future<String?> getCurrentUserTopic() async {
    final userId = await _getUserId();
    return userId != null ? 'user_$userId' : null;
  }

  // دالة لتحديث FCM token
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

  // دالة لتسجيل الخروج وإلغاء التوكن
  Future<void> logout() async {
    try {
      // إلغاء الاشتراك من جميع المواضيع باستخدام user_id المخزن
      if (!kIsWeb) {
        final userId = await _getUserId();
        if (userId != null) {
          await unsubscribeFromTopic('user_$userId');
        }
      }
      
      // حذف التوكن من التخزين المحلي
      await _storage.delete(key: 'fcmToken');
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_id');
      
      print('تم تسجيل الخروج وإلغاء FCM Token');
    } catch (e) {
      print('خطأ في تسجيل الخروج: $e');
    }
  }
}