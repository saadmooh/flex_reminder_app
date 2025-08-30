import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/pages/auth_screen.dart';
import 'package:flex_reminder/pages/reminders_screen.dart';
import 'package:flex_reminder/pages/reminder_detail_screen.dart';
import 'package:flex_reminder/pages/time_slots_screen.dart';
import 'package:flex_reminder/pages/save_post_screen.dart';
import 'package:flex_reminder/pages/stats_screen.dart';
import 'package:flex_reminder/pages/splash_screen.dart';
import 'package:flex_reminder/globals.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/pages/reset_password_screen.dart';
import 'package:flex_reminder/pages/subscription_management_screen.dart';
import 'package:flex_reminder/pages/email_verification_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flex_reminder/firebase_options.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flex_reminder/utils/consts.dart'; // Added import for AppConstants

// Variables for initialization state
bool _isFirebaseInitialized = false;
bool _isFcmInitialized = false;
bool _isRevenueCatInitialized = false;
String? _initializationError;

// Shared instance for NotificationService
late NotificationService _backgroundNotificationService;
late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

// Background message handler - optimized with scheduling
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

    bool schedulingSuccess = false;
    try {
      await FcmService.processMessage(message, isBackground: true);
    } catch (processingError) {
      print('❌ خطأ في معالجة FCM: $processingError');
      schedulingSuccess = false;
      await _scheduleFailbackNotification(title, body, message.data);
    }

    print('✅ تم معالجة الرسالة في الخلفية بنجاح');
  } catch (e) {
    print('❌ خطأ عام في معالجة الرسالة في الخلفية: $e');
    await _scheduleFailbackNotification(
        "_scheduleEmergencyNotification", "body", message.data);
  }
}

// Safe Firebase initialization
Future<bool> _initializeFirebaseSafely() async {
  try {
    print('🔄 فحص الاتصال بالإنترنت...');
    final hasInternet =
        await ConnectivityHelper.checkInternetConnection(verbose: true);
    if (!hasInternet) {
      print('⚠️ لا يوجد اتصال بالإنترنت - تخطي تهيئة Firebase');
      _initializationError = 'لا يوجد اتصال بالإنترنت';
      return false;
    }

    print('🚀 بدء تهيئة Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('انتهت مهلة تهيئة Firebase'),
    );
    print('✅ تم تهيئة Firebase بنجاح');
    _isFirebaseInitialized = true;
    return true;
  } catch (e) {
    print('❌ خطأ في تهيئة Firebase: $e');
    _initializationError = 'خطأ في تهيئة Firebase: $e';
    _isFirebaseInitialized = false;
    return false;
  }
}

// Safe FCM initialization
Future<bool> _initializeFcmSafely() async {
  try {
    if (!_isFirebaseInitialized) {
      print('⚠️ Firebase غير مهيئ - تخطي تهيئة FCM');
      return false;
    }

    print('🔄 بدء تهيئة FCM...');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('✅ تم تسجيل معالج الرسائل في الخلفية');

    final fcmService = FcmService();
    final fcmResult = await fcmService.init().timeout(
          const Duration(seconds: 8),
          onTimeout: () =>
              {'success': false, 'message': 'انتهت مهلة تهيئة FCM'},
        );
    print('✅ تم تهيئة FCM Service: ${fcmResult['message']}');
    _isFcmInitialized = fcmResult['success'] ?? false;
    return _isFcmInitialized;
  } catch (e) {
    print('❌ خطأ في تهيئة FCM: $e');
    _isFcmInitialized = false;
    return false;
  }
}

// Safe RevenueCat initialization
Future<bool> _initializeRevenueCatSafely() async {
  try {
    print('🔄 بدء تهيئة RevenueCat...');
    await Purchases.configure(
      PurchasesConfiguration("goog_WnLgVtBcHCJndRicBHtliPtJENT"),
    );
    print('✅ تم تهيئة RevenueCat بنجاح');
    _isRevenueCatInitialized = true;
    return true;
  } catch (e) {
    print('❌ خطأ في تهيئة RevenueCat: $e');
    _isRevenueCatInitialized = false;
    return false;
  }
}

// Setup message handlers
void _setupMessageHandlers() {
  if (!_isFirebaseInitialized) {
    print('⚠️ تخطي إعداد معالجات الرسائل - Firebase غير مهيئ');
    return;
  }

  try {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📨 وصلت رسالة والتطبيق في المقدمة');
      try {
        await FcmService.processMessage(message, isBackground: false);
        final notificationService = NotificationService();
        await _scheduleForegroundNotification(message, notificationService);
      } catch (e) {
        print('❌ خطأ في معالجة رسالة المقدمة: $e');
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 تم فتح التطبيق من إشعار في الخلفية');
      print('Message data: ${message.data}');
      _handleMessageOpenedApp(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        print('📬 تم فتح التطبيق من إشعار أولي');
        print('Initial message data: ${initialMessage.data}');
        Future.delayed(const Duration(seconds: 2), () {
          _handleMessageOpenedApp(initialMessage);
        });
      }
    }).catchError((e) {
      print('❌ خطأ في الحصول على الرسالة الأولية: $e');
    });

    print('✅ تم إعداد معالجات الرسائل');
  } catch (e) {
    print('❌ خطأ في إعداد معالجات الرسائل: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    print('✅ تم تهيئة WorkManager');
  } catch (e) {
    print('⚠️ خطأ في تهيئة WorkManager: $e');
  }

  try {
    final notificationService = NotificationService();
    await notificationService.init();
    print('✅ تم تهيئة خدمة الإشعارات');
  } catch (e) {
    print('⚠️ خطأ في تهيئة خدمة الإشعارات: $e');
  }

  final firebaseInitialized = await _initializeFirebaseSafely();
  if (firebaseInitialized) {
    await _initializeFcmSafely();
    _setupMessageHandlers();
  }

  await _initializeRevenueCatSafely();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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

  print('✅ تم إطلاق التطبيق بنجاح');
}

Future<void> _initializeBackgroundServices() async {
  try {
    _backgroundNotificationService = NotificationService();
    await _backgroundNotificationService.init();
    await _initializeLocalNotifications();
    print('✅ تم تهيئة الخدمات في الخلفية');
  } catch (e) {
    print('❌ خطأ في تهيئة الخدمات في الخلفية: $e');
  }
}

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
        print('تم النقر على الإشعار في الخلفية: ${response.payload}');
        _handleBackgroundNotificationClick(response);
      },
    );

    print('✅ تم تهيئة الإشعارات المحلية في الخلفية');
  } catch (e) {
    print('❌ خطأ في تهيئة الإشعارات المحلية في الخلفية: $e');
  }
}

Future<void> _scheduleFailbackNotification(
    String title, String body, Map<String, dynamic> data) async {
  try {
    print('🔄 جدولة إشعار احتياطي...');
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
    print('✅ تم جدولة الإشعار الاحتياطي');
  } catch (e) {
    print('❌ خطأ في جدولة الإشعار الاحتياطي: $e');
  }
}

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
          titleColor: AppConstants.TEXT_COLOR, // Updated to use AppConstants
        ),
        AndroidNotificationAction(
          'dismiss_action',
          'إخفاء',
          titleColor: Colors.red, // Kept as Colors.red for contrast
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
    print('✅ تم إظهار إشعار محلي مباشر: $title');
  } catch (e) {
    print('❌ خطأ في إظهار الإشعار المحلي المباشر: $e');
  }
}

void _handleBackgroundNotificationClick(NotificationResponse response) {
  try {
    print('👆 تم النقر على إشعار في الخلفية');
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      print('البيانات: $data');
    }
  } catch (e) {
    print('❌ خطأ في معالجة النقر على الإشعار: $e');
  }
}

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
    print('✅ تم جدولة إشعار المقدمة للوقت: $scheduledDate');
  } catch (e) {
    print('❌ خطأ في جدولة إشعار المقدمة: $e');
  }
}

void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    print('🔗 معالجة فتح التطبيق من إشعار...');
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
    print('❌ خطأ في معالجة فتح التطبيق من إشعار: $e');
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
    print(
        'MyApp build called - Firebase: $isFirebaseInitialized, FCM: $isFcmInitialized, RevenueCat: $isRevenueCatInitialized');
    return Consumer<LanguageManager>(
      builder: (context, languageManager, child) {
        return MaterialApp(
          title: AppLocalizations.of(context)?.appTitle ?? 'Reminder App',
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            fontFamily: 'arial',
            scaffoldBackgroundColor: AppConstants.SCAFFOLD_BACKGROUND_COLOR,
            cardColor: AppConstants.CARD_COLOR,
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: AppConstants.TEXT_COLOR),
              bodyMedium: TextStyle(color: AppConstants.TEXT_SECONDARY_COLOR),
              displayLarge: TextStyle(
                  color: AppConstants.TEXT_COLOR, fontWeight: FontWeight.bold),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
              labelStyle:
                  const TextStyle(color: AppConstants.TEXT_SECONDARY_COLOR),
              hintStyle:
                  const TextStyle(color: AppConstants.TEXT_SECONDARY_COLOR),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.ELEVATED_BUTTON_COLOR,
                padding: const EdgeInsets.symmetric(
                    horizontal: 48.0, vertical: 16.0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0)),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  foregroundColor: AppConstants.TEXT_BUTTON_COLOR),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppConstants.SCAFFOLD_BACKGROUND_COLOR,
              iconTheme: IconThemeData(color: AppConstants.TEXT_COLOR),
              titleTextStyle: TextStyle(
                  color: AppConstants.TEXT_COLOR,
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
              case '/email-verification':
                final args = settings.arguments as Map<String, dynamic>?;
                final email = args?['email'] as String? ?? '';
                return MaterialPageRoute(
                    builder: (_) => EmailVerificationScreen(email: email));
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
