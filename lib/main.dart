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

// إنشاء instance مشترك للـ NotificationService
late NotificationService _backgroundNotificationService;
late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

// معالج الرسائل في الخلفية - محسن مع الجدولة
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // تهيئة Firebase للخلفية إذا لم تكن مهيئة
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    // تهيئة خدمة الإشعارات للخلفية
    await _initializeBackgroundServices();

    // استخراج البيانات من الرسالة
    final String title =
        message.notification?.title ?? message.data['title'] ?? 'تذكير جديد';

    final String body = message.notification?.body ??
        message.data['body'] ??
        'لديك تذكير في انتظارك';

    // محاولة معالجة الرسالة وجدولة الإشعارات
    bool schedulingSuccess = false;

    try {
      // معالجة رسالة FCM
      await FcmService.processMessage(message, isBackground: true);
      // جدولة إشعار فوري (بعد 5 ثوان)
     // await _scheduleFailbackNotification(title, body, message.data);
    } catch (processingError) {
      print('❌ خطأ في معالجة FCM: $processingError');
      schedulingSuccess = false;
      await _scheduleFailbackNotification(title, body, message.data);
    }

    // في حالة فشل الجدولة، جدول إشعار احتياطي

    print('✅ تم معالجة الرسالة في الخلفية بنجاح');
  } catch (e) {
    print('❌ خطأ عام في معالجة الرسالة في الخلفية: $e');
    await _scheduleFailbackNotification(
        "_scheduleEmergencyNotification", "body", message.data);
    // إشعار طوارئ في حالة الفشل الكامل
    //  await _scheduleEmergencyNotification(message);
  }
}

// تهيئة الخدمات في الخلفية
Future<void> _initializeBackgroundServices() async {
  try {
    // تهيئة NotificationService
    _backgroundNotificationService = NotificationService();
    await _backgroundNotificationService.init();

    // تهيئة FlutterLocalNotifications
    await _initializeLocalNotifications();

    print('✅ تم تهيئة الخدمات في الخلفية');
  } catch (e) {
    print('❌ خطأ في تهيئة الخدمات في الخلفية: $e');
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
        print('تم النقر على الإشعار في الخلفية: ${response.payload}');
        _handleBackgroundNotificationClick(response);
      },
    );

    print('✅ تم تهيئة الإشعارات المحلية في الخلفية');
  } catch (e) {
    print('❌ خطأ في تهيئة الإشعارات المحلية في الخلفية: $e');
  }
}

// جدولة إشعار فوري
Future<bool> _scheduleImmediateNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
  Duration delay = const Duration(seconds: 5),
}) async {
  try {
    final scheduledDate = DateTime.now().add(delay);

    final success = await _backgroundNotificationService.scheduleNotification(
      title: '🔔 $title',
      body: body,
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      payload: {
        'type': 'fcm_immediate',
        'source_data': jsonEncode(data),
        'scheduled_at': scheduledDate.toIso8601String(),
        ...data.map((key, value) => MapEntry(key, value.toString())),
      },
    );

    if (success) {
      print('✅ تم جدولة الإشعار الفوري للوقت: $scheduledDate');
    } else {
      print('❌ فشل في جدولة الإشعار الفوري');
    }

    return success;
  } catch (e) {
    print('❌ خطأ في جدولة الإشعار الفوري: $e');
    return false;
  }
}

// جدولة إشعار متأخر
Future<bool> _scheduleDelayedNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
  Duration delay = const Duration(minutes: 30),
}) async {
  try {
    final scheduledDate = DateTime.now().add(delay);

    final success = await _backgroundNotificationService.scheduleNotification(
      title: '⏰ $title',
      body: body,
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      payload: {
        'type': 'fcm_delayed',
        'source_data': jsonEncode(data),
        'scheduled_at': scheduledDate.toIso8601String(),
        ...data.map((key, value) => MapEntry(key, value.toString())),
      },
    );

    if (success) {
      print('✅ تم جدولة الإشعار المتأخر للوقت: $scheduledDate');
    } else {
      print('❌ فشل في جدولة الإشعار المتأخر');
    }

    return success;
  } catch (e) {
    print('❌ خطأ في جدولة الإشعار المتأخر: $e');
    return false;
  }
}

// جدولة إشعار احتياطي
Future<void> _scheduleFailbackNotification(
    String title, String body, Map<String, dynamic> data) async {
  try {
    print('🔄 جدولة إشعار احتياطي...');

    // إشعار احتياطي فوري
    await _showDirectLocalNotification(
      title: '⚠️ $title (احتياطي)',
      body: '$body - تم استلام الرسالة',
      data: data,
      notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    // إشعار احتياطي مجدول بعد دقيقة
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

// جدولة إشعار طوارئ
Future<void> _scheduleEmergencyNotification(RemoteMessage message) async {
  try {
    print('🚨 جدولة إشعار طوارئ...');

    final title = 'رسالة طوارئ';
    final body = 'تم استلام رسالة ولكن حدث خطأ في المعالجة';

    await _showDirectLocalNotification(
      title: '🚨 $title',
      body: body,
      data: message.data,
      notificationId: 99999, // معرف ثابت للطوارئ
    );

    print('✅ تم إرسال إشعار الطوارئ');
  } catch (e) {
    print('❌ فشل حتى في إرسال إشعار الطوارئ: $e');
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

    print('✅ تم إظهار إشعار محلي مباشر: $title');
  } catch (e) {
    print('❌ خطأ في إظهار الإشعار المحلي المباشر: $e');
  }
}

// معالجة النقر على الإشعار في الخلفية
void _handleBackgroundNotificationClick(NotificationResponse response) {
  try {
    print('👆 تم النقر على إشعار في الخلفية');

    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      print('البيانات: $data');

      // يمكن إضافة منطق التنقل هنا
      // مثل حفظ البيانات لمعالجتها عند فتح التطبيق
    }
  } catch (e) {
    print('❌ خطأ في معالجة النقر على الإشعار: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  
  // تهيئة WorkManager مع إعدادات محسنة
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );
  try {
    print('🚀 بدء تهيئة التطبيق...');

    // تهيئة Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ تم تهيئة Firebase');

    // تسجيل معالج الرسائل في الخلفية قبل أي شيء آخر
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('✅ تم تسجيل معالج الرسائل في الخلفية');

    // تهيئة خدمة الإشعارات
    final notificationService = NotificationService();
    await notificationService.init();
    print('✅ تم تهيئة خدمة الإشعارات');

    // تهيئة FcmService مع إعدادات محسنة
    final fcmService = FcmService();
    final fcmResult = await fcmService.init();
    print('✅ تم تهيئة FCM Service: ${fcmResult['message']}');

    // إعداد معالج الرسائل عندما يكون التطبيق في المقدمة
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📨 وصلت رسالة والتطبيق في المقدمة');

      try {
        // معالجة الرسالة في المقدمة
        await FcmService.processMessage(message, isBackground: false);

        // جدولة إشعار إضافي في المقدمة أيضاً
        await _scheduleForegroundNotification(message, notificationService);
      } catch (e) {
        print('❌ خطأ في معالجة رسالة المقدمة: $e');
      }
    });

    // معالجة النقر على الإشعار عندما يكون التطبيق في الخلفية
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 تم فتح التطبيق من إشعار في الخلفية');
      print('Message data: ${message.data}');

      // معالجة التنقل إلى الصفحة المطلوبة
      _handleMessageOpenedApp(message);
    });

    // التحقق من الرسالة الأولية
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('📬 تم فتح التطبيق من إشعار أولي');
      print('Initial message data: ${initialMessage.data}');

      // معالجة الرسالة الأولية
      Future.delayed(const Duration(seconds: 2), () {
        _handleMessageOpenedApp(initialMessage);
      });
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageManager()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider.value(
            value: RemindersNotifier.instance..navigatorKey = navigatorKey,
          ),
        ],
        child: const MyApp(),
      ),
    );

    print('✅ تم إطلاق التطبيق بنجاح');
  } catch (e) {
    print('❌ خطأ في تهيئة التطبيق: $e');

    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'خطأ في تهيئة التطبيق',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

    // جدولة إشعار بعد 10 ثوان
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

// معالجة فتح التطبيق من إشعار
void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    print('🔗 معالجة فتح التطبيق من إشعار...');

    final data = message.data;

    // التحقق من وجود معرف التذكير
    if (data.containsKey('reminder_id')) {
      final reminderId = int.tryParse(data['reminder_id'].toString());
      if (reminderId != null) {
        // التنقل إلى صفحة التذكير
        Future.delayed(const Duration(milliseconds: 500), () {
          navigatorKey.currentState?.pushNamed('/reminder', arguments: {
            'reminderId': reminderId,
          });
        });
        return;
      }
    }

    // التنقل الافتراضي إلى الصفحة الرئيسية
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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('MyApp build called');
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
                return MaterialPageRoute(builder: (_) => const SplashScreen());
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
                return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
          },
        );
      },
    );
  }
}