import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final Map<int, Timer> _pendingTimers = {};
  final Map<int, Timer> _checkTimers = {}; // للفحص الخفي
  final Map<int, int> _attemptCounters = {}; // عداد المحاولات

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
      print('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    }
  }

  Future<void> init() async {
    tz.initializeTimeZones();
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
    print('📝 تم إنشاء الإشعار: ${receivedNotification.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    print(
        '📱 تم عرض الإشعار: ${receivedNotification.title} في ${DateTime.now()}');

    final payload = receivedNotification.payload ?? {};
    final bool isCheckNotification = payload['isCheckNotification'] == 'true';

    if (!isCheckNotification) {
      print('🔔 إشعار تذكير رئيسي: ${receivedNotification.title}');
    } else {
      print('⚠️ إشعار فحص غير متوقع - سيتم تجاهله');
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceived(
      ReceivedAction receivedAction) async {
    print('❌ تم تجاهل الإشعار: ${receivedAction.title}');
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationActionReceived(
      ReceivedAction receivedAction) async {
    print('👆 تم النقر على الإشعار: ${receivedAction.title}');
    _instance._cancelTimerForNotification(receivedAction.id!);

    final payload = receivedAction.payload ?? {};
    final bool isCheckNotification = payload['isCheckNotification'] == 'true';

    if (!isCheckNotification) {
      final String reminderIdStr = payload['id'] ?? '';
      final int? reminderId = int.tryParse(reminderIdStr);
      
      if (reminderId != null) {
        final Map<String, dynamic> arguments = {
          'reminderId': reminderId,
        };
        
        navigatorKey.currentState?.pushNamed('/reminder', arguments: arguments);
        print('🔗 تم توجيه المستخدم لصفحة التذكير بالمعرف: $reminderId');
      } else {
        print('❌ لا يمكن الحصول على معرف التذكير من البيانات المرفقة');
        
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
  }

  void _cancelTimerForNotification(int id) {
    if (_pendingTimers.containsKey(id)) {
      _pendingTimers[id]?.cancel();
      _pendingTimers.remove(id);
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
    print('🔧 جدولة التذكير $reminderId: $title للوقت: $scheduledDate');
    if (scheduledDate.isBefore(DateTime.now())) {
      print('⚠️ الوقت المجدول في الماضي: $scheduledDate');
      print('⚠️ الوقت الحالي: ${DateTime.now()}');
      print('❌ لن يتم جدولة التذكير $reminderId');
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
    
    print('📦 البيانات المرفقة: $payload');
    print('🆔 معرف التذكير المستخرج: $reminderId');

    final bool scheduled = await scheduleReminderNotification(
      title: title,
      body: 'حان وقت التذكير!',
      scheduledDate: scheduledDate,
      channelKey: 'scheduled_channel',
      summary: 'إشعار التذكير',
      payload: payload,
    );

    if (scheduled) {
      final Duration checkDelay = const Duration(hours: 6);
      _scheduleHiddenCheck(
        reminderId: reminderId,
        checkTime: scheduledDate.add(checkDelay),
        postUrl: url,
        title: title,
        importance: importance,
        additionalPayload: additionalPayload,
      );

      print(
          '✅ تم جدولة التذكير $reminderId مع فحص خفي بعد ${checkDelay.inHours} ساعات');
    } else {
      print('❌ فشل في جدولة التذكير $reminderId');
    }
  }

  void _scheduleHiddenCheck({
    required int reminderId,
    required DateTime checkTime,
    required String postUrl,
    required String title,
    required String importance,
    Map<String, String>? additionalPayload,
  }) {
    _checkTimers[reminderId]?.cancel();

    final Duration delay = checkTime.difference(DateTime.now());

    if (delay.isNegative) {
      print('⚡ وقت الفحص في الماضي، تنفيذ فوري للتذكير $reminderId');
      _performBackgroundCheck(
          reminderId, postUrl, title, importance, additionalPayload);
      return;
    }

    _checkTimers[reminderId] = Timer(delay, () {
      _performBackgroundCheck(
          reminderId, postUrl, title, importance, additionalPayload);
    });

    print('⏰ تم جدولة فحص خفي للتذكير $reminderId في: $checkTime');
    print(
        '⏳ المدة المتبقية: ${delay.inHours} ساعة و ${delay.inMinutes % 60} دقيقة');
  }

  Future<void> _performBackgroundCheck(
    int reminderId,
    String postUrl,
    String title,
    String importance,
    Map<String, String>? additionalPayload,
  ) async {
    print('🔍 بدء فحص خفي للتذكير $reminderId في: ${DateTime.now()}');

    final int attempts = _attemptCounters[reminderId] ?? 0;
    print('📊 عدد المحاولات الحالي: $attempts من 5');

    if (attempts >= 5) {
      print(
          '⛔ تم تجاوز الحد الأقصى للمحاولات للتذكير $reminderId - إيقاف نهائي');
      await cancelReminderNotifications(reminderId);
      return;
    }

    try {
      print('🌐 جاري فحص حالة التذكير من الخادم...');
      final fetchedReminder = await ApiService().getReminder(postUrl);

      if (fetchedReminder.isOpened == 1) {
        print('✅ تم فتح التذكير $reminderId بنجاح - إلغاء جميع العمليات');
        await cancelReminderNotifications(reminderId);
      } else {
        print(
            '❌ لم يتم فتح التذكير $reminderId بعد - المحاولة ${attempts + 1}');

        print('🔄 جاري طلب إعادة جدولة من الخادم...');
        final Map<String, dynamic> resMap =
            await ApiService().reschedulePost(postUrl, importance);

        final String newScheduledTimeStr = resMap['post']['next_reminder_time'];
        final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);

        _attemptCounters[reminderId] = attempts + 1;

        print('📅 موعد جديد للتذكير: $newScheduledDate');
        print('🔢 عدد المحاولات الجديد: ${_attemptCounters[reminderId]}');

        await scheduleReminderWithHiddenCheck(
          reminderId: reminderId,
          title: title,
          url: postUrl,
          scheduledDate: newScheduledDate,
          importance: importance,
          additionalPayload: additionalPayload,
        );

        print('🔄 تمت إعادة جدولة التذكير $reminderId بنجاح');
      }
    } catch (e) {
      print('❌ خطأ في الفحص الخفي للتذكير $reminderId: $e');

      if (attempts < 3) {
        print('🔁 إعادة محاولة الفحص بعد 30 دقيقة بسبب الخطأ');
        _scheduleHiddenCheck(
          reminderId: reminderId,
          checkTime: DateTime.now().add(const Duration(minutes: 30)),
          postUrl: postUrl,
          title: title,
          importance: importance,
          additionalPayload: additionalPayload,
        );
      }
    }
  }

  Future<bool> scheduleReminderNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String channelKey,
    String? summary,
    Map<String, String>? payload,
  }) async {
    try {
      final int notificationId = createUniqueId();
      print('🆔 إنشاء إشعار بالمعرف: $notificationId');
      final now = DateTime.now();
      if (scheduledDate.isBefore(now) ||
          scheduledDate.difference(now).inSeconds < 10) {
        print('❌ وقت الإشعار غير صالح: $scheduledDate (الحالي: $now)');
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
          wakeUpScreen: true,
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

      print('📅 تمت جدولة الإشعار لـ: $scheduledDate');

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
      print('❌ خطأ في جدولة الإشعار: $e');
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
      return await scheduleReminderNotification(
        title: title,
        body: body,
        scheduledDate: finalScheduledDate,
        channelKey: channelKey,
        summary: summary,
        payload: payload,
      );
    } catch (e) {
      print('❌ خطأ في جدولة الإشعار: $e');
      return false;
    }
  }

  int createUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(100000);
  }

  Future<void> cancelReminderNotifications(int reminderId) async {
    print('🗑️ إلغاء جميع العمليات للتذكير $reminderId');

    final notificationMap = await _getNotificationMap();
    final notificationIds = notificationMap[reminderId] ?? [];

    print('📱 إلغاء ${notificationIds.length} إشعار مرئي');
    for (final id in notificationIds) {
      await AwesomeNotifications().cancel(id);
    }

    if (_checkTimers.containsKey(reminderId)) {
      _checkTimers[reminderId]?.cancel();
      _checkTimers.remove(reminderId);
      print('⏰ تم إلغاء المؤقت الخفي');
    }

    if (_attemptCounters.containsKey(reminderId)) {
      _attemptCounters.remove(reminderId);
      print('🔢 تم مسح عداد المحاولات');
    }

    notificationMap.remove(reminderId);
    await _saveNotificationMap(notificationMap);

    print('✅ تم إلغاء جميع العمليات للتذكير $reminderId بنجاح');
  }

  Future<void> updateReminderNotifications(
      Map<String, dynamic> reminderData) async {
    final reminderId = reminderData['id'] as int?;
    if (reminderId == null) {
      print('❌ لا يمكن تحديث الإشعارات: معرف التذكير مفقود');
      return;
    }

    print('🔄 تحديث إشعارات التذكير $reminderId');

    final nextReminderTimeStr = reminderData['next_reminder_time'] as String?;
    if (nextReminderTimeStr != null && nextReminderTimeStr.isNotEmpty) {
      final scheduledDate = DateTime.parse(nextReminderTimeStr);

      if (scheduledDate.isBefore(DateTime.now())) {
        print('⚠️ وقت الإشعار في الماضي: $nextReminderTimeStr');
        print('⚠️ الوقت الحالي: ${DateTime.now()}');
        print('🔄 سيتم طلب إعادة جدولة من الخادم...');

        try {
          final Map<String, dynamic> resMap = await ApiService().reschedulePost(
              reminderData['url'] as String? ?? '',
              reminderData['importance'] as String? ?? 'day');
          final String newScheduledTimeStr =
              resMap['post']['next_reminder_time'];
          final DateTime newScheduledDate = DateTime.parse(newScheduledTimeStr);

          if (newScheduledDate.isAfter(DateTime.now())) {
            print('📅 تم الحصول على موعد جديد: $newScheduledDate');
            await scheduleReminderWithHiddenCheck(
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
            print('❌ الموعد الجديد أيضاً في الماضي: $newScheduledDate');
          }
        } catch (e) {
          print('❌ خطأ في إعادة الجدولة: $e');
        }

        print('❌ لن يتم جدولة التذكير $reminderId');
        return;
      }

      final title = reminderData['title'] as String? ?? 'تذكير';
      final url = reminderData['url'] as String? ?? '';
      final importance = reminderData['importance'] as String? ?? 'day';

      _attemptCounters[reminderId] = 0;

      await scheduleReminderWithHiddenCheck(
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

      print('✅ تم تحديث التذكير $reminderId للوقت: $nextReminderTimeStr');
    } else {
      print('⚠️ لا يمكن تحديث الإشعارات: next_reminder_time مفقود');
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
    print('🧹 إلغاء جميع الإشعارات والمؤقتات');

    await AwesomeNotifications().cancelAll();

    for (final timer in _checkTimers.values) {
      timer.cancel();
    }
    _checkTimers.clear();

    _attemptCounters.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_map');

    print('✅ تم إلغاء جميع الإشعارات والمؤقتات بنجاح');
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
    print('📊 === حالة خدمة الإشعارات ===');
    print('🔔 إشعارات نشطة: ${_pendingTimers.length}');
    print('🔍 فحوصات خفية نشطة: ${_checkTimers.length}');
    print('🔢 عدادات المحاولات: ${_attemptCounters.length}');

    for (final entry in _attemptCounters.entries) {
      print('   - التذكير ${entry.key}: ${entry.value} محاولات');
    }

    for (final entry in _checkTimers.entries) {
      print('   - فحص خفي للتذكير ${entry.key}: نشط');
    }
    print('================================');
  }

  Future<Map<String, dynamic>> getServiceStatus() async {
    return {
      'activeNotifications': _pendingTimers.length,
      'hiddenChecks': _checkTimers.length,
      'attemptCounters': Map<int, int>.from(_attemptCounters),
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

    print('✅ تم تحديث قناة الإشعارات بالإعدادات الجديدة');
  }

  void dispose() {
    print('🧹 تنظيف خدمة الإشعارات...');

    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    for (final timer in _checkTimers.values) {
      timer.cancel();
    }

    _pendingTimers.clear();
    _checkTimers.clear();
    _attemptCounters.clear();

    print('✅ تم تنظيف جميع المؤقتات والموارد');
  }

  bool _isValidScheduledTime(DateTime scheduledDate, int reminderId) {
    final now = DateTime.now();
    final difference = scheduledDate.difference(now);

    print('🕐 الوقت الحالي: $now');
    print('📅 الوقت المجدول: $scheduledDate');
    print('⏰ الفرق الزمني: ${difference.inMinutes} دقيقة');

    if (difference.isNegative) {
      print('❌ الوقت في الماضي للتذكير $reminderId');
      return false;
    }

    if (difference.inSeconds < 30) {
      print('⚠️ الوقت قريب جداً (أقل من 30 ثانية) للتذكير $reminderId');
      return false;
    }

    print('✅ الوقت صالح للجدولة للتذكير $reminderId');
    return true;
  }
}