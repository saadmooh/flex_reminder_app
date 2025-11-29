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

  // إضافة متغيرات Rate Limiting
  DateTime? _lastSnackBarTime;
  final Duration _snackBarThrottle = const Duration(milliseconds: 500);

  // إضافة متغير لتتبع التهيئة
  bool _isInitialized = false;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final _storage = const FlutterSecureStorage();
  static bool _isFirebaseInitialized = false; 
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
  static const MethodChannel _fcmChannel = MethodChannel('com.saadmohammed2000.flex_reminder/fcm');
  static const MethodChannel _deeplinkChannel = MethodChannel('com.saadmohammed2000.flex_reminder/deeplink');

  // ✅ دالة محسّنة لعرض الرسائل
  void _safeShowMessage(String message, {Color? color, bool debugOnly = false, bool force = false}) {
    // 1. طباعة في console دائماً
    if (kDebugMode) {
      debugPrint('🔵 FCM: $message');
    }

    // 2. عرض SnackBar (إذا لم يكن debugOnly فقط)
    if (!debugOnly) {
      // Rate limiting
      final now = DateTime.now();
      if (!force && _lastSnackBarTime != null && 
          now.difference(_lastSnackBarTime!) < _snackBarThrottle) {
        debugPrint('⏭️ SnackBar throttled: $message');
        return;
      }
      
      _lastSnackBarTime = now;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final currentState = scaffoldMessengerKey.currentState;
          if (currentState != null && currentState.mounted) {
            currentState.clearSnackBars();
            currentState.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: color ?? Colors.blue,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ SnackBar error: $e');
        }
      });
    }
  }

  // ✅ استبدل _showSnackBar القديمة بهذه
  void _showSnackBar(String message, Color backgroundColor) {
    _safeShowMessage(message, color: backgroundColor, debugOnly: true); // فقط للـ debug
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
        _safeShowMessage('تم رفض إذن الإشعارات', color: Colors.red, force: true);
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
        _safeShowMessage('✅ تم منح الأذونات', color: Colors.green, force: true);
      }

      return _permissionsGranted;
    } catch (e) {
      debugPrint('❌ خطأ في الأذونات: $e');
      _safeShowMessage('خطأ في الأذونات', color: Colors.red, force: true);
      return false;
    }
  }

  // ✅ تحديث init() لتقليل الرسائل
  Future<Map<String, dynamic>> init() async {
    
    if (_isInitialized) {
      debugPrint('FCM already initialized');
      final fcmToken = await _storage.read(key: AppConstants.FCM_TOKEN_KEY);
      return {
        'fcmToken': fcmToken,
        'message': 'Already initialized',
        'permissionsGranted': _permissionsGranted,
      };
    }

    try {
      // طلب الأذونات
      final permissionsGranted = await requestAllPermissions();
      
      // الحصول على Token
      final fcmToken = await getAccessToken();
      if (fcmToken != null) {
        await _storage.write(key: AppConstants.FCM_TOKEN_KEY, value: fcmToken);
        debugPrint('✅ FCM Token obtained');
      } else {
        _safeShowMessage('فشل في الحصول على Token', color: Colors.red, force: true);
        return {
          'fcmToken': null,
          'message': 'Token failed',
          'permissionsGranted': false,
        };
      }
    _isFirebaseInitialized = true; 
      // إرسال Token للباك إند
      await sendFcmTokenToBackend();

      // الاشتراك في المواضيع
      if (!kIsWeb) {
        final userId = await _getUserId();
        if (userId != null) {
          await subscribeToTopic('user_$userId');
        }
      }

      // إعداد معالجات الرسائل
      await setupMessageHandlers();
      _setupAppLifecycleListener();
      _setupMethodCallHandlers();

      _isInitialized = true;
      _safeShowMessage('✅ FCM جاهز', color: Colors.green, force: true);

      return {
        'fcmToken': fcmToken,
        'message': 'Success',
        'permissionsGranted': permissionsGranted,
      };
    } catch (e) {
      debugPrint('❌ FCM init failed: $e');
      _safeShowMessage('فشل تهيئة FCM', color: Colors.red, force: true);
      return {
        'fcmToken': null,
        'message': 'Failed: $e',
        'permissionsGranted': false,
      };
    }
  }

  // ✅ تحديث processMessage لتقليل الرسائل
  Future<void> processMessage(RemoteMessage message, {required bool isBackground}) async {
      _safeShowMessage('🔄 Processing message (background: $isBackground)');
      
    try {
    
      if (!_isInitialized) {
        debugPrint('⚠️ FCM not initialized');
        await init();
      }
      
      final data = Map<String, dynamic>.from(message.data);
      final title = data['title']?.toString() ?? data['post_title']?.toString() ?? 'تذكير';
      final body = data['body']?.toString() ?? data['next_reminder_time']?.toString() ?? '';
      final postId = data['post_id']?.toString() ?? '';
      
      debugPrint('📋 Title: $title');
      debugPrint('📋 PostID: $postId');
      
      final int? reminderId = postId.isNotEmpty ? int.tryParse(postId) : null;
      final msgId = message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
      
      // فحص التكرار
      if (_isDuplicateMessage(msgId)) {
        debugPrint('⏭️ Duplicate ignored');
        return;
      }

      // عرض إشعار في المقدمة فقط
      if (!isBackground && title.isNotEmpty) {
        _showFcmNotificationSnackBar(title, body);
      }

      // معالجة الإشعارات
      if (reminderId == null || reminderId <= 0) {
        await _handleGeneralNotification(title, body, data, isBackground);
        return;
      }

      if (!_shouldProcessReminder(reminderId)) {
        debugPrint('⏭️ Reminder delayed');
        return;
      }

      // معالجة التذكير
      await _processReminderOperation(data['action']?.toString() ?? '', reminderId, isBackground, data);
      debugPrint('✅ Message processed');
      
    } catch (e, s) {
      debugPrint('❌ Process error: $e');
      // إشعار احتياطي
      try {
        final title = message.data['post_title']?.toString() ?? 'تذكير';
        final body = message.data['next_reminder_time']?.toString() ?? '';
        await _sendGenericNotification(title, body.isNotEmpty ? 'موعد: $body' : 'تذكير', message.data);
      } catch (_) {}
    }
  }

  // ✅ دالة عرض إشعارات FCM (تبقى static)
  static void _showFcmNotificationSnackBar(String title, String body) {
    if (title.isEmpty && body.isEmpty) return;
    final msg = title.isNotEmpty ? '$title: $body' : body;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final messenger = ScaffoldMessenger.maybeOf(ctx);
      if (messenger == null) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('🔔 $msg'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
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

  void _setupMethodCallHandlers() {
    _fcmChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFcmMessageReceived':
          final Map<String, dynamic> arguments = call.arguments;
          final action = arguments['action'] as String?;
          final Map<String, String> data = Map<String, String>.from(arguments['data'] ?? {});
          
          _safeShowMessage('Received FCM message: $action', color: Colors.blue);
          _showSnackBar('FCM Message: $action', Colors.blue);
          
          await _processNativeFcmMessage(action, data);
          break;
          
        case 'onTokenRefresh':
          final String? token = call.arguments;
          if (token != null) {
            _safeShowMessage('FCM token refreshed: $token', color: Colors.blue);
            _showSnackBar('FCM Token Refreshed', Colors.blue);
            await _storage.write(key: AppConstants.FCM_TOKEN_KEY, value: token);
            await sendFcmTokenToBackend();
          }
          break;
          
        default:
          throw PlatformException(
            code: 'Unimplemented',
            details: 'Method ${call.method} is not implemented',
          );
      }
    });

    _deeplinkChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openReminderDetail':
          final int reminderId = call.arguments;
          _safeShowMessage('Opening reminder detail: $reminderId', color: Colors.blue);
          _showSnackBar('Opening Reminder: $reminderId', Colors.blue);
          
          navigatorKey.currentState?.pushNamed(
            '/reminder',
            arguments: {'reminderId': reminderId},
          );
          break;
          
        default:
          throw PlatformException(
            code: 'Unimplemented',
            details: 'Method ${call.method} is not implemented',
          );
      }
    });
  }

  Future<void> _processNativeFcmMessage(String? action, Map<String, String> data) async {
  try {
    if (action == null) return;
    
    final postId = data['post_id'] ?? '';
    final postTitle = data['post_title'] ?? '';
    final nextReminderTime = data['next_reminder_time'] ?? '';
    
    final int? reminderId = postId.isNotEmpty ? int.tryParse(postId) : null;
    
    final title = postTitle.isNotEmpty ? postTitle : 'تذكير';
    final body = "موعد التذكير التالي: $nextReminderTime";
    
    _showFcmNotificationSnackBar(title, body);
    _showSnackBar('FCM: $title - $body', Colors.blue);
    
    // تحويل البيانات إلى Map<String, dynamic> واستدعاء handleFcmMessage
    final Map<String, dynamic> messageData = Map<String, dynamic>.from(data);
    messageData['action'] = action;
    
    await RemindersNotifier.instance.handleFcmMessage(messageData);
  } catch (e) {
    _safeShowMessage('Error processing FCM message: $e', color: Colors.red);
  }
}

  // ============================================================================
  // الحل 1: إضافة فحوصات أمان في processMessage
  // ============================================================================

  Future<void> processMessageSafe(RemoteMessage message, {required bool isBackground}) async {
    try {
      _safeShowMessage('🔄 Starting safe processMessage', color: Colors.blue);
      
      // ✅ التحقق من جاهزية النظام
      final isReady = await _isSystemReady();
      if (!isReady && !isBackground) {
        _safeShowMessage('⚠️ System not ready, showing notification only', color: Colors.orange);
        
        // عرض إشعار بسيط فقط
        final title = message.data['post_title']?.toString() ?? 'تذكير';
        final body = message.data['next_reminder_time']?.toString() ?? '';
        _showFcmNotificationSnackBar(title, body);
        return;
      }

      // ✅ متابعة المعالجة العادية
      await processMessage(message, isBackground: isBackground);
      
    } catch (e, s) {
      _safeShowMessage('❌ Error in safe processMessage: $e', color: Colors.red);
      print('❌ Error: $e\n$s');
    }
  }

  // ============================================================================
  // الحل 2: تحسين _processReminderOperation مع معالجة أفضل للأخطاء
  // ============================================================================
  Future<void> _processReminderOperation(
    String action, int reminderId, bool isBackground, Map<String, dynamic> data) async {
  try {
    _safeShowMessage('🔄 Processing: $action for reminder: $reminderId', color: Colors.blue);
    
    // استدعاء RemindersNotifier لمعالجة رسالة FCM
    await RemindersNotifier.instance.handleFcmMessage(data);
    
    _safeShowMessage('✅ FCM message processed by RemindersNotifier', color: Colors.green);
  } catch (e, s) {
    _safeShowMessage('❌ Error in _processReminderOperation: $e', color: Colors.red);
    print('❌ Error: $e\n$s');
    
    // إرسال إشعار احتياطي
    if (isBackground) {
      try {
        await _sendGenericNotification(
          'خطأ في معالجة التذكير',
          'يرجى فتح التطبيق للمزامنة',
          data
        );
      } catch (_) {}
    }
  }
}

  // ============================================================================
  // الحل 3: تحسين _handleGeneralNotification
  // ============================================================================

  Future<void> _handleGeneralNotification(
      String title, String body, Map<String, dynamic> data, bool isBackground) async {
    try {
      _safeShowMessage('📢 Handling general notification', color: Colors.blue);

      // في حالة الخلفية، إرسال إشعار محلي
      if (isBackground) {
        await _sendGenericNotification(title, body, data);
      } else {
        // في المقدمة، عرض SnackBar فقط
        _showFcmNotificationSnackBar(title, body);
      }
    } catch (e) {
      _safeShowMessage('❌ Error in general notification: $e', color: Colors.red);
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

  Future<String?> getAccessToken() async {
    try {
      try {
        final String? token = await _fcmChannel.invokeMethod('getFCMToken');
        if (token != null && token.isNotEmpty) {
          return token;
        }
      } catch (e) {
        print('Error getting token from native code: $e');
      }
      
      if (kIsWeb) {
        return await _firebaseMessaging.getToken(
          vapidKey: 'your-vapid-key-here',
        );
      }

      final jsonString = await rootBundle.loadString(
        AppConstants.SERVICE_ACCOUNT_PATH,
      );

      final accountCredentials =
          auth.ServiceAccountCredentials.fromJson(jsonString);
      final scopes = [AppConstants.FIREBASE_MESSAGING_SCOPE];
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
  // if (!_isFirebaseInitialized) {
  //   _safeShowMessage('⚠️ Skipping message handlers - Firebase not initialized', color: Colors.orange);
  //   return;
  // }
    if (Firebase.apps.isEmpty) {
    _safeShowMessage('⚠️ Skipping message handlers - Firebase app not active', color: Colors.orange);
    return;
  }

  try {
    // معالج المقدمة
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _safeShowMessage('📨 FOREGROUND MESSAGE RECEIVED', color: Colors.blue);
      
      try {
        final data = Map<String, dynamic>.from(message.data);
        final postTitle = data['post_title']?.toString().trim() ?? '';
        final nextReminderTime = data['next_reminder_time']?.toString() ?? '';
        
        final title = postTitle.isNotEmpty ? postTitle : 'تذكير';
        final body = "موعد التذكير التالي: $nextReminderTime";
        
        if (title.isNotEmpty || body.isNotEmpty) {
          _showFcmNotificationSnackBar(title, body);
        }

        await processMessageSafe(message, isBackground: false);
        
        _safeShowMessage('✅ Message processed successfully', color: Colors.green);
        
      } catch (e, stackTrace) {
        _safeShowMessage('❌ Error processing message: $e', color: Colors.red);
        print('Error: $e\nStack: $stackTrace');
      }
    }, onError: (error) {
      _safeShowMessage('❌ Stream error: $error', color: Colors.red);
    });

    // معالج فتح التطبيق من إشعار
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _safeShowMessage('📱 App opened from notification', color: Colors.blue);
      
      try {
        _handleMessageOpenedAppNavigation(message);
      } catch (e) {
        _safeShowMessage('❌ Error handling opened app: $e', color: Colors.red);
      }
    });

    // معالج الرسالة الأولية
    FirebaseMessaging.instance.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        _safeShowMessage('📬 Initial message', color: Colors.blue);
        
        Future.delayed(const Duration(seconds: 2), () {
          try {
            _handleMessageOpenedAppNavigation(initialMessage);
          } catch (e) {
            _safeShowMessage('❌ Error handling initial message: $e', color: Colors.red);
          }
        });
      }
    });

    _safeShowMessage('✅ Message handlers configured', color: Colors.green);
    
  } catch (e, stackTrace) {
    _safeShowMessage('❌ Setup error: $e', color: Colors.red);
    print('Error: $e\nStack: $stackTrace');
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

  
Future<void> _handleForegroundMessage(RemoteMessage message) async {
  _showSnackBar('📨 Handling foreground message', Colors.blue);
  _safeShowMessage('=== Foreground message received ===', color: Colors.blue);
  
  try {
    _isAppInForeground = true;

    final messageId = message.messageId ?? 
        'msg_${DateTime.now().millisecondsSinceEpoch}';
    
    if (_isDuplicateMessage(messageId)) {
      _showSnackBar('⏭️ Duplicate message ignored', Colors.orange);
      _safeShowMessage('⏭️ Duplicate message ignored: $messageId', color: Colors.orange);
      return;
    }
    
    // ✅ استخراج title و body من data
    final data = Map<String, dynamic>.from(message.data);
    final title = data['title']?.toString() ?? data['post_title']?.toString() ?? 'تذكير';
    final body = data['body']?.toString() ?? '';
    
    // عرض SnackBar
    if (title.isNotEmpty) {
      _showFcmNotificationSnackBar(title, body);
    }
    
    // استدعاء handleFcmMessage من RemindersNotifier
    await RemindersNotifier.instance.handleFcmMessage(data);
    
  } catch (e, stackTrace) {
    _showSnackBar('❌ Error in foreground handler', Colors.red);
    _safeShowMessage('❌ Error in foreground handler: $e', color: Colors.red);
    _safeShowMessage('Stack trace: $stackTrace', color: Colors.red);
  }
}

Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
  _showSnackBar('📱 Handling app opened from notification', Colors.blue);
  _safeShowMessage('=== App opened from notification ===', color: Colors.blue);
  
  try {
    _isAppInForeground = true;

    final messageId = message.messageId ?? 
        'opened_${DateTime.now().millisecondsSinceEpoch}';
    
    if (_isDuplicateMessage(messageId)) {
      _showSnackBar('⏭️ Duplicate message ignored', Colors.orange);
      _safeShowMessage('⏭️ Duplicate message ignored', color: Colors.orange);
      return;
    }

    // ✅ استخراج البيانات من data
    final data = Map<String, dynamic>.from(message.data);
    
    // استدعاء handleFcmMessage من RemindersNotifier
    await RemindersNotifier.instance.handleFcmMessage(data);
    
  } catch (e, stackTrace) {
    _showSnackBar('❌ Error handling app opened', Colors.red);
    _safeShowMessage('❌ Error handling app opened: $e', color: Colors.red);
    _safeShowMessage('Stack trace: $stackTrace', color: Colors.red);
  }
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
}