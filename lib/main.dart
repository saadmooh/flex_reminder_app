import 'package:flex_reminder/globals.dart'; // استيراد واحد فقط
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/consts.dart';
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
import 'package:flex_reminder/services/reminders_service.dart';
import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/services/subscription_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/background/workmanager_dispatcher.dart'; // ✅ استيراد dispatcher

// إنشاء instance مشترك للـ NotificationService
late NotificationService _backgroundNotificationService;
late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

// ============================================================================
// دوال مساعدة للرسائل والإشعارات
// ============================================================================

/// دالة محسّنة لعرض الرسائل باستخدام نظام globals.dart
void _safeShowMessage(String message, {Color? color, bool debugOnly = false}) {
  // 1. طباعة في الـ debug console دائماً
  if (kDebugMode) {
    debugPrint('Main: $message');
  }

  // 2. عرض SnackBar باستخدام النظام العام من globals.dart
  if (!debugOnly) {
    // اختيار الدالة المناسبة بناءً على اللون
    if (color == Colors.red) {
      showErrorSnackBar(message);
    } else if (color == Colors.green) {
      showSuccessSnackBar(message);
    } else if (color == Colors.orange) {
      showWarningSnackBar(message);
    } else {
      showInfoSnackBar(message);
    }
  }
}

// ============================================================================
// دوال التهيئة
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 1. تهيئة Firebase أولاً
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // ✅ 2. تهيئة الإشعارات المحلية
  await _initializeLocalNotifications();
  
  // ✅ 3. تسجيل معالج الخلفية (الخفيف الآن)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // ✅ 4. تهيئة WorkManager (مرة واحدة فقط)
  await Workmanager().initialize(
    callbackDispatcher,  // ✅ من workmanager_dispatcher.dart
    isInDebugMode: kDebugMode,
  );
  
  // ✅ تفعيل وضع Debug في بداية التطبيق
  isDebugMode = true; // من globals.dart
 
  // استخدام دالة التهيئة الموحدة
  await _initializeAndStartApp();
}

Future<void> _initializeAndStartApp() async {
  try {
    // تهيئة Firebase
    final firebaseInitialized = await _initializeFirebaseSafely();
    
    // تهيئة NotificationService (للإشعارات المجدولة)
    try {
      final notificationService = NotificationService();
      await notificationService.init();
    } catch (e) {
      await showErrorSnackBar('خطأ في تهيئة خدمة الإشعارات');
      debugPrint('NotificationService error: $e');
    }

    // تهيئة RemindersNotifier
    final remindersNotifier = RemindersNotifier.instance;
    await remindersNotifier.initialize(authProvider: AuthProvider.instance);

    // طباعة حالة جميع الخدمات
    printServicesStatus();

    // تشغيل التطبيق
    print('🎯 تشغيل التطبيق...');
    print('=' * 60);
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageManager()),
          ChangeNotifierProvider(create: (_) => AuthProvider.instance),
          ChangeNotifierProvider.value(value: remindersNotifier),
        ],
        child: MyApp(
          isFirebaseInitialized: isFirebaseInitialized,
          isFcmInitialized: isFcmInitialized,
          isRevenueCatInitialized: isRevenueCatInitialized,
          initializationError: initializationError,
        ),
      ),
    );
  } catch (e) {
    await showErrorSnackBar('خطأ في تهيئة التطبيق');
    debugPrint('App initialization error: $e');
    
    // في حالة الخطأ، محاولة تشغيل التطبيق
    final remindersNotifier = RemindersNotifier.instance;
    try {
      await remindersNotifier.initialize(authProvider: AuthProvider.instance);
    } catch (_) {}
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageManager()),
          ChangeNotifierProvider(create: (_) => AuthProvider.instance),
          ChangeNotifierProvider.value(value: remindersNotifier),
        ],
        child: MyApp(
          isFirebaseInitialized: isFirebaseInitialized,
          isFcmInitialized: isFcmInitialized,
          isRevenueCatInitialized: isRevenueCatInitialized,
          initializationError: initializationError ?? e.toString(),
        ),
      ),
    );
  }
}

// تهيئة Firebase بشكل آمن
Future<bool> _initializeFirebaseSafely() async {
  try {
    debugPrint('🚀 بدء تهيئة Firebase...');
    
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('انتهت مهلة تهيئة Firebase');
      },
    );
    
    await showSuccessSnackBar('تم تهيئة Firebase بنجاح');
    isFirebaseInitialized = true;
    return true;
  } catch (e) {
    await showErrorSnackBar('خطأ في تهيئة Firebase');
    initializationError = 'خطأ في تهيئة Firebase: $e';
    isFirebaseInitialized = false;
    debugPrint('Firebase init error: $e');
    return false;
  }
}

// ============================================================================
// دوال الخدمات في الخلفية (معدلة)
// ============================================================================

// ✅ تعديل مهم: معالج الخلفية الخفيف جدًا
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 1. Firebase فقط
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (message.data.isEmpty) return;

  // 2. حفظ البيانات (خفيف)
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'pending_fcm_payload',
    jsonEncode(message.data),
  );

  // 3. تشغيل WorkManager
  await Workmanager().registerOneOffTask(
    'fcm-background-task',
    'processFcmPayload',
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    backoffPolicy: BackoffPolicy.exponential,
  );
}

// 🔥 تعديل جديد: دالة مساعدة لعرض الإشعار المحلي
Future<void> _showLocalNotificationFromMessage(RemoteMessage message) async {
  // تأكد من تهيئة الإشعارات المحلية
  if (_flutterLocalNotificationsPlugin == null) {
    await _initializeLocalNotifications();
  }

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'high_importance_channel', // معرف القناة
    'High Importance Notifications', // اسم القناة
    channelDescription: 'This channel is used for important notifications.',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher', // 🔥 تعديل جديد: استخدام أيقونة التطبيق
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await _flutterLocalNotificationsPlugin.show(
    message.hashCode, // معرف فريد للإشعار
    message.notification?.title ?? 'Flex Reminder', // عنوان الإشعار
    message.notification?.body ?? 'لديك تذكير جديد', // محتوى الإشعار
    platformChannelSpecifics,
    payload: jsonEncode(message.data), // إرسال البيانات كـ payload
  );
}

Future<void> _initializeLocalNotifications() async {
  try {
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // 🔥 تعديل جديد: استخدام أيقونة التطبيق
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
        debugPrint('تم النقر على الإشعار في الخلفية: ${response.payload}');
        _handleBackgroundNotificationClick(response);
      },
    );
    debugPrint('✅ تم تهيئة الإشعارات المحلية في الخلفية');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة الإشعارات المحلية في الخلفية: $e');
  }
}

// ============================================================================
// دوال الإشعارات
// ============================================================================

void _showFcmNotificationSnackBar(String title, String body) {
  if (title.isEmpty && body.isEmpty) return;
  
  String message = title.isNotEmpty ? '$title${body.isNotEmpty ? ': $body' : ''}' : body;
  
  // استخدام النظام العام من globals.dart
  showInfoSnackBar(message);
}

void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    debugPrint('🔗 Handling message opened app...');
    
    final data = Map<String, dynamic>.from(message.data);
    final postId = data['post_id']?.toString() ?? '';
    final action = data['action']?.toString().trim() ?? '';
    final postUrl = data['post_url']?.toString().trim() ?? '';
    
    final int? reminderId = postId.isNotEmpty ? int.tryParse(postId) : null;
    
    // عرض رسالة معلومات
    showInfoSnackBar('فتح التذكير...');
    
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
    showErrorSnackBar('خطأ في فتح التذكير');
    debugPrint('Navigation error: $e');
  }
}

void _handleBackgroundNotificationClick(NotificationResponse response) {
  try {
    debugPrint('👆 تم النقر على إشعار في الخلفية');
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      debugPrint('البيانات: $data');
    }
  } catch (e) {
    showErrorSnackBar('خطأ في معالجة النقر على الإشعار');
    debugPrint('Error: $e');
  }
}

// ============================================================================
// دوال إضافية
// ============================================================================

// إضافة دالة للتحكم في وضع Debug من واجهة المستخدم
void toggleDebugMode(bool enabled) {
  isDebugMode = enabled;
  
  if (enabled) {
    showSuccessSnackBar('تم تفعيل وضع Debug');
  } else {
    showInfoSnackBar('تم تعطيل وضع Debug');
    // مسح قائمة الانتظار
    clearSnackBarQueue();
  }
  
  debugPrint('🐛 Debug Mode: ${enabled ? "Enabled" : "Disabled"}');
  debugPrint('📬 Queue Length: ${getSnackBarQueueLength()}');
}

// إضافة دالة لعرض معلومات Debug
void showDebugInfo() {
  debugPrint('\n' + '=' * 60);
  debugPrint('📊 Debug Information:');
  debugPrint('   Firebase: ${isFirebaseInitialized ? "✅" : "❌"}');
  debugPrint('   FCM: ${isFcmInitialized ? "✅" : "❌"}');
  debugPrint('   RevenueCat: ${isRevenueCatInitialized ? "✅" : "❌"}');
  debugPrint('   RemindersNotifier: ${isRemindersNotifierInitialized ? "✅" : "❌"}');
  debugPrint('   Debug Mode: ${isDebugMode ? "🟢 ON" : "🔴 OFF"}');
  debugPrint('   SnackBar Queue: ${getSnackBarQueueLength()} messages');
  debugPrint('   Processing: ${isSnackBarProcessing() ? "⚙️ Active" : "⏸️ Idle"}');
  if (initializationError != null) {
    debugPrint('   ⚠️ Error: $initializationError');
  }
  debugPrint('=' * 60 + '\n');
}

// ============================================================================
// تطبيق منفصل لحالة عدم وجود إنترنت
// ============================================================================

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
      // إعادة تشغيل التطبيق باستخدام دالة التهيئة الموحدة
      await _initializeAndStartApp();
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

// ============================================================================
// التطبيق الرئيسي
// ============================================================================

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
    debugPrint(
        'MyApp build called - Firebase: $isFirebaseInitialized, FCM: $isFcmInitialized, RevenueCat: $isRevenueCatInitialized');
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