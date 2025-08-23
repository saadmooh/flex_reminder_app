import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// دالة للتعامل مع مهام WorkManager في الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('🔄 WorkManager task executing: $task');

    switch (task) {
      case 'followUpNotification':
        await _handleFollowUpNotification(inputData);
        break;
      default:
        print('❌ Unknown task: $task');
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
      print('❌ No input data provided for follow-up notification');
      return;
    }

    final String title = inputData['title'] ?? 'تذكير متابعة';
    final String body = inputData['body'] ?? 'هذا تذكير متابعة!';
    final String reminderId = inputData['reminderId']?.toString() ?? '';
    final String url = inputData['url'] ?? '';
    final String importance = inputData['importance'] ?? '';

    print('🔄 Processing follow-up for reminder: $reminderId');

    // إرسال طلب reschedulePost إلى السيرفر
    try {
      print('📡 Sending reschedulePost request to server...');
      print('🔗 URL: $url');
      print('⚡ Importance: $importance');

      final apiService = ApiService();
      final Map<String, dynamic> rescheduleResult =
          await apiService.reschedulePost(url, importance);

      print('✅ Successfully rescheduled post on server');
      print('📅 Server response: $rescheduleResult');

      // التحقق من وجود وقت جديد في الاستجابة
      if (rescheduleResult.containsKey('post') &&
          rescheduleResult['post'].containsKey('next_reminder_time')) {
        final String newReminderTime =
            rescheduleResult['post']['next_reminder_time'];
        print('🕐 New reminder time received: $newReminderTime');

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

        print('📨 Follow-up notification sent with reschedule info');
      } else {
        // إرسال إشعار متابعة عادي في حالة عدم وجود وقت جديد
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

        print('📨 Standard follow-up notification sent');
      }
    } catch (apiError) {
      print('❌ Error calling reschedulePost API: $apiError');

      // جدولة إعادة محاولة بعد 30 دقيقة
      final DateTime retryTime =
          DateTime.now().add(const Duration(minutes: 30));
      print('🔄 Scheduling retry for reschedulePost at: $retryTime');

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
      print('✅ Scheduled retry task for reminder $reminderId');

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

      print('📨 Error follow-up notification sent with retry info');
    }

    print('✅ Follow-up processing completed for reminder: $reminderId');
  } catch (e) {
    print('❌ Error in follow-up notification handler: $e');
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

  void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey.currentContext != null) {
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
      print('App not active, SnackBar ignored: $message');
    }
  }

  // فحص الاتصال بالإنترنت
  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      print('❌ خطأ في فحص الاتصال بالإنترنت: $e');
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
    print('📝 Notification created: ${receivedNotification.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    print(
        '📱 Notification displayed: ${receivedNotification.title} at ${DateTime.now()}');
    _instance._showSnackBar(
        '🔔 حان وقت التذكير: ${receivedNotification.title}', Colors.blue);
    print('🔔 Main reminder notification: ${receivedNotification.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceived(
      ReceivedAction receivedAction) async {
    print('❌ Notification dismissed: ${receivedAction.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationActionReceived(
      ReceivedAction receivedAction) async {
    print('👆 Notification tapped: ${receivedAction.title}');

    final payload = receivedAction.payload ?? {};
    final String reminderIdStr = payload['id'] ?? '';
    final String? url = payload['url'];
    final int? reminderId = int.tryParse(reminderIdStr);

    // إرسال طلب updateStats عند النقر على الإشعار
    if (url != null && url.isNotEmpty) {
      try {
        // فحص الاتصال بالإنترنت
        final hasConnection = await _instance._checkInternetConnection();

        if (hasConnection) {
          print('📡 Sending updateStats request from notification tap...');
          await ApiService().updateStats(url, true);
          print('✅ Successfully sent updateStats from notification');

          // تحديث التذكير إذا كان معرف التذكير متوفراً
          if (reminderId != null) {
            print('🔄 Updated reminder stats for ID: $reminderId');
          }
        } else {
          print('❌ No internet connection - updateStats skipped');
          _instance._showSnackBar('لا يوجد اتصال بالإنترنت', Colors.orange);
        }
      } catch (e) {
        print('❌ Error sending updateStats from notification: $e');
        _instance._showSnackBar('خطأ في تحديث الإحصائيات', Colors.red);
      }

      // محاولة فتح الرابط
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('🌐 Successfully launched URL: $url');
          return;
        } catch (e) {
          print('❌ Error launching URL: $e');
          _instance._showSnackBar('خطأ في فتح الرابط: $url', Colors.red);
        }
      } else {
        print('❌ Invalid or unsupported URL: $url');
        _instance._showSnackBar('الرابط غير صالح: $url', Colors.red);
      }
    } else {
      print('⚠️ No URL provided in payload');
    }

    // التنقل إلى صفحة التذكير
    if (reminderId != null) {
      final Map<String, dynamic> arguments = {
        'reminderId': reminderId,
      };
      navigatorKey.currentState?.pushNamed('/reminder', arguments: arguments);
      print('🔗 Navigated to reminder page with ID: $reminderId');
    } else {
      print('❌ Could not retrieve reminder ID from payload');
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
    print('🔧 Scheduling reminder $reminderId: $title for: $scheduledDate');

    if (scheduledDate.isBefore(DateTime.now())) {
      print('⚠️ Scheduled time is in the past: $scheduledDate');
      print('⚠️ Current time: ${DateTime.now()}');
      print('❌ Will not schedule reminder $reminderId');
      return;
    }

    await cancelReminderNotifications(reminderId);

    final Map<String, String> payload = {
      'id': reminderId.toString(),
      'url': url,
      'title': title,
      'importance': importance,
      'nextReminderTime': scheduledDate.toIso8601String(),
      ...?additionalPayload,
    };

    print('📦 Payload: $payload');
    print('🆔 Extracted reminder ID: $reminderId');

    final bool scheduled = await _scheduleNotification(
      title: title,
      body: 'حان وقت التذكير!',
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      summary: 'إشعار التذكير',
      payload: payload,
    );

    if (scheduled) {
      print('✅ Successfully scheduled reminder $reminderId');

      // جدولة إشعار المتابعة باستخدام WorkManager بعد 30 ثانية
      await _scheduleFollowUpNotification(
        reminderId: reminderId,
        title: title,
        url: url,
        importance: importance,
        scheduledDate: scheduledDate,
      );
    } else {
      print('❌ Failed to schedule reminder $reminderId');
    }
  }

  // دالة جديدة لجدولة إشعار المتابعة وطلب إعادة الجدولة
  Future<void> _scheduleFollowUpNotification({
    required int reminderId,
    required String title,
    required String url,
    required String importance,
    required DateTime scheduledDate,
  }) async {
    try {
      final String taskName = 'followUpNotification_$reminderId';

      // حساب التأخير: 30 ثانية بعد وقت الإشعار الأساسي
      final DateTime followUpTime =
          scheduledDate.add(const Duration(seconds: 30));
      final Duration delay = followUpTime.difference(DateTime.now());

      if (delay.isNegative) {
        print('❌ Follow-up time would be in the past, skipping');
        return;
      }

      print('📅 Scheduling follow-up task for: $followUpTime');
      print('⏱️ Delay from now: ${delay.inSeconds} seconds');

      await Workmanager().registerOneOffTask(
        taskName,
        'followUpNotification',
        initialDelay: delay,
        inputData: {
          'reminderId': reminderId,
          'title': title,
          'body': 'سيتم إعادة جدولة هذا التذكير تلقائياً',
          'url': url,
          'importance': importance,
          'scheduledTime': scheduledDate.toIso8601String(),
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      // حفظ معلومات المهمة للإلغاء لاحقاً إذا لزم الأمر
      await _saveFollowUpTask(reminderId, taskName);

      print('✅ Scheduled follow-up with API call for reminder $reminderId');
      print('🌐 API reschedule will be called at: $followUpTime');
    } catch (e) {
      print('❌ Error scheduling follow-up notification: $e');
    }
  }

  // حفظ معلومات مهام المتابعة
  Future<void> _saveFollowUpTask(int reminderId, String taskName) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> followUpTasks = await _getFollowUpTasks();
    followUpTasks[reminderId.toString()] = taskName;
    await prefs.setString('follow_up_tasks', jsonEncode(followUpTasks));
  }

  // الحصول على معلومات مهام المتابعة
  Future<Map<String, String>> _getFollowUpTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksString = prefs.getString('follow_up_tasks');
    if (tasksString == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(tasksString);
    return decoded.cast<String, String>();
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
      print('🆔 Created notification with ID: $notificationId');

      final now = DateTime.now();
      if (scheduledDate.isBefore(now) ||
          scheduledDate.difference(now).inSeconds < 10) {
        print('❌ Invalid notification time: $scheduledDate (current: $now)');
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

      print('📅 Notification scheduled for: $scheduledDate');

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
      print('❌ Error scheduling notification: $e');
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
      print('❌ Error scheduling notification: $e');
      return false;
    }
  }

  int createUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  Future<void> cancelReminderNotifications(int reminderId) async {
    print('🗑️ Canceling all operations for reminder $reminderId');

    // إلغاء الإشعارات العادية
    final notificationMap = await _getNotificationMap();
    final notificationIds = notificationMap[reminderId] ?? [];

    print('📱 Canceling ${notificationIds.length} visible notifications');
    for (final id in notificationIds) {
      await AwesomeNotifications().cancel(id);
    }

    notificationMap.remove(reminderId);
    await _saveNotificationMap(notificationMap);

    // إلغاء مهام المتابعة
    await _cancelFollowUpTask(reminderId);

    print('✅ Successfully canceled all operations for reminder $reminderId');
  }

  // إلغاء مهمة المتابعة
  Future<void> _cancelFollowUpTask(int reminderId) async {
    try {
      final Map<String, String> followUpTasks = await _getFollowUpTasks();
      final String? taskName = followUpTasks[reminderId.toString()];

      if (taskName != null) {
        await Workmanager().cancelByUniqueName(taskName);
        followUpTasks.remove(reminderId.toString());

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('follow_up_tasks', jsonEncode(followUpTasks));

        print('✅ Canceled follow-up task: $taskName');
      }
    } catch (e) {
      print('❌ Error canceling follow-up task: $e');
    }
  }

  Future<void> updateReminderNotifications(
      Map<String, dynamic> reminderData) async {
    final reminderId = reminderData['id'] as int?;
    if (reminderId == null) {
      print('❌ Cannot update notifications: Missing reminder ID');
      return;
    }

    print('🔄 Updating notifications for reminder $reminderId');

    final nextReminderTimeStr = reminderData['next_reminder_time'] as String?;
    if (nextReminderTimeStr != null && nextReminderTimeStr.isNotEmpty) {
      final scheduledDate = DateTime.parse(nextReminderTimeStr);

      if (scheduledDate.isBefore(DateTime.now())) {
        print('⚠️ Notification time is in the past: $nextReminderTimeStr');
        print('⚠️ Current time: ${DateTime.now()}');
        print('🔄 Requesting reschedule from server...');

        try {
          final Map<String, dynamic> resMap = await ApiService().reschedulePost(
              reminderData['url'] as String? ?? '',
              reminderData['importance'] as String? ?? 'day');
          final String newScheduledTimeStr =
              resMap['post']['next_reminder_time'];
          final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);

          if (newScheduledDate.isAfter(DateTime.now())) {
            print('📅 Received new scheduled time: $newScheduledDate');
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
            print(
                '❌ New scheduled time is also in the past: $newScheduledDate');
          }
        } catch (e) {
          print('❌ Error rescheduling: $e');
        }

        print('❌ Will not schedule reminder $reminderId');
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

      print('✅ Updated reminder $reminderId for time: $nextReminderTimeStr');
    } else {
      print('⚠️ Cannot update notifications: Missing next_reminder_time');
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
    print('🧹 Canceling all notifications and tasks');

    await AwesomeNotifications().cancelAll();
    await Workmanager().cancelAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');
    await prefs.remove('follow_up_tasks');

    print('✅ Successfully canceled all notifications and tasks');
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

  void printStatus() {
    print('📊 === Notification Service Status ===');
    print('🔔 Notification service active');
    print('⚙️ WorkManager integration enabled');
    print('🌐 API reschedule calls enabled');
    print('================================');
  }

  Future<Map<String, dynamic>> getServiceStatus() async {
    final notificationMap = await _getNotificationMap();
    final followUpTasks = await _getFollowUpTasks();
    return {
      'activeReminders': notificationMap.length,
      'scheduledFollowUps': followUpTasks.length,
    };
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

    print('✅ Updated notification channel with new settings');
  }

  void dispose() {
    print('🧹 Cleaning up notification service...');
    Workmanager().cancelAll();
    print('✅ All resources cleaned up');
  }

  bool _isValidScheduledTime(DateTime scheduledDate, int reminderId) {
    final now = DateTime.now();
    final difference = scheduledDate.difference(now);

    print('🕐 Current time: $now');
    print('📅 Scheduled time: $scheduledDate');
    print('⏰ Time difference: ${difference.inMinutes} minutes');

    if (difference.isNegative) {
      print('❌ Time is in the past for reminder $reminderId');
      return false;
    }

    if (difference.inSeconds < 30) {
      print(
          '⚠️ Time is too close (less than 30 seconds) for reminder $reminderId');
      return false;
    }

    print('✅ Time is valid for scheduling reminder $reminderId');
    return true;
  }
}
