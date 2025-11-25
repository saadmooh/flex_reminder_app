import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/pages/auth_screen.dart';
import 'package:flex_reminder/pages/reminders_screen.dart';
import 'package:flex_reminder/pages/reminder_detail_screen.dart';
import 'package:flex_reminder/pages/time_slots_screen.dart';
import 'package:flex_reminder/pages/save_post_screen.dart';
import 'package:flex_reminder/pages/stats_screen.dart';
import 'package:flex_reminder/pages/splash_screen.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/pages/reset_password_screen.dart';
import 'package:flex_reminder/pages/subscription_management_screen.dart';
import 'package:flex_reminder/pages/verification_code_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flex_reminder/firebase_options.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'dart:convert';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// متغيرات للتحكم في حالة التهيئة
bool _isFirebaseInitialized = false;
bool _isFcmInitialized = false;
bool _isRevenueCatInitialized = false;
String? _initializationError;

// إنشاء instance مشترك للـ NotificationService
late NotificationService _backgroundNotificationService;
late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فحص الإنترنت أولاً
  final hasInternet =
      await ConnectivityHelper.checkInternetConnection(verbose: true);

  if (!hasInternet) {
    // تشغيل التطبيق مع شاشة عدم وجود إنترنت
    runApp(const NoInternetApp());
    return;
  }

  // باقي الكود للحالة العادية...
  await _initializeFirebaseSafely();

  // تهيئة WorkManager أولاً (لا يتطلب إنترنت)
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    _safeShowMessage('✅ تم تهيئة WorkManager', color: Colors.green);
  } catch (e) {
    _safeShowMessage('⚠️ خطأ في تهيئة WorkManager: $e', color: Colors.orange);
  }

  // تهيئة خدمة الإشعارات (لا تتطلب إنترنت)
  try {
    final notificationService = NotificationService();
    await notificationService.init();
    _safeShowMessage('✅ تم تهيئة خدمة الإشعارات', color: Colors.green);
  } catch (e) {
    _safeShowMessage('⚠️ خطأ في تهيئة خدمة الإشعارات: $e',
        color: Colors.orange);
  }

  // محاولة تهيئة FCM (فقط إذا تم تهيئة Firebase)
  await _initializeFcmSafely();
  _setupMessageHandlers();

  // تشغيل التطبيق العادي
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => AuthProvider.instance),
        ChangeNotifierProvider.value(
          value: RemindersNotifier.instance..navigatorKey = navigatorKey,
        ),
      ],
      child: MyApp(
        isFirebaseInitialized: _isFirebaseInitialized,
        isFcmInitialized: _isFcmInitialized,
        isRevenueCatInitialized: _isRevenueCatInitialized,
        initializationError: _initializationError,
      ),
    ),
  );

  _safeShowMessage('✅ تم إطلاق التطبيق بنجاح', color: Colors.green);
}

// تطبيق منفصل لحالة عدم وجود إنترنت
class NoInternetApp extends StatelessWidget {
  const NoInternetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flex Reminder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'arial',
      ),
      home: const NoInternetScreen(),
    );
  }
}

// شاشة عدم وجود إنترنت محسنة
class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _isChecking = false;

  Future<void> _retryConnection() async {
    setState(() {
      _isChecking = true;
    });

    await Future.delayed(const Duration(seconds: 1)); // إظهار حالة التحقق

    final hasInternet =
        await ConnectivityHelper.checkInternetConnection(verbose: true);

    setState(() {
      _isChecking = false;
    });

    if (hasInternet) {
      // إعادة تشغيل التطبيق بالكود الأصلي
      await _initializeAndStartApp();
    }
  }

  Future<void> _initializeAndStartApp() async {
    try {
      // تهيئة Firebase
      await _initializeFirebaseSafely();

      // تهيئة باقي الخدمات
      try {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: true,
        );
      } catch (e) {
        debugPrint('خطأ في تهيئة WorkManager: $e');
      }

      try {
        final notificationService = NotificationService();
        await notificationService.init();
      } catch (e) {
        debugPrint('خطأ في تهيئة خدمة الإشعارات: $e');
      }

      await _initializeFcmSafely();
      _setupMessageHandlers();

      // استبدال التطبيق الحالي بالتطبيق الرئيسي
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => LanguageManager()),
                ChangeNotifierProvider(create: (_) => AuthProvider.instance),
                ChangeNotifierProvider.value(
                  value: RemindersNotifier.instance
                    ..navigatorKey = navigatorKey,
                ),
              ],
              child: MyApp(
                isFirebaseInitialized: _isFirebaseInitialized,
                isFcmInitialized: _isFcmInitialized,
                isRevenueCatInitialized: _isRevenueCatInitialized,
                initializationError: _initializationError,
              ),
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('خطأ في تهيئة التطبيق: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // شعار التطبيق
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.access_time,
                      size: 60,
                      color: Colors.black,
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              // أيقونة عدم الاتصال
              Icon(
                Icons.wifi_off_rounded,
                size: 80,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 24),
              // رسالة عدم الاتصال
              Text(
                'لا يوجد اتصال بالإنترنت',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'يرجى التحقق من الاتصال والمحاولة مرة أخرى',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // زر إعادة المحاولة
              ElevatedButton.icon(
                onPressed: _isChecking ? null : _retryConnection,
                icon: _isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isChecking ? 'جاري التحقق...' : 'إعادة المحاولة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// دالة عرض الرسائل الآمنة (مع دعم Snackbar)
void _safeShowMessage(String message, {Color? color, bool debugOnly = false}) {
  // طباعة في الـ debug console إذا كان مطلوباً
  if (kDebugMode) {
    debugPrint('Main Debug: $message');
  }

  // عرض Snackbar باستخدام الـ GlobalKey (فقط إذا لم يكن debugOnly فقط)
  if (!debugOnly && scaffoldMessengerKey.currentState != null) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: color ?? Colors.blue, // لون افتراضي، يمكن تغييره
        duration: const Duration(seconds: 3), // مدة العرض
        behavior: SnackBarBehavior.floating, // لجعله يطفو
        margin: const EdgeInsets.all(16), // هامش للشاشة
      ),
    );
  }
}

// دالة لعرض SnackBar دائمًا عند وصول إشعار FCM
void _showFcmNotificationSnackBar(String title, String body) {
  String message = title.isNotEmpty ? '$title: $body' : body;
  _safeShowMessage('🔔 وصل إشعار: $message', color: Colors.blue);
}

// معالج الرسائل في الخلفية
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await _initializeBackgroundServices();
    final String title =
        message.notification?.title ?? message.data['title'] ?? 'تذكير جديد';
    final String body = message.notification?.body ??
        message.data['body'] ??
        'لديك تذكير في انتظارك';
    try {
      await FcmService.processMessage(message, isBackground: true);
    } catch (processingError) {
      _safeShowMessage('❌ خطأ في معالجة FCM: $processingError',
          color: Colors.red);
      await _scheduleFailbackNotification(title, body, message.data);
    }
    _safeShowMessage('✅ تم معالجة الرسالة في الخلفية بنجاح',
        color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ عام في معالجة الرسالة في الخلفية: $e',
        color: Colors.red);
    await _scheduleFailbackNotification(
        "_scheduleEmergencyNotification", "body", message.data);
  }
}

// تهيئة Firebase بشكل آمن
Future<bool> _initializeFirebaseSafely() async {
  try {
    _safeShowMessage('🔄 فحص الاتصال بالإنترنت...', debugOnly: true);
    final hasInternet =
        await ConnectivityHelper.checkInternetConnection(verbose: true);
    if (!hasInternet) {
      _safeShowMessage('⚠️ لا يوجد اتصال بالإنترنت - تخطي تهيئة Firebase',
          color: Colors.orange);
      _initializationError = 'لا يوجد اتصال بالإنترنت';
      return false;
    }
    _safeShowMessage('🚀 بدء تهيئة Firebase...', debugOnly: true);
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('انتهت مهلة تهيئة Firebase');
      },
    );
    _safeShowMessage('✅ تم تهيئة Firebase بنجاح', color: Colors.green);
    _isFirebaseInitialized = true;
    return true;
  } catch (e) {
    _safeShowMessage('❌ خطأ في تهيئة Firebase: $e', color: Colors.red);
    _initializationError = 'خطأ في تهيئة Firebase: $e';
    _isFirebaseInitialized = false;
    return false;
  }
}

// تهيئة FCM بشكل آمن
Future<bool> _initializeFcmSafely() async {
  try {
    if (!_isFirebaseInitialized) {
      _safeShowMessage('⚠️ Firebase غير مهيئ - تخطي تهيئة FCM',
          color: Colors.orange);
      return false;
    }
    _safeShowMessage('🔄 بدء تهيئة FCM...', debugOnly: true);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _safeShowMessage('✅ تم تسجيل معالج الرسائل في الخلفية',
        color: Colors.green);
    final fcmService = FcmService();
    final fcmResult = await fcmService.init().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        return {'success': false, 'message': 'انتهت مهلة تهيئة FCM'};
      },
    );
    _safeShowMessage('✅ تم تهيئة FCM Service: ${fcmResult['message']}',
        color: Colors.green);
    _isFcmInitialized = fcmResult['success'] ?? false;
    return _isFcmInitialized;
  } catch (e) {
    _safeShowMessage('❌ خطأ في تهيئة FCM: $e', color: Colors.red);
    _isFcmInitialized = false;
    return false;
  }
}

// إعداد معالجات الرسائل
void _setupMessageHandlers() {
  if (!_isFirebaseInitialized) {
    _safeShowMessage('⚠️ تخطي إعداد معالجات الرسائل - Firebase غير مهيئ',
        color: Colors.orange);
    return;
  }
  try {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _safeShowMessage('📨 وصلت رسالة والتطبيق في المقدمة', debugOnly: true);

      // عرض SnackBar دائمًا عند وصول إشعار في المقدمة
      final String title =
          message.data['title'] ?? message.notification?.title ?? '';
      final String body =
          message.data['body'] ?? message.notification?.body ?? '';
      _showFcmNotificationSnackBar(title, body);

      try {
        await FcmService.processMessage(message, isBackground: false);
        final notificationService = NotificationService();
        await _scheduleForegroundNotification(message, notificationService);
      } catch (e) {
        _safeShowMessage('❌ خطأ في معالجة رسالة المقدمة: $e',
            color: Colors.red);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _safeShowMessage('📱 تم فتح التطبيق من إشعار في الخلفية',
          debugOnly: true);
      _safeShowMessage('Message  ${message.data}', debugOnly: true);

      // عرض SnackBar عند فتح التطبيق من الإشعار
      final String title =
          message.data['title'] ?? message.notification?.title ?? '';
      final String body =
          message.data['body'] ?? message.notification?.body ?? '';
      _showFcmNotificationSnackBar(title, body);

      _handleMessageOpenedApp(message);
    });
    FirebaseMessaging.instance.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        _safeShowMessage('📬 تم فتح التطبيق من إشعار أولي', debugOnly: true);
        _safeShowMessage('Initial message  ${initialMessage.data}',
            debugOnly: true);

        // عرض SnackBar عند فتح التطبيق من الإشعار الأولي
        final String title = initialMessage.data['title'] ??
            initialMessage.notification?.title ??
            '';
        final String body = initialMessage.data['body'] ??
            initialMessage.notification?.body ??
            '';
        _showFcmNotificationSnackBar(title, body);

        Future.delayed(const Duration(seconds: 2), () {
          _handleMessageOpenedApp(initialMessage);
        });
      }
    }).catchError((e) {
      _safeShowMessage('❌ خطأ في الحصول على الرسالة الأولية: $e',
          color: Colors.red);
    });
    _safeShowMessage('✅ تم إعداد معالجات الرسائل', color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في إعداد معالجات الرسائل: $e', color: Colors.red);
  }
}

// تهيئة الخدمات في الخلفية
Future<void> _initializeBackgroundServices() async {
  try {
    _backgroundNotificationService = NotificationService();
    await _backgroundNotificationService.init();
    await _initializeLocalNotifications();
    _safeShowMessage('✅ تم تهيئة الخدمات في الخلفية', color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في تهيئة الخدمات في الخلفية: $e',
        color: Colors.red);
  }
}

// تهيئة الإشعارات المحلية في الخلفية
Future<void> _initializeLocalNotifications() async {
  try {
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _safeShowMessage('تم النقر على الإشعار في الخلفية: ${response.payload}',
            debugOnly: true);
        _handleBackgroundNotificationClick(response);
      },
    );
    _safeShowMessage('✅ تم تهيئة الإشعارات المحلية في الخلفية',
        color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في تهيئة الإشعارات المحلية في الخلفية: $e',
        color: Colors.red);
  }
}

// جدولة إشعار احتياطي
Future<void> _scheduleFailbackNotification(
    String title, String body, Map<String, dynamic> data) async {
  try {
    _safeShowMessage('🔄 جدولة إشعار احتياطي...', debugOnly: true);
    await _showDirectLocalNotification(
      title: '⚠️ $title (احتياطي)',
      body: '$body - تم استلام الرسالة',
      data: data,
      notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final scheduledDate = DateTime.now().add(const Duration(seconds: 20));
    await _backgroundNotificationService.scheduleNotification(
      title: '⚠️ $title (احتياطي)',
      body: 'رسالة لم يتم تسليمها: $body',
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      payload: {
        'type': 'fcm_fallback',
        'original_title': title,
        'original_body': body,
        'source_data': jsonEncode(data),
        'scheduled_at': scheduledDate.toIso8601String(),
      },
    );
    _safeShowMessage('✅ تم جدولة الإشعار الاحتياطي', color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في جدولة الإشعار الاحتياطي: $e', color: Colors.red);
  }
}

// عرض إشعار محلي مباشر
Future<void> _showDirectLocalNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
  required int notificationId,
}) async {
  try {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'fcm_background_channel',
      'FCM Background Notifications',
      channelDescription: 'Notifications received when app is in background',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'view_action',
          'عرض',
          titleColor: Color.fromARGB(255, 255, 255, 255),
        ),
        AndroidNotificationAction(
          'dismiss_action',
          'إخفاء',
          titleColor: Color.fromARGB(255, 255, 0, 0),
          contextual: true,
        ),
      ],
    );
    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      badgeNumber: 1,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );
    await _flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: jsonEncode(data),
    );
    _safeShowMessage('✅ تم إظهار إشعار محلي مباشر: $title',
        color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في إظهار الإشعار المحلي المباشر: $e',
        color: Colors.red);
  }
}

// معالجة النقر على الإشعار في الخلفية
void _handleBackgroundNotificationClick(NotificationResponse response) {
  try {
    _safeShowMessage('👆 تم النقر على إشعار في الخلفية', debugOnly: true);
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      _safeShowMessage('البيانات: $data', debugOnly: true);
    }
  } catch (e) {
    _safeShowMessage('❌ خطأ في معالجة النقر على الإشعار: $e',
        color: Colors.red);
  }
}

// جدولة إشعار في المقدمة
Future<void> _scheduleForegroundNotification(
    RemoteMessage message, NotificationService notificationService) async {
  try {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'تذكير جديد';
    final body =
        message.notification?.body ?? message.data['body'] ?? 'لديك تذكير جديد';
    final scheduledDate = DateTime.now().add(const Duration(seconds: 10));
    await notificationService.scheduleNotification(
      title: '📱 $title (مقدمة)',
      body: body,
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      payload: {
        'type': 'fcm_foreground',
        'source_data': jsonEncode(message.data),
        'scheduled_at': scheduledDate.toIso8601String(),
        ...message.data.map((key, value) => MapEntry(key, value.toString())),
      },
    );
    _safeShowMessage('✅ تم جدولة إشعار المقدمة للوقت: $scheduledDate',
        color: Colors.green);
  } catch (e) {
    _safeShowMessage('❌ خطأ في جدولة إشعار المقدمة: $e', color: Colors.red);
  }
}

// معالجة فتح التطبيق من إشعار
void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    _safeShowMessage('🔗 معالجة فتح التطبيق من إشعار...', debugOnly: true);
    final data = message.data;
    if (data.containsKey('reminder_id')) {
      final reminderId = int.tryParse(data['reminder_id'].toString());
      if (reminderId != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          navigatorKey.currentState?.pushNamed('/reminder', arguments: {
            'reminderId': reminderId,
          });
        });
        return;
      }
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/reminders',
        (route) => false,
      );
    });
  } catch (e) {
    _safeShowMessage('❌ خطأ في معالجة فتح التطبيق من إشعار: $e',
        color: Colors.red);
  }
}

class MyApp extends StatelessWidget {
  final bool isFirebaseInitialized;
  final bool isFcmInitialized;
  final bool isRevenueCatInitialized;
  final String? initializationError;

  const MyApp({
    super.key,
    required this.isFirebaseInitialized,
    required this.isFcmInitialized,
    required this.isRevenueCatInitialized,
    this.initializationError,
  });

  @override
  Widget build(BuildContext context) {
    _safeShowMessage(
        'MyApp build called - Firebase: $isFirebaseInitialized, FCM: $isFcmInitialized, RevenueCat: $isRevenueCatInitialized',
        debugOnly: true);
    return Consumer2<LanguageManager, AuthProvider>(
      builder: (context, languageManager, authProvider, child) {
        RemindersNotifier.instance.setAuthProvider(authProvider);
        return MaterialApp(
          title: AppLocalizations.of(context)?.appTitle ?? 'Reminder App',
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            fontFamily: 'arial',
            scaffoldBackgroundColor: Colors.black,
            cardColor: Colors.grey[900],
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.white),
              bodyMedium: TextStyle(color: Colors.white70),
              displayLarge:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white70),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff727475),
                padding: const EdgeInsets.symmetric(
                    horizontal: 48.0, vertical: 16.0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0)),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffcbced0)),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''),
            Locale('ar', ''),
            Locale('zh', ''),
          ],
          locale: languageManager.locale,
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) {
              return supportedLocales.first;
            }
            for (var supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale.languageCode) {
                return supportedLocale;
              }
            }
            return supportedLocales.first;
          },
          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(
                  builder: (_) => SplashScreen(
                    isFirebaseInitialized: isFirebaseInitialized,
                    isFcmInitialized: isFcmInitialized,
                    isRevenueCatInitialized: isRevenueCatInitialized,
                    initializationError: initializationError,
                  ),
                );
              case '/auth':
                return MaterialPageRoute(builder: (_) => const AuthScreen());
              case '/reminders':
              case '/home':
                return MaterialPageRoute(
                    builder: (_) => const RemindersScreen());
              case '/reminder':
                final args = settings.arguments as Map<String, dynamic>?;
                final reminderId = args?['reminderId'] as int?;
                if (reminderId != null) {
                  return MaterialPageRoute(
                    builder: (_) =>
                        ReminderDetailScreen(reminderId: reminderId),
                  );
                }
                return MaterialPageRoute(
                    builder: (_) => const RemindersScreen());
              case '/time_slots':
                return MaterialPageRoute(
                    builder: (_) => const TimeSlotsScreen());
              case '/save-post':
                return MaterialPageRoute(
                    builder: (_) => const SavePostScreen());
              case '/stats':
                return MaterialPageRoute(builder: (_) => const StatsScreen());
              case '/reset-password':
                return MaterialPageRoute(
                    builder: (_) => const ResetPasswordScreen());
              case '/verify-email':
                final email = settings.arguments as String?;
                return MaterialPageRoute(
                    builder: (_) => VerificationCodeScreen(email: email ?? ''));
              case '/subscription_management':
                return MaterialPageRoute(
                    builder: (_) => const SubscriptionManagementScreen());
              default:
                return MaterialPageRoute(
                  builder: (_) => SplashScreen(
                    isFirebaseInitialized: isFirebaseInitialized,
                    isFcmInitialized: isFcmInitialized,
                    isRevenueCatInitialized: isRevenueCatInitialized,
                    initializationError: initializationError,
                  ),
                );
            }
          },
        );
      },
    );
  }
}

// دالة callbackDispatcher للـ WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // تهيئة Firebase إذا لزم الأمر
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // تنفيذ المهمة بناءً على نوعها
      switch (task) {
        case 'reminderTask':
          // معالجة التذكيرات
          final reminderId = inputData?['reminderId'];
          if (reminderId != null) {
            // هنا يمكنك إضافة كود معالجة التذكير
            debugPrint('تم تنفيذ تذكير رقم: $reminderId');
          }
          break;
        default:
          debugPrint('مهمة غير معروفة: $task');
      }
      return Future.value(true);
    } catch (e) {
      debugPrint('خطأ في تنفيذ المهمة: $e');
      return Future.value(false);
    }
  });
}