import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/consts.dart';
import 'package:flex_reminder/services/reminders_service.dart';
import 'package:flex_reminder/services/subscription_manager.dart';

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

  // 🔍 FCM Debug Mode - Set to true for detailed logging
  static bool debugMode = true;

  // إضافة متغير لتتبع التهيئة
  bool _isInitialized = false;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();

  final NotificationService _notificationService = NotificationService();
  // متغيرات تتبع حالة التطبيق والرسائل
  static bool _isAppInForeground = true;
  static final Set<String> _processedMessages = <String>{};
  static final Map<int, DateTime> _lastProcessedTime = <int, DateTime>{};

  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  // دالة للتحقق من حالة التهيئة
  bool get isInitialized => _isInitialized;

  // Method channels for communication with native code
  static const MethodChannel _deeplinkChannel = MethodChannel('com.saadmohammed2000.flex_reminder/deeplink');

  // متغير لتحديد ما إذا كنا في وضع الخلفية
  bool _isBackgroundMode = false;
  
  void setBackgroundMode(bool value) {
    _isBackgroundMode = value;
  }

  // ✅ دالة محسّنة لعرض الرسائل - تم تحديثها حسب التعديلات
  void _safeShowMessage(String message, {Color? color, bool debugOnly = false, bool force = false}) {
    // 1. طباعة في console دائماً
    // if (kDebugMode) {
    //   debugPrint('🔵 FCM${_isBackgroundMode ? " [BG]" : ""}: $message');
    // }

    // // 2. عرض SnackBar فقط إذا لم نكن في الخلفية
    // if (!debugOnly && !_isBackgroundMode) {
    //   // استخدام showGlobalSnackBar من globals.dart
    //   try {
    //     showGlobalSnackBar(
    //       message,
    //       backgroundColor: color ?? Colors.blue,
    //       duration: const Duration(milliseconds: 1500),
    //     );
    //   } catch (e) {
    //     debugPrint('⚠️ Ignored SnackBar error in FCM (likely background): $e');
    //   }
    // }
  }

  // ✅ استبدل _showSnackBar القديمة بهذه - تم تحديثها حسب التعديلات
  void _showSnackBar(String message, Color backgroundColor) {
    if (kDebugMode) {
      debugPrint('🔵 FCM: $message');
    }
    
    // استخدام النظام العام
    showGlobalSnackBar(
      message,
      backgroundColor: backgroundColor,
      duration: const Duration(milliseconds: 1500),
    );
  }

  // 🔍 FCM Debug Logger - Detailed logging for troubleshooting
  void _fcmDebugLog(String stage, String message, {Map<String, dynamic>? data}) {
    if (!debugMode) return;
    
    final timestamp = DateTime.now().toIso8601String();
    print('🔍 [$timestamp] FCM-$stage: $message');
    if (data != null) {
      try {
        print('   📦 Data: ${jsonEncode(data)}');
      } catch (e) {
        print('   📦 Data: ${data.toString()}');
      }
    }
  }

  // 🏥 FCM Health Check - Diagnose FCM configuration and status
  Future<void> performFCMHealthCheck() async {
    print('\n🏥 ========== FCM HEALTH CHECK ==========');
    
    try {
      final firebaseApps = Firebase.apps.length;
      print('   ✓ Firebase Apps: $firebaseApps');
      
      final fcmInitialized = _isInitialized;
      print('   ${fcmInitialized ? "✓" : "✗"} FCM Initialized: $fcmInitialized');
      
      final token = await getAccessToken();
      print('   ${token != null ? "✓" : "✗"} FCM Token: ${token != null ? "${token.substring(0, 20)}..." : "null"}');
      
      final settings = await _firebaseMessaging.getNotificationSettings();
      print('   ${settings.authorizationStatus == AuthorizationStatus.authorized ? "✓" : "✗"} Permission Status: ${settings.authorizationStatus}');
      
      print('   ✓ Permissions Granted: $_permissionsGranted');
      print('   ✓ Debug Mode: $debugMode');
      print('   ✓ Processed Messages Count: ${_processedMessages.length}');
      
      if (_processedMessages.isNotEmpty) {
        print('   📋 Last 3 processed message IDs:');
        _processedMessages.take(3).forEach((msgId) => print('      - $msgId'));
      }
      
    } catch (e) {
      print('   ✗ Health check error: $e');
    }
    
    print('========================================\n');
  }


  // ✅ تحديث requestAllPermissions لتقليل الرسائل
  Future<bool> requestAllPermissions() async {
    try {
      debugPrint('🔐 طلب الأذونات...');
      
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      debugPrint('📱 حالة الإذن: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        await showErrorSnackBar('تم رفض إذن الإشعارات');
        return false;
      }

      if (!kIsWeb) {
        // طلب الأذونات الأخرى بصمت
        await Permission.notification.request();
        await Permission.ignoreBatteryOptimizations.request();
        await Permission.scheduleExactAlarm.request();
        
        _permissionsGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
      } else {
        _permissionsGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
      }

      // رسالة واحدة فقط للنتيجة النهائية
      if (_permissionsGranted) {
        await showSuccessSnackBar('تم منح الأذونات');
      }

      return _permissionsGranted;
     } catch (e) {
      debugPrint('❌ خطأ في الأذونات: $e');
      await showErrorSnackBar('خطأ في الأذونات');
      return false;
    }
  }

  Future<Map<String, dynamic>> init() async {
    if (_isInitialized) {
      debugPrint('✅ FCM already initialized');
      final fcmToken = await _storage.read(key: AppConstants.FCM_TOKEN_KEY);
      return {
        'fcmToken': fcmToken,
        'message': 'Already initialized',
        'permissionsGranted': _permissionsGranted,
      };
    }

    try {
      // ✅ ضبط وضع Debug في بداية التهيئة
      setDebugMode(debugMode);
      
      debugPrint('🔄 Starting FCM initialization...');
      
      // التحقق من Firebase
      if (Firebase.apps.isEmpty) {
        debugPrint('❌ Firebase not initialized');
        return {
          'fcmToken': null,
          'message': 'Firebase not initialized',
          'permissionsGranted': false,
        };
      }
      
      // طلب الأذونات
      final permissionsGranted = await requestAllPermissions();
      if (!permissionsGranted) {
        debugPrint('⚠️ Permissions not granted');
      }
      
      // الحصول على FCM Token
      final fcmToken = await getAccessToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _storage.write(key: AppConstants.FCM_TOKEN_KEY, value: fcmToken);
        debugPrint('✅ FCM Token saved: ${fcmToken.substring(0, 20)}...');
      } else {
        debugPrint('⚠️ Failed to get FCM token');
      }
      
      // إعداد معالجات الرسائل
      await setupMessageHandlers();
      _setupAppLifecycleListener();
      
      // إرسال Token للباك إند (لا تفشل التهيئة إذا فشل)
      try {
        if (fcmToken != null) {
     //     await sendFcmTokenToBackend();
        }
      } catch (e) {
        debugPrint('⚠️ Failed to send token to backend: $e');
      }

      // الاشتراك في المواضيع
      if (!kIsWeb) {
        try {
          final userId = await _getUserId();
          if (userId != null) {
            await subscribeToTopic('user_$userId');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to subscribe to topic: $e');
        }
      }

      _isInitialized = true;
      // ✅ استخدام الدوال المساعدة من globals.dart
      await showSuccessSnackBar('FCM جاهز');

      return {
        'fcmToken': fcmToken,
        'message': 'Success',
        'permissionsGranted': permissionsGranted,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ FCM init failed: $e');
      debugPrint('Stack trace: $stackTrace');
      // ✅ استخدام دالة الخطأ
      await showErrorSnackBar('فشل تهيئة FCM');
      return {
        'fcmToken': null,
        'message': 'Failed: $e',
        'permissionsGranted': false,
      };
    }
  }
// داخل FcmService
Future<void> handleBackgroundData(Map<String, dynamic> data) async {
  final type = data['type'];

  switch (type) {
    case 'reminder_update':
      await RemindersService.instance
          .handleReminderUpdateInBackground(data);
      break;

    case 'subscription_update':
      await SubscriptionManager()
          .handleSubscriptionUpdateNotification(data);
      break;
  }
}

Future<void> processMessage(RemoteMessage message) async {
  final data = Map<String, dynamic>.from(message.data);
 
  final type = data['type']?.toString();
  showSuccessSnackBar('type: $type');
  if (type == null) {
 //   showSuccessSnackBar('❌ type is NULL');
    return;
  }

  switch (type) {
    case 'reminder_update':
      showSuccessSnackBar('🔔 reminder_update');
      await RemindersNotifier.instance.handleFcmData(data);
      break;

    case 'subscription_update':
      showSuccessSnackBar('💳 subscription_update');
      await SubscriptionManager()
          .handleSubscriptionUpdateNotification(data);
      break;

    default:
   //   showSuccessSnackBar('⚠️ Unknown type: $type');
  }

  debugPrint('✅ processMessage FINISHED');
}


void _showSubscriptionUpdateNotification(String userId, String eventType, String status) {
  String title = "User: $userId";
  String body = "Event: $eventType";
  
  // إضافة وصف للحدث
 String eventDescription = SubscriptionManager().getEventDescription(eventType);
  if (eventDescription.isNotEmpty) {
    body += "\n$eventDescription";
  }
  
  // إضافة الحالة
  body += "\nStatus: $status";
  
  _showFcmNotificationSnackBar(title, body);
}

// دالة جديدة لعرض إشعار مفصل
void _showDetailedSubscriptionNotification(String userId, String eventType, String status) {
  String title = "User: $userId";
  String body = "Event: $eventType";
  
  // إضافة وصف للحدث
  String eventDescription = _getEventDescription(eventType);
  if (eventDescription.isNotEmpty) {
    body += "\n$eventDescription";
  }
  
  // إضافة الحالة
  body += "\nStatus: $status";
  
  _showFcmNotificationSnackBar(title, body);
}

// دالة مساعدة لوصف الأحداث
String _getEventDescription(String eventType) {
  switch (eventType) {
    case 'INITIAL_PURCHASE':
      return 'تم تفعيل اشتراك جديد';
    case 'RENEWAL':
      return 'تم تجديد الاشتراك';
    case 'CANCELLATION':
      return 'تم إلغاء الاشتراك';
    case 'UNCANCELLATION':
      return 'تم استعادة الاشتراك';
    case 'EXPIRATION':
      return 'انتهت صلاحية الاشتراك';
    case 'BILLING_ISSUE':
      return 'مشكلة في الدفع';
    case 'PRODUCT_CHANGE':
      return 'تم تغيير خطة الاشتراك';
    default:
      return 'تحديث في الاشتراك';
  }
}
  // ✅ دالة عرض إشعارات FCM (تبقى static) - تم تحديثها حسب التعديلات
  static void _showFcmNotificationSnackBar(String title, String body) {
    if (title.isEmpty && body.isEmpty) return;
    final msg = title.isNotEmpty ? '$title${body.isNotEmpty ? ': $body' : ''}' : body;
    
    // استخدام النظام العام من globals.dart
    showInfoSnackBar(msg); // أو showGlobalSnackBar('🔔 $msg', ...)
  }

  // الدوال المساعدة الأخرى تبقى كما هي...
  static bool _isDuplicateMessage(String messageId) {
    if (_processedMessages.contains(messageId)) {
      print('رسالة مكررة تم تجاهلها: $messageId');
      return true;
    }

    _processedMessages.add(messageId);

    if (_processedMessages.length > AppConstants.MAX_PROCESSED_MESSAGES) {
      final oldMessages = _processedMessages.take(
          _processedMessages.length - AppConstants.MAX_PROCESSED_MESSAGES);
      _processedMessages.removeAll(oldMessages);
    }

    return false;
  }

  static bool _shouldProcessReminder(int reminderId) {
    final now = DateTime.now();
    final lastProcessed = _lastProcessedTime[reminderId];

    if (lastProcessed != null &&
        now.difference(lastProcessed) < AppConstants.PROCESS_DELAY) {
      print('تم تأخير معالجة التذكير $reminderId لتجنب التكرار');
      return false;
    }

    _lastProcessedTime[reminderId] = now;

    _lastProcessedTime.removeWhere((key, value) =>
        now.difference(value) > AppConstants.LAST_PROCESSED_CLEANUP_DURATION);

    return true;
  }


  // ============================================================================
  // الحل 2: تحسين _processReminderOperation مع معالجة أفضل للأخطاء
  // ============================================================================
  Future<void> _processReminderOperation(
  String action, int reminderId, Map<String, dynamic> data) async {
  try {
    debugPrint('🔵 [_processReminderOperation] === STARTED ===');
    debugPrint('🔵 [_processReminderOperation] action="$action", reminderId=$reminderId');
    
    final isInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    
    if (isInForeground) {
      await showInfoSnackBar('معالجة: $action');
    }
    
    // استدعاء RemindersNotifier بدون isBackground
    await RemindersNotifier.instance.handleFcmData(data);
    
    debugPrint('🔵 [_processReminderOperation] handleFcmData completed');
    
    if (isInForeground) {
      await showSuccessSnackBar('تمت معالجة التذكير');
    }
  } catch (e, s) {
    debugPrint('🔴 [_processReminderOperation] ERROR: $e');
    
    final isInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (isInForeground) {
      await showErrorSnackBar('خطأ في معالجة التذكير');
    }
    
    print('❌ Error: $e\n$s');
    
    // إرسال إشعار احتياطي في الخلفية
    if (!isInForeground) {
      try {
       
      } catch (_) {}
    }
  }
}
  

  // ============================================================================
  // الحل 4: تحسين _sendGenericNotification مع retry logic
  // ============================================================================

  Future<void> _sendGenericNotification(
      String title, String body, Map<String, dynamic> data) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        _safeShowMessage('📢 Sending notification (attempt ${retryCount + 1})', color: Colors.blue);

        await NotificationService.instance.scheduleNotification(
          title: title,
          body: body,
          scheduledDate: DateTime.now().add(const Duration(seconds: 2)),
          channelKey: AppConstants.SCHEDULED_CHANNEL_KEY,
          payload: data.cast<String, String>(),
        );

        _safeShowMessage('✅ Notification sent successfully', color: Colors.green);
        return; // نجحت العملية، خروج من الدالة
        
      } catch (e) {
        retryCount++;
        _safeShowMessage(
          '❌ Notification attempt $retryCount failed: $e', 
          color: Colors.orange
        );
        
        if (retryCount >= maxRetries) {
          _safeShowMessage('❌ All notification attempts failed', color: Colors.red);
          throw e;
        }
        
        // انتظار قبل المحاولة التالية
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
  }

  // ============================================================================
  // الحل 5: إضافة دالة للتحقق من جاهزية النظام
  // ============================================================================

  Future<bool> _isSystemReady() async {
    try {
      // التحقق من التهيئة
      if (!_isInitialized) {
        _safeShowMessage('⚠️ FCM not initialized', color: Colors.orange);
        return false;
      }

      // التحقق من RemindersNotifier
      if (RemindersNotifier.instance == null) {
        _safeShowMessage('⚠️ RemindersNotifier not available', color: Colors.orange);
        return false;
      }

      // التحقق من تسجيل الدخول
      final userId = await _storage.read(key: AppConstants.USER_ID_KEY);
      if (userId == null) {
        _safeShowMessage('⚠️ User not logged in', color: Colors.orange);
        return false;
      }

      // التحقق من NotificationService
      try {
        await NotificationService.instance.init();
      } catch (e) {
        _safeShowMessage('⚠️ NotificationService init failed: $e', color: Colors.orange);
        return false;
      }

      return true;
    } catch (e) {
      _safeShowMessage('❌ System readiness check failed: $e', color: Colors.red);
      return false;
    }
  }

  Future<String?> _getUserId() async {
    try {
      return await _storage.read(key: AppConstants.USER_ID_KEY);
    } catch (e) {
      print('خطأ في الحصول على user_id: $e');
      return null;
    }
  }

  void _handleNavigationLogic(RemoteMessage message, String userTopic) {
    try {
      // ✅ قراءة جميع البيانات من data
      final data = Map<String, dynamic>.from(message.data);
      final postId = data['post_id']?.toString() ?? '';
      final action = data['action']?.toString().trim() ?? '';
      final postTitle = data['post_title']?.toString().trim() ?? 
                       data['title']?.toString().trim() ?? '';
      final postUrl = data['post_url']?.toString().trim() ?? '';
      
      final title = postTitle.isNotEmpty ? postTitle : 'تذكير';
      final body = data['body']?.toString() ?? data['next_reminder_time']?.toString() ?? '';

      _showSnackBar('🔗 Handling navigation: $action', Colors.blue);
      _safeShowMessage('Post ID: $postId, Action: $action', color: Colors.blue);
      _safeShowMessage('Title: $title, Body: $body', color: Colors.blue);
      _safeShowMessage('URL: $postUrl', color: Colors.blue);
      _safeShowMessage('Topic: $userTopic', color: Colors.blue);

      switch (action.toLowerCase().trim()) {
        case 'reminder_updated':
          _showSnackBar('🔄 التنقل إلى صفحة التذكير المحدث', Colors.blue);
          if (postUrl.isNotEmpty) {
            _showSnackBar('فتح الرابط: $postUrl', Colors.blue);
          }
          break;
        case 'reschedule':
          _showSnackBar('🔄 التنقل إلى صفحة إعادة الجدولة', Colors.blue);
          break;
        case 'update':
          _showSnackBar('✏️ التنقل إلى صفحة تحديث التذكير', Colors.blue);
          break;
        case 'new':
          _showSnackBar('🆕 التنقل إلى صفحة التذكيرات الجديدة', Colors.blue);
          break;
        case 'markas_read':
        case 'mark_as_read':
          _showSnackBar('✅ التنقل إلى صفحة التذكيرات المقروءة', Colors.blue);
          break;
        case 'delete':
          _showSnackBar('🗑️ التنقل إلى الصفحة الرئيسية', Colors.blue);
          break;
        default:
          _showSnackBar('📱 التنقل العام للإشعار', Colors.blue);
      }
    } catch (e) {
      _safeShowMessage('❌ خطأ في معالجة منطق التنقل: $e', color: Colors.red);
    }
  }

  /// الحصول على FCM Token
  Future<String?> getAccessToken() async {
    try {
      debugPrint('🔑 Getting FCM token...');
      
      if (kIsWeb) {
        final token = await _firebaseMessaging.getToken(
          vapidKey: 'your-vapid-key-here',
        );
        debugPrint('✅ Web FCM token obtained');
        return token;
      }
      
      // للتطبيقات الأصلية (Android/iOS)
      final token = await _firebaseMessaging.getToken();
      
      if (token != null && token.isNotEmpty) {
        debugPrint('✅ FCM token obtained: ${token.substring(0, 20)}...');
        return token;
      } else {
        debugPrint('⚠️ FCM token is null or empty');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting FCM token: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<String> sendFcmTokenToBackend() async {
    try {
      String? token = await _storage.read(key: AppConstants.AUTH_TOKEN_KEY);
      String? fcmToken = await _storage.read(key: AppConstants.FCM_TOKEN_KEY);
      String? userId = await _storage.read(key: AppConstants.USER_ID_KEY);

      final response = await http.post(
        Uri.parse('${AppConstants.API_BASE_URL}/fcm/subscribe'),
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
        _showSnackBar(message, Colors.green);
        return message;
      } else {
        final message =
            'فشل في إرسال التوكن إلى الخادم: ${response.statusCode}';
        _safeShowMessage(message, color: Colors.red);
        _showSnackBar(message, Colors.red);
        return message;
      }
    } catch (e) {
      final message = 'خطأ في إرسال التوكن إلى الخادم: $e';
      _safeShowMessage(message, color: Colors.red);
      _showSnackBar(message, Colors.red);
      return message;
    }
  }

  // ✅ نقل setupMessageHandlers إلى FcmService وجعلها public
Future<void> setupMessageHandlers() async {
  _fcmDebugLog('SETUP', 'Starting message handlers setup...');
  
  if (Firebase.apps.isEmpty) {
    await showWarningSnackBar('Firebase غير مهيأ');
    _fcmDebugLog('SETUP', 'FAILED - Firebase not initialized');
    return;
  }

  try {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
 
        await processMessage(message); // ✅ بدون isBackground

         showSuccessSnackBar('تمت المعالجة');
        //showSuccessSnackBar(message.data['type']);
    
    }, onError: (error) {
      _fcmDebugLog('FOREGROUND', '❌ Stream error: $error');
      _safeShowMessage('❌ Stream error: $error', color: Colors.red);
    });

    _fcmDebugLog('SETUP', '✓ onMessage listener registered');

    // معالج فتح التطبيق من إشعار
    _fcmDebugLog('SETUP', 'Registering onMessageOpenedApp listener...');
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _fcmDebugLog('OPENED_APP', '📱 App opened from notification', data: message.data);
      _safeShowMessage('📱 App opened from notification', color: Colors.blue);
      
      try {
        _handleMessageOpenedAppNavigation(message);
        _fcmDebugLog('OPENED_APP', '✓ Navigation handled');
      } catch (e) {
        _fcmDebugLog('OPENED_APP', '❌ Error: $e');
        _safeShowMessage('❌ Error handling opened app: $e', color: Colors.red);
      }
    });

    _fcmDebugLog('SETUP', '✓ onMessageOpenedApp listener registered');

    // معالج الرسالة الأولية
    _fcmDebugLog('SETUP', 'Checking for initial message...');
    FirebaseMessaging.instance.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        _fcmDebugLog('INITIAL', '📬 Initial message found', data: initialMessage.data);
        _safeShowMessage('📬 Initial message', color: Colors.blue);
        
        Future.delayed(const Duration(seconds: 2), () {
          try {
            _handleMessageOpenedAppNavigation(initialMessage);
            _fcmDebugLog('INITIAL', '✓ Navigation handled');
          } catch (e) {
            _fcmDebugLog('INITIAL', '❌ Error: $e');
            _safeShowMessage('❌ Error handling initial message: $e', color: Colors.red);
          }
        });
      } else {
        _fcmDebugLog('INITIAL', 'No initial message found');
      }
    });

    _fcmDebugLog('SETUP', '✓ All listeners registered successfully');
    await showSuccessSnackBar('تم تكوين معالجات الرسائل');
    
  } catch (e, stackTrace) {
    _fcmDebugLog('SETUP', '❌ Setup error: $e');
    print('🔴 Error: $e\nStack: $stackTrace');
    await showErrorSnackBar('خطأ في الإعداد');
  }
}

// ✅ دالة مساعدة للتنقل
void _handleMessageOpenedAppNavigation(RemoteMessage message) {
  try {
    final data = Map<String, dynamic>.from(message.data);
    final postId = data['post_id']?.toString() ?? '';
    final action = data['action']?.toString().trim() ?? '';
    final postUrl = data['post_url']?.toString().trim() ?? '';
    
    final int? reminderId = postId.isNotEmpty ? int.tryParse(postId) : null;
    
    Future.delayed(const Duration(milliseconds: 800), () {
      if (reminderId != null) {
        switch (action.toLowerCase().trim()) {
          case 'reminder_updated':
          case 'update':
          case 'reschedule':
          case 'new':
          case 'markas_read':
          case 'mark_as_read':
            navigatorKey.currentState?.pushNamed(
              '/reminder',
              arguments: {'reminderId': reminderId},
            );
            break;
          case 'delete':
            navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/reminders',
              (route) => false,
            );
            break;
          default:
            if (postUrl.isNotEmpty) {
              navigatorKey.currentState?.pushNamed(
                '/reminder',
                arguments: {'reminderId': reminderId},
              );
            } else {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/reminders',
                (route) => false,
              );
            }
        }
      } else {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/reminders',
          (route) => false,
        );
      }
    });
    
  } catch (e) {
    _safeShowMessage('❌ Error in navigation: $e', color: Colors.red);
  }
}

  void _setupAppLifecycleListener() {
    _showSnackBar('🔄 App lifecycle listener set up', Colors.blue);
    _safeShowMessage('تم تعيين مراقب دورة حياة التطبيق', color: Colors.blue);
  }




  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      _safeShowMessage('الاشتراك في المواضيع غير مدعوم في منصة الويب',
          color: Colors.orange);
      return;
    }

    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      _showSnackBar('Subscribed to topic: $topic', Colors.green);
      _safeShowMessage('تم الاشتراك في الموضوع: $topic', color: Colors.blue);
    } catch (e) {
      _safeShowMessage('خطأ في الاشتراك في الموضوع: $e', color: Colors.red);
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      _safeShowMessage('إلغاء الاشتراك من المواضيع غير مدعوم في منصة الويب',
          color: Colors.orange);
      return;
    }

    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      _showSnackBar('Unsubscribed from topic: $topic', Colors.orange);
      _safeShowMessage('تم إلغاء الاشتراك من الموضوع: $topic',
          color: Colors.orange);
    } catch (e) {
      _safeShowMessage('خطأ في إلغاء الاشتراك من الموضوع: $e',
          color: Colors.red);
    }
  }

  Future<bool> isTokenValid() async {
    final token = await _storage.read(key: AppConstants.AUTH_TOKEN_KEY);
    return token != null && token.isNotEmpty;
  }

  Future<void> resubscribeToUserTopic() async {
    if (kIsWeb) {
      _safeShowMessage('إعادة الاشتراك في المواضيع غير مدعومة في منصة الويب');
      return;
    }

    try {
      final userId = await _getUserId();
      if (userId != null) {
        await subscribeToTopic('user_$userId');
        _showSnackBar('Resubscribed to user topic', Colors.green);
        _safeShowMessage('تم إعادة الاشتراك في الموضوع: user_$userId');
      } else {
        _safeShowMessage('لم يتم العثور على user_id لإعادة الاشتراك');
      }
    } catch (e) {
      _safeShowMessage('خطأ في إعادة الاشتراك في الموضوع: $e');
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
        await _storage.write(key: AppConstants.FCM_TOKEN_KEY, value: newToken);
        await sendFcmTokenToBackend();
        _showSnackBar('FCM token refreshed', Colors.green);
      }
    } catch (e) {
      _safeShowMessage('خطأ في تحديث FCM Token: $e');
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

      await _storage.delete(key: AppConstants.FCM_TOKEN_KEY);
      await _storage.delete(key: AppConstants.AUTH_TOKEN_KEY);
      await _storage.delete(key: AppConstants.USER_ID_KEY);

      _showSnackBar('Logged out successfully', Colors.green);
      _safeShowMessage('تم تسجيل الخروج وإلغاء FCM Token');
    } catch (e) {
      _safeShowMessage('خطأ في تسجيل الخروج: $e');
    }
  }

  static void resetInstance() {
    _instance = null;
  }

  // ✅ اختياري: إضافة دالة مساعدة في FcmService للتحكم في وضع Debug
  /// تفعيل/تعطيل رسائل FCM Debug
  void setDebugMode(bool enabled) {
    debugMode = enabled;
    isDebugMode = enabled; // من globals.dart
    debugPrint('🐛 FCM Debug Mode: ${enabled ? "enabled" : "disabled"}');
  }
}

// ✅ إضافة دالة للتحكم في رسائل FCM من خارج الخدمة:
// في أي مكان في التطبيق:
void toggleFcmDebug(bool enabled) {
  FcmService.instance.setDebugMode(enabled);
  
  if (enabled) {
    showInfoSnackBar('تم تفعيل وضع FCM Debug');
  } else {
    showInfoSnackBar('تم تعطيل وضع FCM Debug');
    clearSnackBarQueue(); // مسح الرسائل المتبقية
  }
}