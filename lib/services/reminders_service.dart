import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';

/// Service للتعامل مع منطق الأعمال والعمليات الخلفية للتذكيرات
class RemindersService {
  // ============================================================================
  // Singleton Pattern
  // ============================================================================
  static RemindersService? _instance;
  
  static RemindersService get instance {
    _instance ??= RemindersService._internal();
    return _instance!;
  }

  RemindersService._internal();

  factory RemindersService() => instance;

  // ============================================================================
  // الخدمات والثوابت
  // ============================================================================
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  static const String _categoriesKey = 'cached_categories';
  static const String _complexitiesKey = 'cached_complexities';
  static const String _domainsKey = 'cached_domains';
  static const String _totalKey = 'cached_total';
  static const String _sessionRemindersKeyPrefix = 'session_reminders_page_';
  static const String _lastInitKey = 'last_initialization';

  // ============================================================================
  // دوال التخزين المؤقت (Cache)
  // ============================================================================

  /// تحميل التذكيرات من الصفحة المحددة من التخزين المؤقت
  Future<List<Reminder>> loadCachedReminders(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_sessionRemindersKeyPrefix$page';
      final cachedReminders = prefs.getString(key);

      if (cachedReminders != null && cachedReminders.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedReminders);
          final reminders = remindersList
              .map((r) => Reminder.fromJson(r as Map<String, dynamic>))
              .where((r) => r.id != 0)
              .toList();
          return reminders;
        } catch (parseError) {
          await prefs.remove(key);
          return [];
        }
      }
    } catch (e) {
      // Handle error silently
    }
    return [];
  }

  /// حفظ التذكيرات في صفحة معينة في التخزين المؤقت
  Future<void> cacheRemindersForPage(int page, List<Reminder> reminders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_sessionRemindersKeyPrefix$page';
      final validReminders = reminders.where((r) => r.id != 0).toList();
      if (validReminders.isEmpty) return;
      final remindersJson =
          jsonEncode(validReminders.map((r) => r.toJson()).toList());
      await prefs.setString(key, remindersJson);
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحديث تذكير معين في التخزين المؤقت
  Future<void> updateCachedReminder(Reminder updatedReminder, int currentPage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool reminderUpdated = false;

      for (int page = 1; page <= currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            final List<Reminder> reminders = remindersList
                .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
                .toList();

            int index = reminders.indexWhere((r) => r.id == updatedReminder.id);
            if (index != -1) {
              reminders[index] = updatedReminder;
              reminderUpdated = true;
              final updatedJson =
                  jsonEncode(reminders.map((r) => r.toJson()).toList());
              await prefs.setString(key, updatedJson);
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (!reminderUpdated) {
        await addReminderToFirstPage(updatedReminder);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// إضافة تذكير إلى الصفحة الأولى
  Future<void> addReminderToFirstPage(Reminder reminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = '${_sessionRemindersKeyPrefix}1';
      List<Reminder> reminders = [];
      final cachedData = prefs.getString(key);

      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          reminders = remindersList
              .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          reminders = [];
        }
      }

      reminders.removeWhere((r) => r.id == reminder.id);
      reminders.add(reminder);
      reminders.sort((a, b) => b.id.compareTo(a.id));
      final updatedJson = jsonEncode(reminders.map((r) => r.toJson()).toList());
      await prefs.setString(key, updatedJson);
    } catch (e) {
      // Handle error silently
    }
  }

  /// حذف تذكير من التخزين المؤقت
  Future<void> removeCachedReminder(int reminderId, int currentPage, int totalReminders) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (int page = 1; page <= currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            remindersList.removeWhere((item) => item['id'] == reminderId);
            await prefs.setString(key, jsonEncode(remindersList));
          } catch (e) {
            continue;
          }
        }
      }

      await prefs.setInt(_totalKey, totalReminders);
    } catch (e) {
      // Handle error silently
    }
  }

  /// حذف تذكير من التخزين المؤقت (نسخة بديلة)
  Future<void> deleteCachedReminder(int id, int currentPage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith(_sessionRemindersKeyPrefix)) {
          final cachedRemindersJson = prefs.getString(key);
          if (cachedRemindersJson != null) {
            final List<dynamic> remindersList = jsonDecode(cachedRemindersJson);
            final updatedList =
                remindersList.where((r) => r['id'] != id).toList();
            await prefs.setString(key, jsonEncode(updatedList));
          }
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// حفظ بيانات الفلاتر في التخزين المؤقت
  Future<void> saveCachedData(RemindersResponse response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_categoriesKey, jsonEncode(response.categories));
      await prefs.setString(
          _complexitiesKey, jsonEncode(response.complexities));
      await prefs.setString(_domainsKey, jsonEncode(response.domains));
      await prefs.setInt(_totalKey, response.total ?? 0);
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحميل الفلاتر من التخزين المؤقت
  Future<Map<String, List<String>>> loadFiltersFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCategoriesJson = prefs.getString(_categoriesKey);
      final cachedComplexitiesJson = prefs.getString(_complexitiesKey);
      final cachedDomainsJson = prefs.getString(_domainsKey);

      final isArabic = cachedCategoriesJson?.contains('الكل') ?? false;
      final allLabel = isArabic ? 'الكل' : 'All';

      return {
        'categories': cachedCategoriesJson != null
            ? [allLabel, ...List<String>.from(jsonDecode(cachedCategoriesJson))]
            : [allLabel],
        'complexities': cachedComplexitiesJson != null
            ? [allLabel, ...List<String>.from(jsonDecode(cachedComplexitiesJson))]
            : [allLabel],
        'domains': cachedDomainsJson != null
            ? [allLabel, ...List<String>.from(jsonDecode(cachedDomainsJson))]
            : [allLabel],
      };
    } catch (e) {
      return {
        'categories': ['All'],
        'complexities': ['All'],
        'domains': ['All'],
      };
    }
  }

  /// تنظيف التخزين المؤقت من البيانات غير الصالحة
  Future<void> cleanupCache(int currentPage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final sessionKeys =
          keys.where((k) => k.startsWith(_sessionRemindersKeyPrefix)).toList();

      for (String key in sessionKeys) {
        final cachedData = prefs.getString(key);
        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            final validReminders = remindersList
                .where((item) =>
                    item is Map<String, dynamic> && item['id'] != null)
                .toList();

            if (validReminders.length != remindersList.length) {
              await prefs.setString(key, jsonEncode(validReminders));
            }
          } catch (e) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// تنظيف التذكيرات المخزنة مؤقتاً
  Future<void> cleanupCachedReminders(int currentPage) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (int page = 1; page <= currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            await prefs.setString(key, jsonEncode(remindersList));
          } catch (e) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// طباعة محتويات التخزين المؤقت للتصحيح
  Future<void> debugCacheContents(int currentPage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int page = 1; page <= currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          for (var item in remindersList) {
            final reminder = Reminder.fromJson(item as Map<String, dynamic>);
            // Process reminder without printing
          }
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// اختبار اتساق التخزين المؤقت
  Future<void> testCacheConsistency(
    int currentPage,
    List<Reminder> memoryReminders,
  ) async {
    try {
      List<Reminder> cachedReminders = [];
      for (int page = 1; page <= currentPage; page++) {
        final pageReminders = await loadCachedReminders(page);
        cachedReminders.addAll(pageReminders);
      }

      for (final memoryReminder in memoryReminders) {
        final cachedReminder = cachedReminders.firstWhere(
          (r) => r.id == memoryReminder.id,
          orElse: () => Reminder(
              id: 0,
              userId: 0,
              title: '',
              scheduledTimes: [],
              nextReminderTime: '',
              isOpened: 0),
        );

        if (cachedReminder.id == 0) {
          await updateCachedReminder(memoryReminder, currentPage);
        } else if (cachedReminder.isOpened != memoryReminder.isOpened ||
            cachedReminder.title != memoryReminder.title) {
          await updateCachedReminder(memoryReminder, currentPage);
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// حفظ الحالة الحالية فوراً
  Future<void> forceSaveCurrentState(
    List<Reminder> allReminders,
    int totalReminders,
  ) async {
    try {
      if (allReminders.isNotEmpty) {
        await cacheRemindersForPage(1, allReminders);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_totalKey, totalReminders);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// مسح جميع بيانات التخزين المؤقت للجلسة
  Future<void> clearSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // مسح البيانات المخزنة مؤقتاً
      await prefs.remove(_categoriesKey);
      await prefs.remove(_complexitiesKey);
      await prefs.remove(_domainsKey);
      await prefs.remove(_totalKey);
      await prefs.remove(_lastInitKey);

      // مسح جميع صفحات التذكيرات المخزنة
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_sessionRemindersKeyPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // ============================================================================
  // دوال الإشعارات
  // ============================================================================

  /// جدولة إشعارات التذكير
  Future<void> scheduleReminderNotifications(Reminder reminder) async {
    try {
      if (reminder.nextReminderTime != null &&
          reminder.nextReminderTime!.isNotEmpty &&
          reminder.isOpened != 1) {
        final scheduledDate = DateTime.parse(reminder.nextReminderTime!);
        await _notificationService.scheduleReminderWithHiddenCheck(
          reminderId: reminder.id,
          title: reminder.title,
          url: reminder.url ?? '',
          scheduledDate: scheduledDate,
          importance: reminder.importance ?? 'day',
          additionalPayload: {
            'content': reminder.content ?? '',
            'imageUrl': reminder.imageUrl ?? '',
            'createdAt': reminder.createdAt ?? '',
            'updatedAt': reminder.updatedAt ?? '',
            'category': reminder.category ?? '',
            'complexity': reminder.complexity ?? '',
            'domain': reminder.domain ?? '',
          },
        );
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// إعادة جدولة جميع الإشعارات
  Future<void> rescheduleAllNotifications(List<Reminder> unreadReminders) async {
    try {
      await _notificationService.cancelAllNotifications();
      for (final reminder in unreadReminders) {
        await scheduleReminderNotifications(reminder);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// إلغاء إشعار تذكير محدد
  Future<void> cancelReminderNotification(int reminderId) async {
    try {
      await _notificationService.cancelReminderNotifications(reminderId);
    } catch (e) {
      // Handle error silently
    }
  }

  /// إلغاء جميع الإشعارات
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationService.cancelAllNotifications();
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحديث إشعار تذكير
  Future<void> updateReminderNotification(Reminder reminder) async {
    try {
      await _notificationService.cancelReminderNotifications(reminder.id);
      await scheduleReminderNotifications(reminder);
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحديث إشعار من البيانات
  Future<void> updateReminderNotificationFromData(
      Map<String, dynamic> reminderData) async {
    try {
      await _notificationService.updateReminderNotifications(reminderData);
    } catch (e) {
      // Handle error silently
    }
  }

  /// جدولة إشعارات للوضع غير المتصل
  Future<void> scheduleOfflineNotifications(List<Reminder> unreadReminders) async {
    try {
      await _notificationService.cancelAllNotifications();

      for (final reminder in unreadReminders) {
        try {
          if (reminder.nextReminderTime != null &&
              reminder.nextReminderTime!.isNotEmpty) {
            final scheduledDate = DateTime.parse(reminder.nextReminderTime!);
            final now = DateTime.now();

            if (scheduledDate.isAfter(now)) {
              await scheduleReminderNotifications(reminder);
            }
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحديث قناة الإشعارات
  Future<void> updateNotificationChannel() async {
    try {
      await _notificationService.updateNotificationChannel();
    } catch (e) {
      // Handle error silently
    }
  }

  /// التحقق من صلاحيات الإشعارات
  Future<bool> checkNotificationPermissions() async {
    try {
      return await _notificationService.checkPermissions();
    } catch (e) {
      return false;
    }
  }

  /// طلب صلاحيات الإشعارات
  Future<bool> requestNotificationPermissions() async {
    try {
      return await _notificationService.requestPermissions();
    } catch (e) {
      return false;
    }
  }

  /// الحصول على حالة خدمة الإشعارات
  Future<Map<String, dynamic>> getNotificationServiceStatus() async {
    try {
      return await _notificationService.getServiceStatus();
    } catch (e) {
      return {};
    }
  }

  // ============================================================================
  // دوال إعادة الجدولة
  // ============================================================================

  /// التحقق وإعادة جدولة التذكيرات غير المقروءة
  Future<List<Reminder>> checkAndRescheduleUnreadReminders(
    List<Reminder> unreadReminders,
  ) async {
    final now = DateTime.now();
    final List<Reminder> updatedReminders = [];
    final Set<int> currentlyRescheduling = <int>{};

    for (var reminder in unreadReminders) {
      if (currentlyRescheduling.contains(reminder.id)) {
        updatedReminders.add(reminder);
        continue;
      }

      if (reminder.nextReminderTime != null &&
          reminder.nextReminderTime!.isNotEmpty) {
        try {
          final nextReminderTime = DateTime.parse(reminder.nextReminderTime!);
          if (nextReminderTime.isBefore(now)) {
            if (reminder.url != null && reminder.importance != null) {
              currentlyRescheduling.add(reminder.id);
              try {
                final rescheduleResponse = await _apiService.reschedulePost(
                  reminder.url!,
                  reminder.importance!,
                );

                final newReminderTime = rescheduleResponse['post']
                    ['next_reminder_time'] as String?;

                if (newReminderTime != null && newReminderTime.isNotEmpty) {
                  final updatedReminder = reminder.copyWith(
                    nextReminderTime: newReminderTime,
                  );
                  updatedReminders.add(updatedReminder);
                } else {
                  updatedReminders.add(reminder);
                }
              } catch (e) {
                updatedReminders.add(reminder);
              } finally {
                currentlyRescheduling.remove(reminder.id);
              }
            } else {
              updatedReminders.add(reminder);
            }
          } else {
            updatedReminders.add(reminder);
          }
        } catch (e) {
          updatedReminders.add(reminder);
        }
      } else {
        updatedReminders.add(reminder);
      }
    }

    return updatedReminders;
  }

  // ============================================================================
  // دوال API
  // ============================================================================

  /// التحقق من البريد الإلكتروني
  Future<void> verifyEmail(String email, String code) async {
    try {
      await _apiService.verifyEmail(email, code);
    } catch (e) {
      rethrow;
    }
  }

  /// إعادة إرسال رمز التحقق
  Future<void> resendVerificationCode(String email) async {
    try {
      await _apiService.resendVerificationCode(email);
    } catch (e) {
      rethrow;
    }
  }

  /// الحصول على تحليل إحصائيات المنشورات المفتوحة
  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    try {
      final response = await _apiService.getOpenedStatsAnalysis();

      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>;
      } else {
        throw Exception(response['message'] ?? 'فشل في جلب تحليل الإحصائيات');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// الحصول على إحصائيات المنشورات المحفوظة
  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    try {
      final response = await _apiService.getSavedPostStatistics();

      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>;
      } else {
        throw Exception(
            response['message'] ?? 'فشل في جلب إحصائيات المنشورات المحفوظة');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// إعادة جدولة منشور
  Future<Map<String, dynamic>> reschedulePost(String url, String importance) async {
    try {
      return await _apiService.reschedulePost(url, importance);
    } catch (e) {
      rethrow;
    }
  }

  /// حفظ منشور جديد
  Future<Map<String, dynamic>> savePost(Map<String, dynamic> postData) async {
    try {
      return await _apiService.savePost(postData);
    } catch (e) {
      rethrow;
    }
  }

  /// تحديث تذكير
  Future<Map<String, dynamic>> updateReminder(Reminder reminder) async {
    try {
      return await _apiService.updateReminder(reminder);
    } catch (e) {
      rethrow;
    }
  }

  /// حذف تذكير
  Future<void> deleteReminder(int id) async {
    try {
      await _apiService.deleteReminder(id);
    } catch (e) {
      rethrow;
    }
  }

  /// الحصول على تذكير بواسطة المعرف
  Future<Reminder> getReminderById(int reminderId) async {
    try {
      return await _apiService.getReminderById(reminderId);
    } catch (e) {
      rethrow;
    }
  }

  /// جلب التذكيرات من API
  Future<RemindersResponse> fetchReminders({
    int page = 1,
    String searchQuery = '',
    String? category,
    String? complexity,
    String? domain,
    bool forceFetch = false,
    List<int> excludeIds = const [],
  }) async {
    try {
      return await _apiService.fetchReminders(
        page: page,
        searchQuery: searchQuery,
        category: category,
        complexity: complexity,
        domain: domain,
        forceFetch: forceFetch,
        excludeIds: excludeIds,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// تحديث إحصائيات الرابط
  Future<void> updateStats(String url, bool opened) async {
    try {
      await _apiService.updateStats(url, opened);
    } catch (e) {
      rethrow;
    }
  }

  /// الحصول على معرفات التذكيرات
  Future<List<int>> getRemindersIds() async {
    try {
      return await _apiService.getRemindersIds();
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // دوال المساعدة
  // ============================================================================

  /// التحقق من أن التذكير أحدث
  bool isReminderNewer(Reminder reminder1, Reminder reminder2) {
    try {
      if (reminder1.updatedAt != null && reminder2.updatedAt != null) {
        final date1 = DateTime.parse(reminder1.updatedAt!);
        final date2 = DateTime.parse(reminder2.updatedAt!);
        return date1.isAfter(date2);
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  /// تحميل معرف المستخدم
  Future<String?> loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('userId');
    } catch (e) {
      return null;
    }
  }

  /// التحقق من وجود بيانات محلية
  Future<bool> hasOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      const firstPageKey = '${_sessionRemindersKeyPrefix}1';
      final cachedData = prefs.getString(firstPageKey);

      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          return remindersList.isNotEmpty;
        } catch (e) {
          return false;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// التحقق من وجود تذكير في التخزين المؤقت
  Future<bool> reminderExistsInCache(int reminderId, int currentPage) async {
    final prefs = await SharedPreferences.getInstance();
    int page = 1;
    while (page <= currentPage) {
      final key = '$_sessionRemindersKeyPrefix$page';
      final cachedData = prefs.getString(key);
      if (cachedData == null || cachedData.isEmpty) break;
      try {
        final List<dynamic> remindersList = jsonDecode(cachedData);
        if (remindersList.any(
            (item) => (item as Map<String, dynamic>)['id'] == reminderId)) {
          return true;
        }
      } catch (e) {
        page++;
        continue;
      }
      page++;
    }
    return false;
  }

  /// حفظ وقت آخر تهيئة
  Future<void> saveLastInitialization(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastInitKey, timestamp.toIso8601String());
    } catch (e) {
      // Handle error silently
    }
  }
// ============================================================================
// Background FCM Handling (NO UI – SAFE FOR BACKGROUND)
// ============================================================================

/// معالجة تحديث التذكير في الخلفية (يُستدعى من FCM Background Handler)
Future<void> handleReminderUpdateInBackground(
  Map<String, dynamic> data,
) async {
  try {
    // 1️⃣ تحقق من البيانات
    if (!data.containsKey('reminder')) {
      return;
    }

    final reminderRaw = data['reminder'];

    // 2️⃣ تحويل JSON
    final Map<String, dynamic> reminderJson =
        reminderRaw is String ? jsonDecode(reminderRaw) : reminderRaw;

    final reminder = Reminder.fromJson(reminderJson);

    // 3️⃣ تحديث الكاش
    await updateCachedReminder(reminder, 1);

    // 4️⃣ تحديث / إعادة جدولة الإشعار
    await updateReminderNotification(reminder);

  } catch (e) {
    // ❗ ممنوع SnackBar / UI
    // يمكن تسجيل Log فقط
  }
}

  /// تحميل وقت آخر تهيئة
  Future<DateTime?> loadLastInitialization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastInitStr = prefs.getString(_lastInitKey);
      if (lastInitStr != null) {
        return DateTime.parse(lastInitStr);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}