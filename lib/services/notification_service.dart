import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flex_reminder/utils/consts.dart';
import 'package:http/http.dart' as http;
// ============================================================================
// Type Definitions للـ Callbacks
// ============================================================================

/// Callback يتم استدعاؤه عندما يتم marking reminder as read
typedef OnReminderMarkedAsReadCallback = Future<void> Function(int reminderId);

/// Callback يتم استدعاؤه عندما يتم فتح reminder
typedef OnReminderOpenedCallback = Future<void> Function(int reminderId, String url, bool wasOpened);

/// Callback للتأكيد على جدولة الإشعار
typedef ConfirmationCallback = Future<void> Function(
  Map<String, dynamic> data,
  int? reminderId,
  String status,
);

// ============================================================================
// ✅ تم حذف كل دوال WorkManager Background Tasks من هنا
// تم نقلها إلى: lib/background/workmanager_dispatcher.dart
// ============================================================================

// ============================================================================
// NotificationService - Singleton
// ============================================================================

class NotificationService {
  // ============================================================================
  // Singleton Pattern
  // ============================================================================
  
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ============================================================================
  // Platform Channel
  // ============================================================================
  
  static const platform = MethodChannel('com.saadmohammed2000.flex_reminder/alarm');

  // ============================================================================
  // ✅ Callbacks - لفصل الاعتماديات
  // ============================================================================
  
  /// Callback يتم استدعاؤه عندما يتم marking reminder as read محلياً
  OnReminderMarkedAsReadCallback? onReminderMarkedAsRead;
  
  /// Callback يتم استدعاؤه عندما يتم فتح reminder
  OnReminderOpenedCallback? onReminderOpened;
// ============================================================================
// ✅ دالة تأكيد خاصة بجدولة الإشعارات
// ============================================================================

Future<void> _sendSchedulingConfirmation(
  String stage,
  Map<String, dynamic> data,
  bool? success,
  String? error,
) async {
  try {
    final uri = Uri.parse('${AppConstants.API_BASE_URL}/test-fcm-background');
    
    final requestBody = {
      'triggered_at': DateTime.now().toIso8601String(),
      'source': 'NotificationService.scheduleReminder',
      'stage': stage,
      'data': data,
      'success': success,
      'error': error,
    };
    
    await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Password': AppConstants.API_PASSWORD,
        'X-FCM-Background-Test': 'true',
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 5));
    
    debugPrint('📤 Scheduling confirmation: $stage = ${success ?? "null"}');
  } catch (e) {
    debugPrint('⚠️ Failed to send scheduling confirmation: $e');
  }
}
  // ============================================================================
  // Initialization
  // ============================================================================

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
    
    // ✅ تم إزالة تسجيل WorkManager من هنا
    // تم نقله إلى main.dart مع callbackDispatcher المنفصل

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

  // ============================================================================
  // Notification Event Handlers
  // ============================================================================

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreated(
      ReceivedNotification receivedNotification) async {
    debugPrint('Notification created: ${receivedNotification.id}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    debugPrint('Notification displayed: ${receivedNotification.id}');
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceived(
      ReceivedAction receivedAction) async {
    debugPrint('Notification dismissed: ${receivedAction.id}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationActionReceived(
      ReceivedAction receivedAction) async {
    try {
      final payload = receivedAction.payload ?? {};
      final String reminderIdStr = payload['id'] ?? '';
      final String? url = payload['url'];
      final int? reminderId = int.tryParse(reminderIdStr);

      // ============================================================================
      // ✅ استخدام الـ Callback بدلاً من الاعتماد المباشر
      // ============================================================================
      
      if (reminderId != null) {
        // استدعاء الـ callback لـ marking as read (سيتم ربطه من RemindersService)
        await _instance.onReminderMarkedAsRead?.call(reminderId);
        
        // إلغاء الإشعارات
        await NotificationService.instance.cancelReminderNotifications(reminderId);
      }

      // فتح الـ URL
      if (url != null && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            
            // استدعاء callback الفتح الناجح
            if (reminderId != null) {
              await _instance.onReminderOpened?.call(reminderId, url, true);
              await _instance._scheduleMarkReminderAsReadTask(reminderId, url, true);
            }
          } catch (e) {
            // استدعاء callback الفتح الفاشل
            if (reminderId != null) {
              await _instance.onReminderOpened?.call(reminderId, url, false);
              await _instance._scheduleMarkReminderAsReadTask(reminderId, url, false);
            }
          }
        } else {
          if (reminderId != null) {
            await _instance.onReminderOpened?.call(reminderId, url, false);
            await _instance._scheduleMarkReminderAsReadTask(reminderId, url, false);
          }
        }
      }

      // التنقل للـ reminder screen
      if (reminderId != null) {
        final Map<String, dynamic> arguments = {'reminderId': reminderId};
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
      debugPrint('Error in onNotificationActionReceived: $e');
    }
  }

  // ============================================================================
  // Mark As Read Task
  // ============================================================================

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
        debugPrint('Fallback updateStats failed: $fallbackError');
      }
    }
  }

  Future<void> cancelAllMarkReminderAsReadTasks() async {
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      debugPrint('Error cancelling tasks: $e');
    }
  }

  // ============================================================================
  // Scheduling Notifications
  // ============================================================================

  Future<bool> scheduleReminderWithHiddenCheck({
    required int reminderId,
    required String title,
    required String url,
    required DateTime scheduledDate,
    required String importance,
    Map<String, String>? additionalPayload,
    ConfirmationCallback? onConfirmation,
  }) async {
    final bool success = await scheduleReminderNotification(
      reminderId: reminderId,
      title: title,
      url: url,
      scheduledDate: scheduledDate,
      importance: importance,
      additionalPayload: additionalPayload,
    );
    
    if (success && onConfirmation != null) {
      try {
        final Map<String, dynamic> data = {
          'reminderId': reminderId,
          'title': title,
          'url': url,
          'scheduledDate': scheduledDate.toIso8601String(),
          'importance': importance,
          ...?additionalPayload,
        };
        
        await onConfirmation(data, reminderId, 'scheduled_successfully');
      } catch (e) {
        debugPrint('Error sending confirmation: $e');
      }
    }
    
    return success;
  }

// ✅ في notification_service.dart:
Future<bool> scheduleReminderNotification({
  required int reminderId,
  required String title,
  required String url,
  required DateTime scheduledDate,
  required String importance,
  Map<String, String>? additionalPayload,
}) async {
  if (scheduledDate.isBefore(DateTime.now())) {
    return false;
  }

  try {
    // إلغاء الإشعارات القديمة
    await cancelReminderNotifications(reminderId);

    // إنشاء إشعار جديد باستخدام Awesome Notifications
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: reminderId.hashCode,
        channelKey: 'scheduled_channel',
        title: title,
        body: 'Time to review!',
        payload: {
          'id': reminderId.toString(),
          'url': url,
          'importance': importance,
          ...?additionalPayload,
        },
      ),
      schedule: NotificationCalendar.fromDate(
        date: scheduledDate,
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );

    return true;
  } catch (e) {
    debugPrint('❌ Error: $e');
    return false;
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
      final preciseAlarms = prefs.getBool('notification_precise_alarms') ?? true;

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
      debugPrint('Error in _scheduleNotification: $e');
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
      debugPrint('Error in scheduleNotification: $e');
      return false;
    }
  }

  int createUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  // ============================================================================
  // Cancellation
  // ============================================================================

  Future<void> cancelReminderNotifications(int reminderId) async {
    try {
      await platform.invokeMethod('cancelAlarm', {'reminderId': reminderId});
    } catch (e) {
      debugPrint('Error cancelling reminder notifications: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await platform.invokeMethod('cancelAllAlarms');
    } catch (e) {
      debugPrint('Error cancelling all alarms: $e');
    }
    
    await AwesomeNotifications().cancelAll();
    await Workmanager().cancelAll();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');
    await prefs.remove('follow_up_tasks');
  }

  // ============================================================================
  // Update Notifications
  // ============================================================================

  Future<void> updateReminderNotifications(Map<String, dynamic> reminderData) async {
    final reminderId = reminderData['id'] as int?;
    if (reminderId == null) return;

    final nextReminderTimeStr = reminderData['next_reminder_time'] as String?;
    if (nextReminderTimeStr != null && nextReminderTimeStr.isNotEmpty) {
      final scheduledDate = DateTime.parse(nextReminderTimeStr);
      
      if (scheduledDate.isBefore(DateTime.now())) {
        try {
          final Map<String, dynamic> resMap = await ApiService().reschedulePost(
              reminderData['url'] as String? ?? '',
              reminderData['importance'] as String? ?? 'day');
          final String newScheduledTimeStr = resMap['post']['next_reminder_time'];
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
          debugPrint('Error rescheduling: $e');
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
 // ============================================================================
  // ✅ إعادة هذه الدالة لأنها تُستخدم في getServiceStatus()
  // ============================================================================
  
  Future<Map<String, String>> _getFollowUpTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksString = prefs.getString('follow_up_tasks');
    if (tasksString == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(tasksString);
    return decoded.cast<String, String>();
  }

  // ============================================================================
  // Utilities
  // ============================================================================

  Future<List<DateTime>> getScheduledTimesForReminder(int reminderId) async {
    final notificationMap = await _getNotificationMap();
    final notificationIds = notificationMap[reminderId] ?? [];
    List<DateTime> scheduledTimes = [];
    
    for (final id in notificationIds) {
      final notifications = await AwesomeNotifications().listScheduledNotifications();
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

  Future<void> updateNotificationChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('notification_sound_enabled') ?? true;
    final vibrationEnabled = prefs.getBool('notification_vibration_enabled') ?? true;

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
}