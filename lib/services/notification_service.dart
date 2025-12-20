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
import 'package:flutter/services.dart';

// دالة للتعامل مع مهام WorkManager في الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'followUpNotification':
        await _handleFollowUpNotification(inputData);
        break;
      case 'markReminderAsRead':
        await _handleMarkReminderAsRead(inputData);
        break;
      default:
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
      return;
    }
    final String title = inputData['title'] ?? 'تذكير متابعة';
    final String body = inputData['body'] ?? 'هذا تذكير متابعة!';
    final String reminderId = inputData['reminderId']?.toString() ?? '';
    final String url = inputData['url'] ?? '';
    final String importance = inputData['importance'] ?? '';

    // إرسال طلب reschedulePost إلى السيرفر
    try {
      final apiService = ApiService();
      final Map<String, dynamic> rescheduleResult =
          await apiService.reschedulePost(url, importance);

      // التحقق من وجود وقت جديد في الاستجابة
      if (rescheduleResult.containsKey('post') &&
          rescheduleResult['post'].containsKey('next_reminder_time')) {
        final String newReminderTime =
            rescheduleResult['post']['next_reminder_time'];

        // إرسال إشعار متابعة مع المعلومات المحدثة
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'scheduled_channel',
            title: '🔄 $title - تم إعادة الجدولة',
            body: 'تم إعادة جدولة التذكير بنجاح للوقت التالي: $newReminderTime',
            category: NotificationCategory.Reminder,
            notificationLayout: NotificationLayout.Default,
            payload: {
              'id': reminderId,
              'url': url,
              'importance': importance,
              'isFollowUp': 'true',
              'rescheduled': 'true',
              'newReminderTime': newReminderTime,
            },
            criticalAlert: true,
            locked: true,
          ),
        );
      } else {
        // إرسال إشعار متابعة عادي
        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'scheduled_channel',
            title: '🔔 $title - متابعة',
            body: body,
            category: NotificationCategory.Reminder,
            notificationLayout: NotificationLayout.Default,
            payload: {
              'id': reminderId,
              'url': url,
              'importance': importance,
              'isFollowUp': 'true',
            },
            criticalAlert: true,
            locked: true,
          ),
        );
      }
    } catch (apiError) {
      // جدولة إعادة محاولة بعد 30 دقيقة
      final DateTime retryTime =
          DateTime.now().add(const Duration(minutes: 30));
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
        ),
      );

      // حفظ معلومات مهمة إعادة المحاولة
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> followUpTasks = await _getFollowUpTasks();
      followUpTasks[reminderId.toString()] =
          'retry_followUpNotification_$reminderId';
      await prefs.setString('follow_up_tasks', jsonEncode(followUpTasks));

      // إرسال إشعار خطأ مع معلومات إعادة المحاولة
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
    }
  } catch (e) {
    // لا نفعل شيئاً هنا (تم حذف الـ SnackBar)
  }
}

// دالة جديدة للتعامل مع markReminderAsRead في الخلفية
@pragma('vm:entry-point')
Future<void> _handleMarkReminderAsRead(Map<String, dynamic>? inputData) async {
  try {
    if (inputData == null) {
      return;
    }
    final String url = inputData['url'] ?? '';
    final int reminderId = inputData['reminderId'] ?? 0;
    final bool wasOpened = inputData['wasOpened'] ?? true;

    // إرسال طلب updateStats إلى السيرفر
    try {
      final apiService = ApiService();
      await apiService.updateStats(url, wasOpened);
    } catch (apiError) {
      // جدولة إعادة محاولة
      await _scheduleMarkReminderAsReadRetry(reminderId, url, wasOpened);
    }
  } catch (e) {
    // تم حذف الـ SnackBar
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
      ),
    );
  } catch (e) {
    // تم حذف الـ SnackBar
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

  // تم حذف دالة _showSnackBar وجميع دوال showSnackBar (success/error/warning)

  // فحص الاتصال بالإنترنت
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<void> init() async {
    tz.initializeTimeZones();
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

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
    // تم حذف الـ SnackBar
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    // تم حذف الـ SnackBars
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceived(
      ReceivedAction receivedAction) async {
    // تم حذف الـ SnackBar
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationActionReceived(
      ReceivedAction receivedAction) async {
    try {
      final payload = receivedAction.payload ?? {};
      final String reminderIdStr = payload['id'] ?? '';
      final String? url = payload['url'];
      final int? reminderId = int.tryParse(reminderIdStr);

      if (reminderId != null) {
        final remindersNotifier = RemindersNotifier.instance;
        await remindersNotifier.markReminderAsReadLocally(reminderId);
        await NotificationService.instance
            .cancelReminderNotifications(reminderId);
      }

      if (url != null && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (reminderId != null) {
              await _instance._scheduleMarkReminderAsReadTask(
                  reminderId, url, true);
            }
          } catch (e) {
            if (reminderId != null) {
              await _instance._scheduleMarkReminderAsReadTask(
                  reminderId, url, false);
            }
          }
        } else {
          if (reminderId != null) {
            await _instance._scheduleMarkReminderAsReadTask(
                reminderId, url, false);
          }
        }
      }

      if (reminderId != null) {
        final Map<String, dynamic> arguments = {
          'reminderId': reminderId,
        };
        navigatorKey.currentState?.pushNamed('/reminder', arguments: arguments);
      } else {
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
    } catch (e) {
      // تم حذف الـ print
    }
  }

  Future<void> _scheduleMarkReminderAsReadTask(
      int reminderId, String url, bool wasOpened) async {
    try {
      final String taskName =
          'markReminderAsRead_${reminderId}_${DateTime.now().millisecondsSinceEpoch}';

      await Workmanager().registerOneOffTask(
        taskName,
        'markReminderAsRead',
        initialDelay: const Duration(seconds: 10),
        inputData: {
          'reminderId': reminderId,
          'url': url,
          'wasOpened': wasOpened,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } catch (e) {
      try {
        final hasConnection = await _checkInternetConnection();
        if (hasConnection) {
          await ApiService().updateStats(url, wasOpened);
        }
      } catch (fallbackError) {
        // لا نفعل شيئاً
      }
    }
  }

  Future<void> cancelAllMarkReminderAsReadTasks() async {
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      // تم حذف الـ SnackBar
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
    await scheduleReminderNotification(
      reminderId: reminderId,
      title: title,
      url: url,
      scheduledDate: scheduledDate,
      importance: importance,
      additionalPayload: additionalPayload,
    );
  }

  Future<void> scheduleReminderNotification({
    required int reminderId,
    required String title,
    required String url,
    required DateTime scheduledDate,
    required String importance,
    Map<String, String>? additionalPayload,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) {
      return;
    }

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
      // لا نتحقق من النتيجة هنا (تم حذف الـ SnackBars)
    } catch (e) {
      // تم حذف الـ SnackBar
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
      final now = DateTime.now();
      if (scheduledDate.isBefore(now) ||
          scheduledDate.difference(now).inSeconds < 10) {
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
      return false;
    }
  }

  int createUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  Future<void> cancelReminderNotifications(int reminderId) async {
    try {
      await platform.invokeMethod('cancelAlarm', {'reminderId': reminderId});
    } catch (e) {
      // تم حذف الـ SnackBar
    }
  }

  Future<void> updateReminderNotifications(
      Map<String, dynamic> reminderData) async {
    final reminderId = reminderData['id'] as int?;
    if (reminderId == null) {
      return;
    }

    final nextReminderTimeStr = reminderData['next_reminder_time'] as String?;
    if (nextReminderTimeStr != null && nextReminderTimeStr.isNotEmpty) {
      final scheduledDate = DateTime.parse(nextReminderTimeStr);
      if (scheduledDate.isBefore(DateTime.now())) {
        try {
          final Map<String, dynamic> resMap = await ApiService().reschedulePost(
              reminderData['url'] as String? ?? '',
              reminderData['importance'] as String? ?? 'day');
          final String newScheduledTimeStr =
              resMap['post']['next_reminder_time'];
          final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);
          if (newScheduledDate.isAfter(DateTime.now())) {
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
          }
        } catch (e) {
          // تم حذف الـ SnackBar
        }
        return;
      }

      await scheduleReminderNotification(
        reminderId: reminderId,
        title: reminderData['title'] as String? ?? 'تذكير',
        url: reminderData['url'] as String? ?? '',
        scheduledDate: scheduledDate,
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
    try {
      await platform.invokeMethod('cancelAllAlarms');
    } catch (e) {
      // تم حذف الـ SnackBar
    }
    await AwesomeNotifications().cancelAll();
    await Workmanager().cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');
    await prefs.remove('follow_up_tasks');
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
      'markAsReadSystem': 'enabled',
    };
  }

  void printStatus() {
    // تم حذف جميع الـ SnackBars داخل هذه الدالة
  }

  Future<void> updateNotificationChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('notification_sound_enabled') ?? true;
    final vibrationEnabled =
        prefs.getBool('notification_vibration_enabled') ?? true;

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
  }

  void dispose() {
    Workmanager().cancelAll();
  }

  bool _isValidScheduledTime(DateTime scheduledDate, int reminderId) {
    final now = DateTime.now();
    final difference = scheduledDate.difference(now);
    if (difference.isNegative) {
      return false;
    }
    if (difference.inSeconds < 30) {
      return false;
    }
    return true;
  }

  
}