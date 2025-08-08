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

// معالج الرسائل في الخلفية - يجب أن يكون في المستوى الأعلى
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // تهيئة Firebase للخلفية
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('=== معالجة رسالة خلفية ===');
  print('Message ID: ${message.messageId}');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Data: ${message.data}');

  try {
    // تهيئة خدمة الإشعارات المحلية
    //await _initializeBackgroundNotifications();

    // معالجة الرسالة وإظهار الإشعار
    await FcmService.processMessage(message, isBackground: true);
  } catch (e) {
    print('خطأ في معالجة الرسالة في الخلفية: $e');

    // إظهار إشعار بديل في حالة الفشل
    await _showFallbackNotification(message);
  }
}

// تهيئة الإشعارات المحلية في الخلفية
Future<void> _initializeBackgroundNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

// معالجة الرسائل في الخلفية
Future<void> _processBackgroundMessage(RemoteMessage message) async {
  final String title =
      message.data['title'] ?? message.notification?.title ?? 'إشعار جديد';
  final String body = message.data['body'] ??
      message.notification?.body ??
      'تم استلام رسالة جديدة';

  // محاولة استخراج معرف التذكير
  int? reminderId;
  try {
    reminderId = int.parse(body.trim());
  } catch (e) {
    // إذا لم يكن body رقماً، نعرض الرسالة كما هي
    await _showBackgroundNotification(title, body, message.data);
    return;
  }

  if (reminderId != null && reminderId > 0) {
    String notificationTitle = '';
    String notificationBody = '';

    // تحديد محتوى الإشعار حسب نوع العملية
    switch (title.toLowerCase().trim()) {
      case 'reschedule':
        notificationTitle = '🔄 إعادة جدولة تذكير';
        notificationBody = 'تم إعادة جدولة التذكير رقم $reminderId';
        break;
      case 'update':
        notificationTitle = '✏️ تحديث تذكير';
        notificationBody = 'تم تحديث التذكير رقم $reminderId';
        break;
      case 'new':
        notificationTitle = '🆕 تذكير جديد';
        notificationBody = 'تم إضافة تذكير جديد رقم $reminderId';
        break;
      case 'markas_read':
      case 'mark_as_read':
        notificationTitle = '✅ تذكير مقروء';
        notificationBody = 'تم وضع علامة "مقروء" على التذكير رقم $reminderId';
        break;
      case 'delete':
        notificationTitle = '🗑️ حذف تذكير';
        notificationBody = 'تم حذف التذكير رقم $reminderId';
        break;
      default:
        notificationTitle = title;
        notificationBody = 'تذكير رقم $reminderId';
    }

    await _showBackgroundNotification(notificationTitle, notificationBody, {
      ...message.data,
      'reminder_id': reminderId.toString(),
      'action': title,
    });
  }
}

// عرض الإشعار في الخلفية
Future<void> _showBackgroundNotification(
    String title, String body, Map<String, dynamic> data) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'scheduled_channel',
    'Scheduled Notifications',
    channelDescription: 'Notifications for scheduled reminders',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    playSound: true,
    enableVibration: true,
    icon: '@mipmap/ic_launcher',
  );

  const DarwinNotificationDetails iosNotificationDetails =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidNotificationDetails,
    iOS: iosNotificationDetails,
  );

  final int notificationId = data['reminder_id'] != null
      ? int.tryParse(data['reminder_id'].toString()) ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000
      : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await flutterLocalNotificationsPlugin.show(
    notificationId,
    title,
    body,
    notificationDetails,
    payload: jsonEncode(data),
  );

  print('✅ تم إظهار الإشعار في الخلفية: $title - $body');
}

// إظهار إشعار بديل في حالة الفشل
Future<void> _showFallbackNotification(RemoteMessage message) async {
  try {
    await _showBackgroundNotification(
      message.notification?.title ?? 'إشعار جديد',
      message.notification?.body ?? 'تم استلام رسالة جديدة',
      message.data,
    );
  } catch (e) {
    print('فشل في إظهار الإشعار البديل: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // **الأهم**: تسجيل معالج الرسائل في الخلفية
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // تهيئة الخدمات
  await NotificationService().init();
  await FcmService().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RemindersNotifier()),
      ],
      child: const MyApp(),
    ),
  );
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
                    builder: (_) => const RemindersScreen()); // Fallback
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
