import 'package:flex_reminder/globals.dart'; // للوصول إلى navigatorKey
import 'package:flex_reminder/globals.dart' as globals;
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
import 'package:flex_reminder/services/fcm_service.dart' hide RemindersNotifier;
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'dart:convert';

// ✅ استخدام navigatorKey و scaffoldMessengerKey من globals.dart بدلاً من تعريفها مرتين

// إنشاء instance مشترك للـ NotificationService
late NotificationService _backgroundNotificationService;
late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

void main() async {
  // ✅ 1. تهيئة Flutter Binding
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🚀 ========== بدء تشغيل التطبيق ==========');

  // ✅ 2. فحص الاتصال بالإنترنت
  print('📡 فحص الاتصال بالإنترنت...');
  final hasInternet = await ConnectivityHelper.checkInternetConnection(verbose: true);
  if (!hasInternet) {
    print('❌ لا يوجد اتصال بالإنترنت - تشغيل شاشة عدم الاتصال');
    runApp(const NoInternetApp());
    return;
  }
  print('✅ الاتصال بالإنترنت متوفر');

  // ✅ 3. استخدام دالة التهيئة الموحدة
  await _initializeAndStartApp();
}

// دالة التهيئة الموحدة
Future<void> _initializeAndStartApp() async {
  try {
    // تهيئة Firebase
     final firebaseInitialized = await _initializeFirebaseSafely();
  if (firebaseInitialized) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _initializeFcmSafely();
   // _setupMessageHandlers();
  }

    // تهيئة باقي الخدمات
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: true,
      );
    } catch (e) {
      _safeShowMessage('خطأ في تهيئة WorkManager: $e', color: Colors.red);
    }

    try {
      final notificationService = NotificationService();
      await notificationService.init();
    } catch (e) {
      _safeShowMessage('خطأ في تهيئة خدمة الإشعارات: $e', color: Colors.red);
    }

   

    // ✅ تهيئة RemindersNotifier مع ربطه بـ AuthProvider
    final remindersNotifier = RemindersNotifier.instance;
    await remindersNotifier.initialize(authProvider: AuthProvider.instance);

    // ✅ طباعة حالة جميع الخدمات
    globals.printServicesStatus();

    // تشغيل التطبيق
    print('🎯 تشغيل التطبيق...');
    print('=' * 60);
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageManager()),
          ChangeNotifierProvider(create: (_) => AuthProvider.instance),
          ChangeNotifierProvider.value(
            value: remindersNotifier,
          ),
        ],
        child: MyApp(
          isFirebaseInitialized: globals.isFirebaseInitialized,
          isFcmInitialized: globals.isFcmInitialized,
          isRevenueCatInitialized: globals.isRevenueCatInitialized,
          initializationError: globals.initializationError,
        ),
      ),
    );
  } catch (e) {
    _safeShowMessage('خطأ في تهيئة التطبيق: $e', color: Colors.red);
    
    // في حالة الخطأ، قم بتشغيل التطبيق مع عرض الخطأ
    final remindersNotifier = RemindersNotifier.instance;
    // محاولة تهيئة RemindersNotifier حتى في حالة الخطأ
    try {
      await remindersNotifier.initialize(authProvider: AuthProvider.instance);
    } catch (_) {
      // تجاهل خطأ التهيئة هنا
    }
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageManager()),
          ChangeNotifierProvider(create: (_) => AuthProvider.instance),
          ChangeNotifierProvider.value(
            value: remindersNotifier,
          ),
        ],
        child: MyApp(
          isFirebaseInitialized: globals.isFirebaseInitialized,
          isFcmInitialized: globals.isFcmInitialized,
          isRevenueCatInitialized: globals.isRevenueCatInitialized,
          initializationError: globals.initializationError ?? e.toString(),
        ),
      ),
    );
  }
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
// دوال مساعدة للرسائل والإشعارات
// ============================================================================

// ✅ دالة محسّنة لعرض الرسائل
void _safeShowMessage(String message, {Color? color, bool debugOnly = false}) {
  // 1. طباعة في الـ debug console دائماً
  if (kDebugMode) {
    debugPrint('Main Debug: $message');
  }

  // 2. عرض SnackBar (إذا لم يكن debugOnly فقط)
  if (!debugOnly) {
    // ✅ استخدام PostFrameCallback للتأكد من جاهزية الـ UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // ✅ التحقق من وجود ScaffoldMessenger
        final currentState = scaffoldMessengerKey.currentState;
        if (currentState != null && currentState.mounted) {
          currentState.showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: color ?? Colors.blue,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        // في حالة فشل عرض SnackBar، فقط اطبع الخطأ
        debugPrint('⚠️ Failed to show SnackBar: $e');
      }
    });
  }
}

// ✅ دالة بديلة للرسائل الفورية (للاستخدام داخل build methods)
void _showImmediateMessage(String message, {Color? color}) {
  try {
    final currentState = scaffoldMessengerKey.currentState;
    if (currentState != null && currentState.mounted) {
      currentState.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color ?? Colors.blue,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    debugPrint('⚠️ Failed to show immediate message: $e');
  }
}

// void _setupMessageHandlers() {
//   if (!globals.isFirebaseInitialized) {
//     _safeShowMessage('⚠️ Skipping message handlers - Firebase not initialized', color: Colors.orange);
//     return;
//   }
  
//     final fcmService = FcmService();
//   try {
//     // معالج المقدمة
//     FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
//       _safeShowMessage('📨 FOREGROUND MESSAGE RECEIVED', color: Colors.blue);
      
//       try {
//         // استخراج البيانات
//         final data = Map<String, dynamic>.from(message.data);
//         final postTitle = data['post_title']?.toString().trim() ?? '';
//         final nextReminderTime = data['next_reminder_time']?.toString() ?? '';
        
//         final title = postTitle.isNotEmpty ? postTitle : 'تذكير';
//         final body = "موعد التذكير التالي: $nextReminderTime";
        
//         // ✅ عرض SnackBar أولاً
//         if (title.isNotEmpty || body.isNotEmpty) {
//           _showFcmNotificationSnackBar(title, body);
//         }

//         // ✅ استخدام instance method بدلاً من static
       
//         await fcmService.processMessage(message, isBackground: false);
        
//         _safeShowMessage('✅ Message processed successfully', color: Colors.green);
        
//       } catch (e, stackTrace) {
//         _safeShowMessage('❌ Error processing message: $e', color: Colors.red);
//         print('Error: $e\nStack: $stackTrace');
//       }
//     }, onError: (error) {
//       _safeShowMessage('❌ Stream error: $error', color: Colors.red);
//     });

//     // معالج فتح التطبيق من إشعار
//     FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
//       _safeShowMessage('📱 App opened from notification', color: Colors.blue);
      
//       try {
//         _handleMessageOpenedApp(message);
//       } catch (e) {
//         _safeShowMessage('❌ Error handling opened app: $e', color: Colors.red);
//       }
//     });

//     // معالج الرسالة الأولية
//     FirebaseMessaging.instance.getInitialMessage().then((initialMessage) {
//       if (initialMessage != null) {
//         _safeShowMessage('📬 Initial message', color: Colors.blue);
        
//         Future.delayed(const Duration(seconds: 2), () {
//           try {
//             _handleMessageOpenedApp(initialMessage);
//           } catch (e) {
//             _safeShowMessage('❌ Error handling initial message: $e', color: Colors.red);
//           }
//         });
//       }
//     });

//     _safeShowMessage('✅ Message handlers configured', color: Colors.green);
    
//   } catch (e, stackTrace) {
//     _safeShowMessage('❌ Setup error: $e', color: Colors.red);
//     print('Error: $e\nStack: $stackTrace');
//   }
// }

// ✅ تحديث معالج الخلفية أيضاً
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('\n🌙 ========== BACKGROUND FCM MESSAGE ==========');
  print('📨 Message ID: ${message.messageId}');
  print('⏰ Sent Time: ${message.sentTime}');
  print('📦 Data Keys: ${message.data.keys.toList()}');
  print('📦 Full Data: ${message.data}');
  print('🔔 Notification Title: ${message.notification?.title}');
  print('🔔 Notification Body: ${message.notification?.body}');
  
  try {
    print('🔄 Step 1: Checking Firebase initialization...');
    if (Firebase.apps.isEmpty) {
      print('   ⚠️ Firebase not initialized - initializing now...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('   ✓ Firebase initialized');
    } else {
      print('   ✓ Firebase already initialized (${Firebase.apps.length} apps)');
    }

    print('🔄 Step 2: Initializing background services...');
    await _initializeBackgroundServices();
    print('   ✓ Background services initialized');

    print('🔄 Step 3: Getting FCM service instance...');
    final fcmService = FcmService.instance;
    print('   ✓ FCM service instance obtained');
    
    print('🔄 Step 4: Processing message...');
    await fcmService.processMessage(message, isBackground: true);
    print('   ✓ Message processed');
    
    print('✅ Background message handled successfully');
    print('==========================================\n');
    
  } catch (e, stackTrace) {
    print('❌ ========== BACKGROUND HANDLER ERROR ==========');
    print('Error: $e');
    print('Stack trace:');
    print(stackTrace);
    print('=================================================\n');
  }
}

// ============================================================================
// دوال التهيئة
// ============================================================================

// تهيئة Firebase بشكل آمن
Future<bool> _initializeFirebaseSafely() async {
  try {
    // _safeShowMessage('🔄 فحص الاتصال بالإنترنت...', debugOnly: true);
    // final hasInternet =
    //     await ConnectivityHelper.checkInternetConnection(verbose: true);
    // if (!hasInternet) {
    //   _safeShowMessage('⚠️ لا يوجد اتصال بالإنترنت - تخطي تهيئة Firebase',
    //       color: Colors.orange);
    //   globals.initializationError = 'لا يوجد اتصال بالإنترنت';
    //   return false;
    // }
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
    globals.isFirebaseInitialized = true;
    return true;
  } catch (e) {
    _safeShowMessage('❌ خطأ في تهيئة Firebase: $e', color: Colors.red);
    globals.initializationError = 'خطأ في تهيئة Firebase: $e';
    globals.isFirebaseInitialized = false;
    return false;
  }
}

// ✅ تحسين _initializeFcmSafely - تهيئة FCM مرة واحدة فقط
Future<bool> _initializeFcmSafely() async {
  try {
    if (!globals.isFirebaseInitialized) {
      _safeShowMessage('⚠️ Firebase not initialized, skipping FCM', color: Colors.orange);
      return false;
    }

    _safeShowMessage('🔄 Initializing FCM Service...', color: Colors.blue);

    // ✅ تهيئة FCM Service مرة واحدة عبر singleton
    final fcmService = FcmService.instance;
    
    // ✅ التهيئة الكاملة عبر FCM service (يتضمن الأذونات والtoken)
    final fcmResult = await fcmService.init().timeout(
      const Duration(seconds: 15),
      onTimeout: () => {
        'fcmToken': null,
        'message': 'FCM initialization timeout',
        'permissionsGranted': false,
      },
    );

    globals.isFcmInitialized = fcmResult['permissionsGranted'] ?? false;
    
    final fcmToken = fcmResult['fcmToken'];
    if (fcmToken != null && fcmToken.toString().length > 20) {
      _safeShowMessage('✅ FCM Token: ${fcmToken.toString().substring(0, 20)}...', color: Colors.green);
    }
    
    _safeShowMessage('✅ FCM initialized: ${globals.isFcmInitialized}', color: Colors.green);
    
    return globals.isFcmInitialized;
    
  } catch (e, stackTrace) {
    _safeShowMessage('❌ FCM initialization error: $e', color: Colors.red);
    debugPrint('Stack trace: $stackTrace');
    globals.isFcmInitialized = false;
    return false;
  }
}

// ============================================================================
// دوال الخدمات في الخلفية
// ============================================================================

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

// ============================================================================
// دوال الإشعارات
// ============================================================================

// ✅ دالة آمنة لعرض إشعارات FCM (محدثة لاستخدام الدالة الجديدة)
void _showFcmNotificationSnackBar(String title, String body) {
  try {
    if (title.isEmpty && body.isEmpty) return;
    
    String message = title.isNotEmpty ? '$title: $body' : body;
    
    // استخدام الدالة الجديدة للرسائل الفورية
    _showImmediateMessage('🔔 Main $message', color: Colors.blue);
  } catch (e) {
    _safeShowMessage('⚠️ Could not show FCM notification: $e', color: Colors.orange);
  }
}

// ✅ تحسين _handleMessageOpenedApp للتعامل مع بنية البيانات الجديدة
void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    _safeShowMessage('🔗 Handling message opened app...', color: Colors.blue);
    
    // استخراج البيانات من الحقول الجديدة
    final data = Map<String, dynamic>.from(message.data);
    final postId = data['post_id']?.toString() ?? '';
    final action = data['action']?.toString().trim() ?? '';
    final postUrl = data['post_url']?.toString().trim() ?? '';
    
    // استخراج معرف التذكير من post_id
    final int? reminderId = postId.isNotEmpty ? int.tryParse(postId) : null;
    
    // التنقل بعد تأخير قصير للسماح بتهيئة التطبيق
    Future.delayed(const Duration(milliseconds: 800), () {
      if (reminderId != null) {
        // التنقل بناءً على نوع الإجراء
        switch (action.toLowerCase().trim()) {
          case 'reminder_updated':
          case 'update':
            navigatorKey.currentState?.pushNamed(
              '/reminder',
              arguments: {'reminderId': reminderId},
            );
            break;
          case 'reschedule':
            navigatorKey.currentState?.pushNamed(
              '/reminder',
              arguments: {'reminderId': reminderId},
            );
            break;
          case 'new':
            navigatorKey.currentState?.pushNamed(
              '/reminder',
              arguments: {'reminderId': reminderId},
            );
            break;
          case 'markas_read':
          case 'mark_as_read':
            navigatorKey.currentState?.pushNamed(
              '/reminder',
              arguments: {'reminderId': reminderId},
            );
            break;
          case 'delete':
            // في حالة الحذف، الانتقال إلى القائمة
            navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/reminders',
              (route) => false,
            );
            break;
          default:
            // فتح الرابط إذا كان متاحًا
            if (postUrl.isNotEmpty) {
              // هنا يمكن إضافة كود لفتح الرابط
              navigatorKey.currentState?.pushNamed(
                '/reminder',
                arguments: {'reminderId': reminderId},
              );
            } else {
              // التنقل الافتراضي
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/reminders',
                (route) => false,
              );
            }
        }
      } else {
        // إذا لم يوجد معرف تذكير، انتقل إلى القائمة
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/reminders',
          (route) => false,
        );
      }
    });
    
  } catch (e) {
    _safeShowMessage('❌ Error in _handleMessageOpenedApp: $e', color: Colors.red);
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
                    isRevenueCatInitialized: globals.isRevenueCatInitialized,
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
            _safeShowMessage('تم تنفيذ تذكير رقم: $reminderId', color: Colors.blue);
          }
          break;
        default:
          _safeShowMessage('مهمة غير معروفة: $task', color: Colors.orange);
      }
      return Future.value(true);
    } catch (e) {
      _safeShowMessage('خطأ في تنفيذ المهمة: $e', color: Colors.red);
      return Future.value(false);
    }
  });
}