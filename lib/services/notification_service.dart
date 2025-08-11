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
import 'package:url_launcher/url_launcher.dart'; // Add this import for URL launching

// WorkManager task for handling background rescheduling
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🚀 Starting WorkManager task: $task');

      if (task == 'reschedule_reminder') {
        final String postUrl = inputData?['postUrl'] ?? '';
        final String importance = inputData?['importance'] ?? 'day';
        final String title = inputData?['title'] ?? 'تذكير';
        final int reminderId = inputData?['reminderId'] ?? 0;

        if (postUrl.isEmpty || reminderId == 0) {
          print('❌ Missing data in WorkManager task');
          return false;
        }

        print('🔄 Sending reschedule request for reminder $reminderId');

        final apiService = ApiService();
        final Map<String, dynamic> resMap =
            await apiService.reschedulePost(postUrl, importance);

        final String newScheduledTimeStr = resMap['post']['next_reminder_time'];
        final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);

        print('📅 Received new scheduled time: $newScheduledDate');

        final notificationService = NotificationService();
        await notificationService.scheduleReminderNotification(
          reminderId: reminderId,
          title: title,
          url: postUrl,
          scheduledDate: newScheduledDate,
          importance: importance,
          additionalPayload: inputData?['additionalPayload'] ?? {},
        );

        print('✅ Successfully rescheduled reminder $reminderId');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error in WorkManager task: $e');
      return false;
    }
  });
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

  Future<void> init() async {
    tz.initializeTimeZones();

    await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

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

    final payload = receivedNotification.payload ?? {};

    final Map<String, String> cleanPayload = {};
    payload.forEach((key, value) {
      if (value != null) {
        cleanPayload[key] = value;
      }
    });

    await _instance._scheduleRescheduleTask(cleanPayload);

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

    // Check if URL exists and is valid, then attempt to launch it
    if (url != null && url.isNotEmpty) {
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('🌐 Successfully launched URL: $url');

          // Cancel rescheduling task since the user interacted with the notification
          if (reminderId != null) {
            await _instance._cancelRescheduleTask(reminderId);
            print('✅ Canceled rescheduling task for reminder $reminderId');
          }
          return; // Exit after launching the URL
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

    // Fallback to existing navigation logic if URL is not available or fails
    if (reminderId != null) {
      await _instance._cancelRescheduleTask(reminderId);

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

  Future<void> _scheduleRescheduleTask(Map<String, String> payload) async {
    try {
      final String reminderIdStr = payload['id'] ?? '';
      final int? reminderId = int.tryParse(reminderIdStr);

      if (reminderId == null) {
        print('❌ Cannot schedule rescheduling task: Missing reminder ID');
        return;
      }

      final String postUrl = payload['url'] ?? '';
      final String importance = payload['importance'] ?? 'day';
      final String title = payload['title'] ?? 'تذكير';

      if (postUrl.isEmpty) {
        print('❌ Cannot schedule rescheduling task: Missing URL');
        return;
      }

      print('⏰ Scheduling rescheduling task for reminder $reminderId');

      await Workmanager().registerOneOffTask(
        'reschedule_$reminderId',
        'reschedule_reminder',
        initialDelay: const Duration(minutes: 1),
        inputData: {
          'reminderId': reminderId,
          'postUrl': postUrl,
          'importance': importance,
          'title': title,
          'additionalPayload': Map<String, String>.from(payload),
        },
      );

      print('✅ Scheduled rescheduling task for reminder $reminderId');
    } catch (e) {
      print('❌ Error scheduling rescheduling task: $e');
    }
  }

  Future<void> _cancelRescheduleTask(int reminderId) async {
    try {
      await Workmanager().cancelByUniqueName('reschedule_$reminderId');
      print('✅ Canceled rescheduling task for reminder $reminderId');
    } catch (e) {
      print('❌ Error canceling rescheduling task: $e');
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
    } else {
      print('❌ Failed to schedule reminder $reminderId');
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

    final notificationMap = await _getNotificationMap();
    final notificationIds = notificationMap[reminderId] ?? [];

    print('📱 Canceling ${notificationIds.length} visible notifications');
    for (final id in notificationIds) {
      await AwesomeNotifications().cancel(id);
    }

    await _cancelRescheduleTask(reminderId);

    notificationMap.remove(reminderId);
    await _saveNotificationMap(notificationMap);

    print('✅ Successfully canceled all operations for reminder $reminderId');
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
    print('🧹 Canceling all notifications and WorkManager tasks');

    await AwesomeNotifications().cancelAll();

    await Workmanager().cancelAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');

    print('✅ Successfully canceled all notifications and WorkManager tasks');
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
    print('⚙️ WorkManager initialized for background tasks');
    print('================================');
  }

  Future<Map<String, dynamic>> getServiceStatus() async {
    final notificationMap = await _getNotificationMap();
    return {
      'activeReminders': notificationMap.length,
      'workmanagerEnabled': true,
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