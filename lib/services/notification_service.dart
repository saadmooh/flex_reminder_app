import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart'; // إضافة لـ MethodChannel

// دالة للتعامل مع مهام WorkManager في الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    NotificationService.showSuccessSnackBar(
        '🔄 WorkManager task executing: $task');
    switch (task) {
      case 'followUpNotification':
        await _handleFollowUpNotification(inputData);
        break;
      case 'markReminderAsRead':
        await _handleMarkReminderAsRead(inputData);
        break;
      default:
        NotificationService.showErrorSnackBar('❌ Unknown task: $task');
        return false;
    }
    return true;
  });
}

// دالة للتعامل مع الإشعار التابع وإعادة جدولة المنشور
@pragma('vm:entry-point')
Future<void> _handleFollowUpNotification(
    Map<String, dynamic>? inputData) async {
  try {
    if (inputData == null) {
      NotificationService.showErrorSnackBar(
          '❌ No input data provided for follow-up notification');
      return;
    }

    final String title = inputData['title'] ?? 'تذكير متابعة';
    final String body = inputData['body'] ?? 'هذا تذكير متابعة!';
    final String reminderId = inputData['reminderId']?.toString() ?? '';
    final String url = inputData['url'] ?? '';
    final String importance = inputData['importance'] ?? '';

    NotificationService.showSuccessSnackBar(
        '🔄 Processing follow-up for reminder: $reminderId');

    // إرسال طلب reschedulePost إلى السيرفر
    try {
      NotificationService.showSuccessSnackBar(
          '📡 Sending reschedulePost request to server...');
      NotificationService.showSuccessSnackBar('🔗 URL: $url');
      NotificationService.showSuccessSnackBar('⚡ Importance: $importance');

      final apiService = ApiService();
      final Map<String, dynamic> rescheduleResult =
          await apiService.reschedulePost(url, importance);

      NotificationService.showSuccessSnackBar(
          '✅ Successfully rescheduled post on server');
      NotificationService.showSuccessSnackBar(
          '📅 Server response: $rescheduleResult');

      // التحقق من وجود وقت جديد في الاستجابة
      if (rescheduleResult.containsKey('post') &&
          rescheduleResult['post'].containsKey('next_reminder_time')) {
        final String newReminderTime =
            rescheduleResult['post']['next_reminder_time'];
        NotificationService.showSuccessSnackBar(
            '🕐 New reminder time received: $newReminderTime');

        // إرسال إشعار متابعة مع المعلومات المحدثة
        // await AwesomeNotifications().createNotification(
        //   content: NotificationContent(
        //     id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        //     channelKey: 'scheduled_channel',
        //     title: '🔄 $title - تم إعادة الجدولة',
        //     body: 'تم إعادة جدولة التذكير بنجاح للوقت التالي: $newReminderTime',
        //     category: NotificationCategory.Reminder,
        //     notificationLayout: NotificationLayout.Default,
        //     payload: {
        //       'id': reminderId,
        //       'url': url,
        //       'importance': importance,
        //       'isFollowUp': 'true',
        //       'rescheduled': 'true',
        //       'newReminderTime': newReminderTime,
        //     },
        //     criticalAlert: true,
        //     locked: true,
        //   ),
        // );

        NotificationService.showSuccessSnackBar(
            '📨 Follow-up notification sent with reschedule info');
      } else {
        // إرسال إشعار متابعة عادي في حالة عدم وجود وقت جديد
        // await AwesomeNotifications().createNotification(
        //   content: NotificationContent(
        //     id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        //     channelKey: 'scheduled_channel',
        //     title: '🔔 $title - متابعة',
        //     body: body,
        //     category: NotificationCategory.Reminder,
        //     notificationLayout: NotificationLayout.Default,
        //     payload: {
        //       'id': reminderId,
        //       'url': url,
        //       'importance': importance,
        //       'isFollowUp': 'true',
        //     },
        //     criticalAlert: true,
        //     locked: true,
        //   ),
        // );

        NotificationService.showSuccessSnackBar(
            '📨 Standard follow-up notification sent');
      }
    } catch (apiError) {
      NotificationService.showErrorSnackBar(
          '❌ Error calling reschedulePost API: $apiError');

      // جدولة إعادة محاولة بعد 30 دقيقة
      final DateTime retryTime =
          DateTime.now().add(const Duration(minutes: 30));
      NotificationService.showSuccessSnackBar(
          '🔄 Scheduling retry for reschedulePost at: $retryTime');

      await Workmanager().registerOneOffTask(
        'retry_followUpNotification_$reminderId',
        'followUpNotification',
        initialDelay: const Duration(minutes: 30),
        inputData: {
          'reminderId': reminderId,
          'title': title,
          'body': 'إعادة محاولة جدولة التذكير تلقائياً',
          'url': url,
          'importance': importance,
          'scheduledTime': inputData['scheduledTime'],
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // حفظ معلومات مهمة إعادة المحاولة
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> followUpTasks = await _getFollowUpTasks();
      followUpTasks[reminderId.toString()] =
          'retry_followUpNotification_$reminderId';
      await prefs.setString('follow_up_tasks', jsonEncode(followUpTasks));
      NotificationService.showSuccessSnackBar(
          '✅ Scheduled retry task for reminder $reminderId');

      // إرسال إشعار لإعلام المستخدم بمحاولة إعادة الجدولة
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'scheduled_channel',
          title: '⚠️ $title - خطأ في الجدولة',
          body:
              'لم يتم إعادة الجدولة بسبب خطأ في الاتصال. سيتم المحاولة مجدداً بعد 30 دقيقة.',
          category: NotificationCategory.Reminder,
          notificationLayout: NotificationLayout.Default,
          payload: {
            'id': reminderId,
            'url': url,
            'importance': importance,
            'isFollowUp': 'true',
            'error': 'api_failed',
            'retryScheduled': 'true',
            'retryTime': retryTime.toIso8601String(),
          },
          criticalAlert: true,
          locked: true,
        ),
      );

      NotificationService.showSuccessSnackBar(
          '📨 Error follow-up notification sent with retry info');
    }

    NotificationService.showSuccessSnackBar(
        '✅ Follow-up processing completed for reminder: $reminderId');
  } catch (e) {
    NotificationService.showErrorSnackBar(
        '❌ Error in follow-up notification handler: $e');
  }
}

// دالة جديدة للتعامل مع markReminderAsRead في الخلفية
@pragma('vm:entry-point')
Future<void> _handleMarkReminderAsRead(Map<String, dynamic>? inputData) async {
  try {
    if (inputData == null) {
      NotificationService.showErrorSnackBar(
          '❌ No input data provided for markReminderAsRead');
      return;
    }
    final String url = inputData['url'] ?? '';
    final int reminderId = inputData['reminderId'] ?? 0;
    final bool wasOpened = inputData['wasOpened'] ?? true;
    NotificationService.showSuccessSnackBar(
        '📖 Processing markReminderAsRead for reminder: $reminderId');
    NotificationService.showSuccessSnackBar('🌐 URL: $url');
    NotificationService.showSuccessSnackBar('👁️ Was Opened: $wasOpened');
    // إرسال طلب updateStats إلى السيرفر
    try {
      final apiService = ApiService();
      await apiService.updateStats(url, wasOpened);
      NotificationService.showSuccessSnackBar(
          '✅ Successfully sent updateStats to server');
    } catch (apiError) {
      NotificationService.showErrorSnackBar(
          '❌ Error in markReminderAsRead API calls: $apiError');

      // جدولة إعادة محاولة بعد 30 ثانية
      await _scheduleMarkReminderAsReadRetry(reminderId, url, wasOpened);
    }
  } catch (e) {
    NotificationService.showErrorSnackBar(
        '❌ Error in markReminderAsRead handler: $e');
  }
}

// جدولة إعادة محاولة لـ markReminderAsRead
@pragma('vm:entry-point')
Future<void> _scheduleMarkReminderAsReadRetry(
    int reminderId, String url, bool wasOpened) async {
  try {
    final String retryTaskName = 'retry_markReminderAsRead_$reminderId';

    await Workmanager().registerOneOffTask(
      retryTaskName,
      'markReminderAsRead',
      initialDelay: const Duration(seconds: 30),
      inputData: {
        'reminderId': reminderId,
        'url': url,
        'wasOpened': wasOpened,
        'isRetry': true,
      },
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    NotificationService.showSuccessSnackBar(
        '🔄 Scheduled retry for markReminderAsRead: $retryTaskName');
  } catch (e) {
    NotificationService.showErrorSnackBar(
        '❌ Error scheduling markReminderAsRead retry: $e');
  }
}

// الحصول على معلومات مهام المتابعة
Future<Map<String, String>> _getFollowUpTasks() async {
  final prefs = await SharedPreferences.getInstance();
  final String? tasksString = prefs.getString('follow_up_tasks');
  if (tasksString == null) return {};
  final Map<String, dynamic> decoded = jsonDecode(tasksString);
  return decoded.cast<String, String>();
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const platform =
      MethodChannel('com.saadmohammed2000.flex_reminder/alarm');

  static void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey.currentContext != null) {
      // إذا كان التطبيق مفتوحًا، أظهر Snackbar
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey.currentContext!);
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
      // Fallback: طباعة الرسالة في الخلفية (لا Snackbar)
      print('📱 Snackbar fallback (app in background): $message');
    }
  }

  // الدوال المساعدة الآن static (تعمل مباشرة بدون instance)
  static void showSuccessSnackBar(String message) {
    _showSnackBar(message, Colors.green);
  }

  static void showErrorSnackBar(String message) {
    _showSnackBar(message, Colors.red);
  }

  static void showWarningSnackBar(String message) {
    _showSnackBar(message, Colors.orange);
  }

  // فحص الاتصال بالإنترنت
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ خطأ في فحص الاتصال بالإنترنت: $e');
      return false;
    }
  }

  Future<void> init() async {
    tz.initializeTimeZones();

    // تهيئة WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // الاحتفاظ بـ AwesomeNotifications للإشعارات العامة أو الـ listeners إذا لزم الأمر
    await AwesomeNotifications().initialize(
      'resource://drawable/notification',
      [
        NotificationChannel(
          channelKey: 'scheduled_channel',
          channelName: 'الإشعارات المجدولة',
          channelDescription: 'قناة للتذكيرات المجدولة',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          locked: true,
          playSound: true,
          defaultRingtoneType: DefaultRingtoneType.Notification,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
          criticalAlerts: true,
          enableLights: true,
        ),
      ],
    );

    bool allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    AwesomeNotifications().setListeners(
      onActionReceivedMethod: onNotificationActionReceived,
      onNotificationCreatedMethod: onNotificationCreated,
      onNotificationDisplayedMethod: onNotificationDisplayed,
      onDismissActionReceivedMethod: onDismissActionReceived,
    );
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreated(
      ReceivedNotification receivedNotification) async {
    NotificationService.showSuccessSnackBar(
        '📝 Notification created: ${receivedNotification.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    NotificationService.showSuccessSnackBar(
        '📱 Notification displayed: ${receivedNotification.title} at ${DateTime.now()}');
    NotificationService.showSuccessSnackBar(
        '🔔 حان وقت التذكير: ${receivedNotification.title}');
    NotificationService.showSuccessSnackBar(
        '🔔 Main reminder notification: ${receivedNotification.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceived(
      ReceivedAction receivedAction) async {
    NotificationService.showErrorSnackBar(
        '❌ Notification dismissed: ${receivedAction.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationActionReceived(
      ReceivedAction receivedAction) async {
    NotificationService.showSuccessSnackBar(
        '👆 Notification tapped: ${receivedAction.title}');
    final payload = receivedAction.payload ?? {};
    final String reminderIdStr = payload['id'] ?? '';
    final String? url = payload['url'];
    final int? reminderId = int.tryParse(reminderIdStr);

    // === START: التعديلات الجديدة ===
    if (reminderId != null) {
      // 1. تحديث الواجهة فوراً بشكل استباقي
      // نحصل على نسخة RemindersNotifier ونقوم بالتحديث المحلي
      final remindersNotifier = RemindersNotifier.instance;
      await remindersNotifier.markReminderAsReadLocally(reminderId);

      // 2. إلغاء أي إشعارات مستقبلية لهذا التذكير لأنه أصبح مقروءاً
      await NotificationService.instance
          .cancelReminderNotifications(reminderId);
      NotificationService.showSuccessSnackBar(
          '✅ تم إلغاء الإشعارات المتبقية للتذكير $reminderId.');
    }
    // === END: التعديلات الجديدة ===

    // فتح الرابط فوراً للمستخدم (أولوية قصوى)
    if (url != null && url.isNotEmpty) {
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          NotificationService.showSuccessSnackBar(
              '🌐 Successfully launched URL immediately: $url');

          // جدولة مهمة في الخلفية لتحديث بيانات السيرفر (تبقى كما هي)
          if (reminderId != null) {
            await _instance._scheduleMarkReminderAsReadTask(
                reminderId, url, true);
          }
        } catch (e) {
          NotificationService.showErrorSnackBar('❌ Error launching URL: $e');
          NotificationService.showErrorSnackBar('خطأ في فتح الرابط: $url');

          // حتى لو فشل فتح الرابط، نحدث بيانات السيرفر
          if (reminderId != null) {
            await _instance._scheduleMarkReminderAsReadTask(
                reminderId, url, false);
          }
        }
      } else {
        NotificationService.showErrorSnackBar(
            '❌ Invalid or unsupported URL: $url');
        NotificationService.showErrorSnackBar('الرابط غير صالح: $url');

        // تحديث البيانات حتى لو كان الرابط غير صالح
        if (reminderId != null) {
          await _instance._scheduleMarkReminderAsReadTask(
              reminderId, url, false);
        }
      }
    } else {
      NotificationService.showWarningSnackBar('⚠️ No URL provided in payload');
    }

    // التنقل إلى صفحة التذكير (يبقى كما هو)
    if (reminderId != null) {
      final Map<String, dynamic> arguments = {
        'reminderId': reminderId,
      };
      navigatorKey.currentState?.pushNamed('/reminder', arguments: arguments);
      NotificationService.showSuccessSnackBar(
          '🔗 Navigated to reminder page with ID: $reminderId');
    } else {
      NotificationService.showErrorSnackBar(
          '❌ Could not retrieve reminder ID from payload');
      // إنشاء Reminder object كما هو موجود في الكود الأصلي
      final Reminder reminder = Reminder(
        id: receivedAction.id!,
        userId: 0,
        url: payload['url'] ?? '',
        title: receivedAction.title ?? 'تذكير',
        content: payload['content'] ?? '',
        imageUrl: payload['imageUrl'] ?? '',
        importance: payload['importance'] ?? '',
        scheduledTimes: (payload['scheduledTimes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        nextReminderTime: payload['nextReminderTime'] ?? '',
        isOpened: 1,
        createdAt: payload['createdAt'] ?? '',
        updatedAt: payload['updatedAt'] ?? '',
        category: payload['category'] ?? '',
        complexity: payload['complexity'] ?? '',
        domain: payload['domain'] ?? '',
      );
      navigatorKey.currentState?.pushNamed('/reminder', arguments: reminder);
    }
  }

  // دالة جديدة لجدولة مهمة markReminderAsRead
  Future<void> _scheduleMarkReminderAsReadTask(
      int reminderId, String url, bool wasOpened) async {
    try {
      final String taskName =
          'markReminderAsRead_${reminderId}_${DateTime.now().millisecondsSinceEpoch}';

      NotificationService.showSuccessSnackBar(
          '📋 Scheduling markReminderAsRead task: $taskName');
      NotificationService.showSuccessSnackBar('🆔 Reminder ID: $reminderId');
      NotificationService.showSuccessSnackBar('🌐 URL: $url');
      NotificationService.showSuccessSnackBar('👁️ Was Opened: $wasOpened');

      await Workmanager().registerOneOffTask(
        taskName,
        'markReminderAsRead',
        initialDelay: const Duration(seconds: 10), // تأخير 10 ثواني
        inputData: {
          'reminderId': reminderId,
          'url': url,
          'wasOpened': wasOpened,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      NotificationService.showSuccessSnackBar(
          '✅ Successfully scheduled markReminderAsRead task');
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ Error scheduling markReminderAsRead task: $e');

      // في حالة فشل الجدولة، نحاول إرسال الطلب مباشرة
      try {
        NotificationService.showSuccessSnackBar(
            '🔄 Attempting immediate API call as fallback...');
        final hasConnection = await _checkInternetConnection();

        if (hasConnection) {
          await ApiService().updateStats(url, wasOpened);
          NotificationService.showSuccessSnackBar(
              '✅ Fallback API calls successful');
        } else {
          NotificationService.showErrorSnackBar(
              '❌ No internet connection for fallback');
        }
      } catch (fallbackError) {
        NotificationService.showErrorSnackBar(
            '❌ Fallback API call failed: $fallbackError');
      }
    }
  }

  // إضافة دالة للإلغاء الشامل للمهام الجديدة
  Future<void> cancelAllMarkReminderAsReadTasks() async {
    try {
      NotificationService.showSuccessSnackBar(
          '🧹 Canceling all markReminderAsRead tasks...');

      // إلغاء جميع المهام التي تحتوي على markReminderAsRead
      await Workmanager().cancelAll();

      NotificationService.showSuccessSnackBar(
          '✅ All markReminderAsRead tasks canceled');
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ Error canceling markReminderAsRead tasks: $e');
    }
  }

  Future<void> scheduleReminderWithHiddenCheck({
    required int reminderId,
    required String title,
    required String url,
    required DateTime scheduledDate,
    required String importance,
    Map<String, String>? additionalPayload,
  }) async {
    NotificationService.showSuccessSnackBar(
        '🔧 Starting hidden check scheduling for reminder $reminderId');

    await scheduleReminderNotification(
      reminderId: reminderId,
      title: title,
      url: url,
      scheduledDate: scheduledDate,
      importance: importance,
      additionalPayload: additionalPayload,
    );

    NotificationService.showSuccessSnackBar(
        '✅ تم جدولة التذكير المخفي بنجاح لـ $title');
  }

  Future<void> scheduleReminderNotification({
    required int reminderId,
    required String title,
    required String url,
    required DateTime scheduledDate,
    required String importance,
    Map<String, String>? additionalPayload,
  }) async {
    NotificationService.showSuccessSnackBar(
        '🔧 Scheduling reminder $reminderId: $title for: $scheduledDate');
    if (scheduledDate.isBefore(DateTime.now())) {
      NotificationService.showWarningSnackBar(
          '⚠️ Scheduled time is in the past: $scheduledDate');
      return;
    }
    // إلغاء أي إنذارات سابقة
    await cancelReminderNotifications(reminderId);
    try {
      final result = await platform.invokeMethod('scheduleAlarm', {
        'reminderId': reminderId,
        'title': title,
        'body': 'حان وقت التذكير!',
        'url': url,
        'importance': importance,
        'scheduledTime': scheduledDate.millisecondsSinceEpoch,
      });
      if (result == true) {
        NotificationService.showSuccessSnackBar(
            '✅ Successfully scheduled alarm for reminder $reminderId');
      } else {
        NotificationService.showErrorSnackBar(
            '❌ Failed to schedule alarm for reminder $reminderId');
      }
    } catch (e) {
      NotificationService.showErrorSnackBar('❌ Error scheduling alarm: $e');
    }
  }

  Future<bool> _scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String channelKey,
    String? summary,
    Map<String, String>? payload,
  }) async {
    try {
      final int notificationId = createUniqueId();
      NotificationService.showSuccessSnackBar(
          '🆔 Created notification with ID: $notificationId');

      final now = DateTime.now();
      if (scheduledDate.isBefore(now) ||
          scheduledDate.difference(now).inSeconds < 10) {
        NotificationService.showErrorSnackBar(
            '❌ Invalid notification time: $scheduledDate (current: $now)');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final wakeUpScreen = prefs.getBool('notification_wake_screen') ?? true;
      final preciseAlarms =
          prefs.getBool('notification_precise_alarms') ?? true;

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: channelKey,
          title: title,
          body: body,
          summary: summary,
          wakeUpScreen: wakeUpScreen,
          category: NotificationCategory.Reminder,
          notificationLayout: NotificationLayout.Default,
          payload: payload,
          criticalAlert: true,
          locked: true,
        ),
        schedule: NotificationCalendar.fromDate(
          date: scheduledDate,
          allowWhileIdle: true,
          preciseAlarm: preciseAlarms,
        ),
      );

      NotificationService.showSuccessSnackBar(
          '📅 Notification scheduled for: $scheduledDate');

      if (payload != null && payload.containsKey('id')) {
        final reminderId = int.parse(payload['id']!);
        final notificationMap = await _getNotificationMap();
        if (!notificationMap.containsKey(reminderId)) {
          notificationMap[reminderId] = [];
        }
        notificationMap[reminderId]!.add(notificationId);
        await _saveNotificationMap(notificationMap);
      }

      return true;
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ Error scheduling notification: $e');
      return false;
    }
  }

  Future<bool> scheduleNotification({
    required String title,
    required String body,
    DateTime? scheduledDate,
    required String channelKey,
    String? summary,
    Map<String, String>? payload,
    bool isPostNotification = false,
  }) async {
    try {
      final DateTime finalScheduledDate =
          scheduledDate ?? DateTime.now().add(const Duration(seconds: 5));
      return await _scheduleNotification(
        title: title,
        body: body,
        scheduledDate: finalScheduledDate,
        channelKey: channelKey,
        summary: summary,
        payload: payload,
      );
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ Error scheduling notification: $e');
      return false;
    }
  }

  int createUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  Future<void> cancelReminderNotifications(int reminderId) async {
    try {
      await platform.invokeMethod('cancelAlarm', {'reminderId': reminderId});
      NotificationService.showSuccessSnackBar(
          '🗑️ Cancelled alarm for reminder $reminderId');
    } catch (e) {
      NotificationService.showErrorSnackBar('❌ Error cancelling alarm: $e');
    }
  }

  Future<void> updateReminderNotifications(
      Map<String, dynamic> reminderData) async {
    final reminderId = reminderData['id'] as int?;
    if (reminderId == null) {
      NotificationService.showErrorSnackBar(
          '❌ Cannot update notifications: Missing reminder ID');
      return;
    }

    NotificationService.showSuccessSnackBar(
        '🔄 Updating notifications for reminder $reminderId');

    final nextReminderTimeStr = reminderData['next_reminder_time'] as String?;
    if (nextReminderTimeStr != null && nextReminderTimeStr.isNotEmpty) {
      final scheduledDate = DateTime.parse(nextReminderTimeStr);

      if (scheduledDate.isBefore(DateTime.now())) {
        NotificationService.showWarningSnackBar(
            '⚠️ Notification time is in the past: $nextReminderTimeStr');
        NotificationService.showWarningSnackBar(
            '⚠️ Current time: ${DateTime.now()}');
        NotificationService.showSuccessSnackBar(
            '🔄 Requesting reschedule from server...');

        try {
          final Map<String, dynamic> resMap = await ApiService().reschedulePost(
              reminderData['url'] as String? ?? '',
              reminderData['importance'] as String? ?? 'day');
          final String newScheduledTimeStr =
              resMap['post']['next_reminder_time'];
          final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);

          if (newScheduledDate.isAfter(DateTime.now())) {
            NotificationService.showSuccessSnackBar(
                '📅 Received new scheduled time: $newScheduledDate');
            await scheduleReminderNotification(
              reminderId: reminderId,
              title: reminderData['title'] as String? ?? 'تذكير',
              url: reminderData['url'] as String? ?? '',
              scheduledDate: newScheduledDate,
              importance: reminderData['importance'] as String? ?? 'day',
              additionalPayload: {
                'content': reminderData['content']?.toString() ?? '',
                'imageUrl': reminderData['image_url']?.toString() ?? '',
                'createdAt': reminderData['created_at']?.toString() ?? '',
                'updatedAt': reminderData['updated_at']?.toString() ?? '',
                'category': reminderData['category']?.toString() ?? '',
                'complexity': reminderData['complexity']?.toString() ?? '',
                'domain': reminderData['domain']?.toString() ?? '',
              },
            );
            return;
          } else {
            NotificationService.showErrorSnackBar(
                '❌ New scheduled time is also in the past: $newScheduledDate');
          }
        } catch (e) {
          NotificationService.showErrorSnackBar('❌ Error rescheduling: $e');
        }

        NotificationService.showErrorSnackBar(
            '❌ Will not schedule reminder $reminderId');
        return;
      }

      final title = reminderData['title'] as String? ?? 'تذكير';
      final url = reminderData['url'] as String? ?? '';
      final importance = reminderData['importance'] as String? ?? 'day';

      await scheduleReminderNotification(
        reminderId: reminderId,
        title: title,
        url: url,
        scheduledDate: scheduledDate,
        importance: importance,
        additionalPayload: {
          'content': reminderData['content']?.toString() ?? '',
          'imageUrl': reminderData['image_url']?.toString() ?? '',
          'createdAt': reminderData['created_at']?.toString() ?? '',
          'updatedAt': reminderData['updated_at']?.toString() ?? '',
          'category': reminderData['category']?.toString() ?? '',
          'complexity': reminderData['complexity']?.toString() ?? '',
          'domain': reminderData['domain']?.toString() ?? '',
        },
      );

      NotificationService.showSuccessSnackBar(
          '✅ Updated reminder $reminderId for time: $nextReminderTimeStr');
    } else {
      NotificationService.showWarningSnackBar(
          '⚠️ Cannot update notifications: Missing next_reminder_time');
    }
  }

  Future<List<DateTime>> getScheduledTimesForReminder(int reminderId) async {
    final notificationMap = await _getNotificationMap();
    final notificationIds = notificationMap[reminderId] ?? [];
    List<DateTime> scheduledTimes = [];

    for (final id in notificationIds) {
      final notifications =
          await AwesomeNotifications().listScheduledNotifications();
      for (final notification in notifications) {
        if (notification.content?.id == id) {
          final schedule = notification.schedule;
          if (schedule is NotificationCalendar) {
            final scheduledDate = DateTime(
              schedule.year ?? DateTime.now().year,
              schedule.month ?? DateTime.now().month,
              schedule.day ?? DateTime.now().day,
              schedule.hour ?? 0,
              schedule.minute ?? 0,
              schedule.second ?? 0,
              schedule.millisecond ?? 0,
            );
            scheduledTimes.add(scheduledDate);
          }
        }
      }
    }

    return scheduledTimes;
  }

  Future<void> cancelAllNotifications() async {
    NotificationService.showSuccessSnackBar(
        '🧹 Canceling all notifications and tasks');

    // إلغاء جميع الإنذارات عبر AlarmManager
    try {
      await platform.invokeMethod('cancelAllAlarms');
    } catch (e) {
      NotificationService.showErrorSnackBar(
          '❌ Error cancelling all alarms: $e');
    }

    await AwesomeNotifications().cancelAll();
    await Workmanager().cancelAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');
    await prefs.remove('follow_up_tasks');

    NotificationService.showSuccessSnackBar(
        '✅ Successfully canceled all notifications and tasks');
  }

  Future<bool> checkPermissions() async {
    return await AwesomeNotifications().isNotificationAllowed();
  }

  Future<bool> requestPermissions() async {
    return await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  Future<void> _saveNotificationMap(Map<int, List<int>> notificationMap) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> stringKeyMap = notificationMap.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    await prefs.setString('notification_map', jsonEncode(stringKeyMap));
  }

  Future<Map<int, List<int>>> _getNotificationMap() async {
    final prefs = await SharedPreferences.getInstance();
    final String? mapString = prefs.getString('notification_map');
    if (mapString == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(mapString);
    return decoded.map(
      (key, value) => MapEntry(int.parse(key), (value as List).cast<int>()),
    );
  }

  Future<Map<String, dynamic>> getServiceStatus() async {
    final notificationMap = await _getNotificationMap();
    final followUpTasks = await _getFollowUpTasks();

    return {
      'activeReminders': notificationMap.length,
      'scheduledFollowUps': followUpTasks.length,
      'markAsReadSystem': 'enabled', // مؤشر جديد
    };
  }

  void printStatus() {
    NotificationService.showSuccessSnackBar(
        '📊 === Notification Service Status ===');
    NotificationService.showSuccessSnackBar('🔔 Notification service active');
    NotificationService.showSuccessSnackBar(
        '⚙️ WorkManager integration enabled');
    NotificationService.showSuccessSnackBar('🌐 API reschedule calls enabled');
    NotificationService.showSuccessSnackBar(
        '📖 MarkReminderAsRead system enabled'); // سطر جديد
    NotificationService.showSuccessSnackBar(
        '⏱️ Delayed processing: 10 seconds'); // سطر جديد
    NotificationService.showSuccessSnackBar('================================');
  }

  Future<void> updateNotificationChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('notification_sound_enabled') ?? true;
    final vibrationEnabled =
        prefs.getBool('notification_vibration_enabled') ?? true;
    final wakeUpScreen = prefs.getBool('notification_wake_screen') ?? true;
    final preciseAlarms = prefs.getBool('notification_precise_alarms') ?? true;

    await AwesomeNotifications().removeChannel('scheduled_channel');

    await AwesomeNotifications().setChannel(
      NotificationChannel(
        channelKey: 'scheduled_channel',
        channelName: 'الإشعارات المجدولة',
        channelDescription: 'قناة للتذكيرات المجدولة',
        defaultColor: const Color(0xFF9D50DD),
        ledColor: Colors.white,
        importance: NotificationImportance.High,
        locked: true,
        playSound: soundEnabled,
        defaultRingtoneType: DefaultRingtoneType.Notification,
        enableVibration: vibrationEnabled,
      ),
    );

    NotificationService.showSuccessSnackBar(
        '✅ Updated notification channel with new settings');
  }

  void dispose() {
    NotificationService.showSuccessSnackBar(
        '🧹 Cleaning up notification service...');
    Workmanager().cancelAll();
    NotificationService.showSuccessSnackBar('✅ All resources cleaned up');
  }

  bool _isValidScheduledTime(DateTime scheduledDate, int reminderId) {
    final now = DateTime.now();
    final difference = scheduledDate.difference(now);

    NotificationService.showSuccessSnackBar('🕐 Current time: $now');
    NotificationService.showSuccessSnackBar(
        '📅 Scheduled time: $scheduledDate');
    NotificationService.showSuccessSnackBar(
        '⏰ Time difference: ${difference.inMinutes} minutes');

    if (difference.isNegative) {
      NotificationService.showErrorSnackBar(
          '❌ Time is in the past for reminder $reminderId');
      return false;
    }

    if (difference.inSeconds < 30) {
      NotificationService.showWarningSnackBar(
          '⚠️ Time is too close (less than 30 seconds) for reminder $reminderId');
      return false;
    }

    NotificationService.showSuccessSnackBar(
        '✅ Time is valid for scheduling reminder $reminderId');
    return true;
  }
}
