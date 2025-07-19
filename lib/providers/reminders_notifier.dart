import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this import for kDebugMode
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemindersNotifier extends ChangeNotifier {
  // الخصائص الأساسية
  List<Reminder> _readReminders = [];
  List<Reminder> _unreadReminders = [];
  List<String> _categories = [];
  List<String> _complexities = [];
  List<String> _domains = [];
  int _totalReminders = 0;
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;

  // الخدمات
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  // Add a global navigator key reference
  // This should be passed from your main app or injected
  GlobalKey<NavigatorState>? navigatorKey;

  // مفاتيح التخزين المؤقت
  static const String _categoriesKey = 'cached_categories';
  static const String _complexitiesKey = 'cached_complexities';
  static const String _domainsKey = 'cached_domains';
  static const String _totalKey = 'cached_total';
  static const String _sessionRemindersKeyPrefix = 'session_reminders_page_';

  // Constructor to accept navigator key
  RemindersNotifier({this.navigatorKey});

  // Getters
  List<Reminder> get readReminders => _readReminders;
  List<Reminder> get unreadReminders => _unreadReminders;
  List<String> get categories => _categories;
  List<String> get complexities => _complexities;
  List<String> get domains => _domains;
  int get totalReminders => _totalReminders;
  int get currentPage => _currentPage;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;

  // ================== دوال التهيئة ==================

  /// تهيئة الخدمة
  Future<void> initialize() async {
    if (_readReminders.isEmpty && _unreadReminders.isEmpty) {
      await loadCachedData();
      if (_readReminders.isEmpty && _unreadReminders.isEmpty) {
        await fetchReminders(forceFetch: true);
      }
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    // التحقق من أن التطبيق نشط ومتاح
    if (navigatorKey?.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey!.currentContext!);

      // التحقق من أن ScaffoldMessenger متاح
      if (scaffoldMessenger.mounted) {
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
        print('ScaffoldMessenger غير متاح، تم تجاهل SnackBar: $message');
      }
    } else {
      print('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    }
  }

  // دالة للتحقق من حالة التطبيق قبل عرض الرسائل
  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      print('FCM Message: $message');
    }

    // محاولة عرض SnackBar مع معالجة الأخطاء
    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  Future<void> updateSingleReminder(int reminderId) async {
    final updatedReminder = await _apiService.getReminderById(reminderId);
    _safeShowMessage(updatedReminder.id.toString());
    try {
      _safeShowMessage('تحديث التذكير $reminderId من السيرفر');

      // جلب التذكير المحدث من السيرفر
      final updatedReminder = await _apiService.getReminderById(reminderId);
      _safeShowMessage(updatedReminder.id.toString());
      if (updatedReminder != null && updatedReminder.id == reminderId) {
        // إزالة التذكير القديم من القوائم المحلية
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);

        // إضافة التذكير المحدث للقائمة المناسبة
        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));

        // إلغاء الإشعارات القديمة وجدولة الجديدة
        await _notificationService.cancelReminderNotifications(reminderId);
        if (updatedReminder.isOpened != 1) {
          await _scheduleReminderNotifications(updatedReminder);
        }

        // تحديث التخزين المؤقت
        await _updateCachedReminder(updatedReminder);

        notifyListeners();
        print('تم تحديث التذكير $reminderId بنجاح');
      } else {
        // إذا لم يتم العثور على التذكير، فهذا يعني أنه تم حذفه
        print('التذكير $reminderId غير موجود، سيتم حذفه محلياً');
        await deleteReminderLocally(reminderId);
      }
    } catch (e) {
      print('خطأ في تحديث التذكير المفرد $reminderId: $e');

      // في حالة الخطأ، نحاول التحقق من وجود التذكير
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        print('التذكير $reminderId تم حذفه من السيرفر');
        await deleteReminderLocally(reminderId);
      } else {
        rethrow;
      }
    }
  }

// دالة حذف التذكير محلياً
  Future<void> deleteReminderLocally(int reminderId) async {
    try {
      print('حذف التذكير $reminderId محلياً');

      // إزالة التذكير من القوائم المحلية
      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);

      // إلغاء الإشعارات المرتبطة به
      await _notificationService.cancelReminderNotifications(reminderId);

      // حذف التذكير من التخزين المؤقت
      await _removeCachedReminder(reminderId);

      // تقليل العدد الإجمالي
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;

      notifyListeners();
      print('تم حذف التذكير $reminderId محلياً بنجاح');
    } catch (e) {
      print('خطأ في حذف التذكير محلياً $reminderId: $e');
      rethrow;
    }
  }

// دالة إزالة التذكير من التخزين المؤقت
  Future<void> _removeCachedReminder(int reminderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // البحث في جميع صفحات التخزين المؤقت وإزالة التذكير
      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final Map<String, dynamic> data = jsonDecode(cachedData);
          final List<dynamic> readList = data['read'] ?? [];
          final List<dynamic> unreadList = data['unread'] ?? [];

          // إزالة التذكير من القوائم
          readList.removeWhere((item) => item['id'] == reminderId);
          unreadList.removeWhere((item) => item['id'] == reminderId);

          // حفظ البيانات المحدثة
          data['read'] = readList;
          data['unread'] = unreadList;

          await prefs.setString(key, jsonEncode(data));
        }
      }

      // تحديث العدد الإجمالي في التخزين المؤقت
      await prefs.setInt(_totalKey, _totalReminders);

      print('تم إزالة التذكير $reminderId من التخزين المؤقت');
    } catch (e) {
      print('خطأ في إزالة التذكير من التخزين المؤقت: $e');
    }
  }

// دالة تحديث التذكير في التخزين المؤقت
  Future<void> _updateCachedReminder(Reminder reminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool reminderUpdated = false;

      // البحث في جميع صفحات التخزين المؤقت وتحديث التذكير
      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final Map<String, dynamic> data = jsonDecode(cachedData);
          final List<dynamic> readList = data['read'] ?? [];
          final List<dynamic> unreadList = data['unread'] ?? [];

          // إزالة التذكير من القوائم القديمة
          readList.removeWhere((item) => item['id'] == reminder.id);
          unreadList.removeWhere((item) => item['id'] == reminder.id);

          // إضافة التذكير للقائمة المناسبة
          final targetList = reminder.isOpened == 1 ? readList : unreadList;
          targetList.add(reminder.toJson());

          // ترتيب القائمة
          targetList.sort((a, b) => b['id'].compareTo(a['id']));

          // حفظ البيانات المحدثة
          data['read'] = readList;
          data['unread'] = unreadList;

          await prefs.setString(key, jsonEncode(data));
          reminderUpdated = true;
        }
      }

      // إذا لم يتم العثور على التذكير في التخزين المؤقت، أضفه للصفحة الأولى
      if (!reminderUpdated && _currentPage >= 1) {
        final key = '${_sessionRemindersKeyPrefix}1';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final Map<String, dynamic> data = jsonDecode(cachedData);
          final List<dynamic> readList = data['read'] ?? [];
          final List<dynamic> unreadList = data['unread'] ?? [];

          final targetList = reminder.isOpened == 1 ? readList : unreadList;
          targetList.insert(0, reminder.toJson()); // إضافة في المقدمة

          data['read'] = readList;
          data['unread'] = unreadList;

          await prefs.setString(key, jsonEncode(data));
        }
      }

      print('تم تحديث التذكير ${reminder.id} في التخزين المؤقت');
    } catch (e) {
      print('خطأ في تحديث التذكير في التخزين المؤقت: $e');
    }
  }

  // ================== دوال جلب البيانات ==================

  /// جلب تذكير معين بواسطة ID
  Future<Reminder?> getReminderById(int reminderId) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;

    var reminder = _readReminders.firstWhere(
      (r) => r.id == reminderId,
      orElse: () => _unreadReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => Reminder(
          id: reminderId,
          userId: userId,
          title: '',
          scheduledTimes: [],
          nextReminderTime: '',
          isOpened: 0,
        ),
      ),
    );

    if (reminder.id == reminderId) {
      print('تم العثور على التذكير $reminderId في التخزين المحلي');
      return reminder;
    }

    try {
      print('جلب التذكير $reminderId من السيرفر');
      reminder = await _apiService.getReminderById(reminderId);
      if (reminder.id == reminderId) {
        final targetList =
            reminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.removeWhere((r) => r.id == reminderId);
        targetList.add(reminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));
        await _updateCachedReminder(reminder);
        notifyListeners();
        return reminder;
      }
    } catch (e) {
      print('خطأ في جلب التذكير $reminderId: $e');
      rethrow;
    }
    return null;
  }

  /// جلب التذكيرات من السيرفر
  Future<void> fetchReminders({
    String searchQuery = '',
    String? category,
    String? complexity,
    String? domain,
    bool isLoadMore = false,
    bool forceFetch = false,
    List<int> excludeIds = const [],
  }) async {
    if (isLoadMore && _isLoadingMore) return;

    try {
      _setLoadingState(isLoadMore);
      final response = await _apiService.fetchReminders(
        page: isLoadMore ? _currentPage : 1,
        searchQuery: searchQuery,
        category: category,
        complexity: complexity,
        domain: domain,
        forceFetch: forceFetch,
        excludeIds: excludeIds,
      );

      if (response.success ?? true) {
        final isArabic = response.categories.contains('الكل');
        final allLabel = isArabic ? 'الكل' : 'All';

        if (!isLoadMore) {
          await _clearSessionCache();
          _readReminders = response.reminders
              .where((r) => r.isOpened == 1)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          _unreadReminders = response.reminders
              .where((r) => r.isOpened == 0)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));

          final unclassified = response.reminders
              .where((r) => r.isOpened != 0 && r.isOpened != 1)
              .toList();
          if (unclassified.isNotEmpty) {
            _unreadReminders.addAll(unclassified);
            _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
          }

          await _checkAndRescheduleUnreadReminders();

          _categories = [allLabel, ...response.categories];
          _complexities = [allLabel, ...response.complexities];
          _domains = [allLabel, ...?response.domains];
          _totalReminders = response.total ?? 0;
          _currentPage = 2;

          await _cacheRemindersForPage(1, response.reminders);
          await _saveCachedData(response);

          // جدولة الإشعارات للتذكيرات غير المقروءة
          await rescheduleAllNotifications();
        } else {
          final newReadReminders = response.reminders
              .where((r) => r.isOpened == 1)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          final newUnreadReminders = response.reminders
              .where((r) => r.isOpened == 0)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          final newUnclassified = response.reminders
              .where((r) => r.isOpened != 0 && r.isOpened != 1)
              .toList();

          _readReminders.addAll(newReadReminders);
          _unreadReminders.addAll(newUnreadReminders);
          if (newUnclassified.isNotEmpty) {
            _unreadReminders.addAll(newUnclassified);
            _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
          }

          await _checkAndRescheduleUnreadReminders();
          _currentPage++;
          await _cacheRemindersForPage(_currentPage - 1, response.reminders);

          // جدولة الإشعارات للتذكيرات الجديدة غير المقروءة
          for (final reminder in [...newUnreadReminders, ...newUnclassified]) {
            await _scheduleReminderNotifications(reminder);
          }
        }
      }
    } catch (e) {
      print('خطأ في جلب التذكيرات: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ================== دوال إدارة التذكيرات ==================

  /// إنشاء تذكير جديد مع جدولة الإشعارات
  Future<Reminder> createReminder(Map<String, dynamic> reminderData) async {
    try {
      // إنشاء التذكير عبر API باستخدام savePost
      final response = await _apiService.savePost(reminderData);
      final newReminder = Reminder.fromJson(response['post']);

      // إضافة التذكير للقائمة المحلية
      _unreadReminders.add(newReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));

      // جدولة الإشعارات للتذكير الجديد
      await _scheduleReminderNotifications(newReminder);

      // حفظ في التخزين المؤقت
      await _updateCachedReminder(newReminder);

      _totalReminders++;
      notifyListeners();

      return newReminder;
    } catch (e) {
      print('خطأ في إنشاء التذكير: $e');
      rethrow;
    }
  }

  /// تحديث تذكير موجود مع تحديث الإشعارات
  Future<void> updateReminder(
      int reminderId, Map<String, dynamic> updatedData) async {
    try {
      // العثور على التذكير الحالي
      var currentReminder = _readReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => _unreadReminders.firstWhere(
          (r) => r.id == reminderId,
          orElse: () => throw Exception('التذكير غير موجود'),
        ),
      );

      // تحديث البيانات في التذكير الحالي
      final updatedReminder = currentReminder.copyWith(
        title: updatedData['title'] ?? currentReminder.title,
        content: updatedData['content'] ?? currentReminder.content,
        url: updatedData['url'] ?? currentReminder.url,
        importance: updatedData['importance'] ?? currentReminder.importance,
        nextReminderTime: updatedData['next_reminder_time'] ??
            currentReminder.nextReminderTime,
        category: updatedData['category'] ?? currentReminder.category,
        complexity: updatedData['complexity'] ?? currentReminder.complexity,
        domain: updatedData['domain'] ?? currentReminder.domain,
        imageUrl: updatedData['image_url'] ?? currentReminder.imageUrl,
        isOpened: updatedData['is_opened'] ?? currentReminder.isOpened,
      );

      // تحديث التذكير عبر API
      final response = await _apiService.updateReminder(updatedReminder);
      final finalUpdatedReminder = Reminder.fromJson(response['post']);

      // إزالة التذكير من القوائم المحلية
      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);

      // إضافة التذكير المحدث للقائمة المناسبة
      final targetList = finalUpdatedReminder.isOpened == 1
          ? _readReminders
          : _unreadReminders;
      targetList.add(finalUpdatedReminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));

      // إلغاء الإشعارات القديمة وجدولة الجديدة
      await _notificationService.cancelReminderNotifications(reminderId);
      await _scheduleReminderNotifications(finalUpdatedReminder);

      // تحديث التخزين المؤقت
      await _updateCachedReminder(finalUpdatedReminder);

      notifyListeners();
    } catch (e) {
      print('خطأ في تحديث التذكير: $e');
      rethrow;
    }
  }

  /// وضع علامة "مقروء" على التذكير وإلغاء إشعاراته
  Future<void> markReminderAsRead(int reminderId) async {
    try {
      // البحث عن التذكير في قائمة غير المقروءة
      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);

      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];

        // تحديث حالة التذكير عبر API باستخدام updateStats
        if (reminder.url != null && reminder.url!.isNotEmpty) {
          await _apiService.updateStats(reminder.url!, true);
        }

        // نقل التذكير من غير المقروءة إلى المقروءة
        _unreadReminders.removeAt(reminderIndex);

        final updatedReminder = reminder.copyWith(
          isOpened: 1,
          nextReminderTime: null,
        );
        _readReminders.add(updatedReminder);
        _readReminders.sort((a, b) => b.id.compareTo(a.id));

        // إلغاء جميع الإشعارات المتعلقة بهذا التذكير
        await _notificationService.cancelReminderNotifications(reminderId);

        // تحديث التخزين المؤقت
        await _updateCachedReminder(updatedReminder);

        notifyListeners();

        print('تم وضع علامة "مقروء" على التذكير $reminderId وإلغاء إشعاراته');
      }
    } catch (e) {
      print('خطأ في وضع علامة "مقروء" على التذكير: $e');
      rethrow;
    }
  }

  /// حذف تذكير مع إلغاء إشعاراته
  Future<void> deleteReminder(int id) async {
    try {
      await _apiService.deleteReminder(id);

      // إزالة التذكير من القوائم المحلية
      _readReminders.removeWhere((r) => r.id == id);
      _unreadReminders.removeWhere((r) => r.id == id);

      // إلغاء الإشعارات المتعلقة بالتذكير
      await _notificationService.cancelReminderNotifications(id);

      // تحديث التخزين المؤقت
      await _deleteCachedReminder(id);

      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      notifyListeners();

      print('تم حذف التذكير $id مع إشعاراته');
    } catch (e) {
      print('خطأ في حذف التذكير: $e');
      rethrow;
    }
  }

  /// إعادة تحديث جميع التذكيرات
  Future<void> forceRefreshReminders() async {
    _currentPage = 1;
    _readReminders.clear();
    _unreadReminders.clear();
    await _clearSessionCache();

    // إلغاء جميع الإشعارات الحالية
    await _notificationService.cancelAllNotifications();

    // جلب التذكيرات الجديدة (سيتم جدولة الإشعارات تلقائياً)
    await fetchReminders(forceFetch: true);
  }

  // ================== دوال إدارة الإشعارات ==================

  /// جدولة إشعارات التذكير
  Future<void> _scheduleReminderNotifications(Reminder reminder) async {
    try {
      // التحقق من وجود موعد للتذكير وأنه لم يُقرأ بعد
      if (reminder.nextReminderTime != null &&
          reminder.nextReminderTime!.isNotEmpty &&
          reminder.isOpened != 1) {
        final scheduledDate = DateTime.parse(reminder.nextReminderTime!);

        // جدولة الإشعار مع الفحص الخفي
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

        print('تم جدولة إشعار للتذكير ${reminder.id}: ${reminder.title}');
      }
    } catch (e) {
      print('خطأ في جدولة إشعار التذكير ${reminder.id}: $e');
    }
  }

  /// إعادة جدولة جميع الإشعارات للتذكيرات غير المقروءة
  Future<void> rescheduleAllNotifications() async {
    try {
      print('بدء إعادة جدولة جميع الإشعارات للتذكيرات غير المقروءة');

      // إلغاء جميع الإشعارات الحالية
      await _notificationService.cancelAllNotifications();

      // إعادة جدولة الإشعارات لجميع التذكيرات غير المقروءة
      for (final reminder in _unreadReminders) {
        await _scheduleReminderNotifications(reminder);
      }

      print('تم إعادة جدولة ${_unreadReminders.length} إشعار تذكير');
    } catch (e) {
      print('خطأ في إعادة جدولة الإشعارات: $e');
    }
  }

  /// إلغاء إشعار تذكير معين
  Future<void> cancelReminderNotification(int reminderId) async {
    try {
      await _notificationService.cancelReminderNotifications(reminderId);
      print('تم إلغاء إشعار التذكير $reminderId');
    } catch (e) {
      print('خطأ في إلغاء إشعار التذكير $reminderId: $e');
    }
  }

  /// إلغاء جميع الإشعارات
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationService.cancelAllNotifications();
      print('تم إلغاء جميع الإشعارات');
    } catch (e) {
      print('خطأ في إلغاء جميع الإشعارات: $e');
    }
  }

  /// تحديث إشعار تذكير معين
  Future<void> updateReminderNotification(int reminderId) async {
    try {
      // البحث عن التذكير
      final reminder = _unreadReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => _readReminders.firstWhere(
          (r) => r.id == reminderId,
          orElse: () => throw Exception('التذكير غير موجود'),
        ),
      );

      // إلغاء الإشعار الحالي
      await _notificationService.cancelReminderNotifications(reminderId);

      // إعادة جدولة الإشعار
      await _scheduleReminderNotifications(reminder);

      print('تم تحديث إشعار التذكير $reminderId');
    } catch (e) {
      print('خطأ في تحديث إشعار التذكير $reminderId: $e');
    }
  }

  /// تحديث إشعار تذكير بناءً على البيانات المحدثة
  Future<void> updateReminderNotificationFromData(
      Map<String, dynamic> reminderData) async {
    try {
      await _notificationService.updateReminderNotifications(reminderData);
      print('تم تحديث إشعار التذكير من البيانات المحدثة');
    } catch (e) {
      print('خطأ في تحديث إشعار التذكير من البيانات: $e');
    }
  }

  // ================== دوال خدمة الإشعارات ==================

  /// الحصول على حالة خدمة الإشعارات
  Future<Map<String, dynamic>> getNotificationServiceStatus() async {
    try {
      return await _notificationService.getServiceStatus();
    } catch (e) {
      print('خطأ في الحصول على حالة خدمة الإشعارات: $e');
      return {};
    }
  }

  /// طباعة حالة الإشعارات (للتطوير)
  void printNotificationStatus() {
    _notificationService.printStatus();
  }

  /// تحديث قناة الإشعارات
  Future<void> updateNotificationChannel() async {
    try {
      await _notificationService.updateNotificationChannel();
      print('تم تحديث قناة الإشعارات');
    } catch (e) {
      print('خطأ في تحديث قناة الإشعارات: $e');
    }
  }

  /// التحقق من أذونات الإشعارات
  Future<bool> checkNotificationPermissions() async {
    try {
      return await _notificationService.checkPermissions();
    } catch (e) {
      print('خطأ في التحقق من أذونات الإشعارات: $e');
      return false;
    }
  }

  /// طلب أذونات الإشعارات
  Future<bool> requestNotificationPermissions() async {
    try {
      return await _notificationService.requestPermissions();
    } catch (e) {
      print('خطأ في طلب أذونات الإشعارات: $e');
      return false;
    }
  }

  // ================== دوال التخزين المؤقت ==================

  /// تحميل البيانات المخزنة مؤقتاً
  Future<void> loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCategoriesJson = prefs.getString(_categoriesKey);
      final cachedComplexitiesJson = prefs.getString(_complexitiesKey);
      final cachedDomainsJson = prefs.getString(_domainsKey);
      final cachedTotal = prefs.getInt(_totalKey) ?? 0;

      int page = 1;
      List<Reminder> cachedReminders = [];
      while (true) {
        final reminders = await _loadCachedReminders(page);
        if (reminders.isEmpty) break;
        cachedReminders.addAll(reminders);
        page++;
      }

      final isArabic =
          cachedCategoriesJson != null && cachedCategoriesJson.contains('الكل');
      final allLabel = isArabic ? 'الكل' : 'All';

      _categories = cachedCategoriesJson != null
          ? [allLabel, ...List<String>.from(jsonDecode(cachedCategoriesJson))]
          : [allLabel];
      _complexities = cachedComplexitiesJson != null
          ? [allLabel, ...List<String>.from(jsonDecode(cachedComplexitiesJson))]
          : [allLabel];
      _domains = cachedDomainsJson != null
          ? [allLabel, ...List<String>.from(jsonDecode(cachedDomainsJson))]
          : [allLabel];
      _totalReminders = cachedTotal;

      _readReminders = cachedReminders.where((r) => r.isOpened == 1).toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      _unreadReminders = cachedReminders.where((r) => r.isOpened == 0).toList()
        ..sort((a, b) => b.id.compareTo(a.id));

      final unclassified = cachedReminders
          .where((r) => r.isOpened != 0 && r.isOpened != 1)
          .toList();
      if (unclassified.isNotEmpty) {
        _unreadReminders.addAll(unclassified);
        _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      }

      // فحص وإعادة جدولة التذكيرات غير المقروءة
      await _checkAndRescheduleUnreadReminders();

      _currentPage = page;

      notifyListeners();
    } catch (e) {
      print('خطأ في تحميل البيانات المخزنة: $e');
    }
  }

  /// فحص وإعادة جدولة التذكيرات غير المقروءة
  Future<void> _checkAndRescheduleUnreadReminders() async {
    final now = DateTime.now();
    final List<Reminder> updatedReminders = [];

    for (var reminder in _unreadReminders) {
      if (reminder.nextReminderTime != null &&
          reminder.nextReminderTime!.isNotEmpty) {
        try {
          final nextReminderTime = DateTime.parse(reminder.nextReminderTime!);
          if (nextReminderTime.isBefore(now)) {
            print('التذكير ${reminder.id} فات موعده: $nextReminderTime');
            if (reminder.url != null && reminder.importance != null) {
              // إعادة جدولة التذكير
              final rescheduleResponse = await _apiService.reschedulePost(
                reminder.url!,
                reminder.importance!,
              );
              final newReminderTime =
                  rescheduleResponse['post']['next_reminder_time'] as String?;
              if (newReminderTime != null && newReminderTime.isNotEmpty) {
                // تحديث التذكير بالتاريخ الجديد
                final updatedReminder = reminder.copyWith(
                  nextReminderTime: newReminderTime,
                );
                updatedReminders.add(updatedReminder);
                await _updateCachedReminder(updatedReminder);
                print(
                    'تم إعادة جدولة التذكير ${reminder.id} إلى: $newReminderTime');
              } else {
                print('فشل في الحصول على تاريخ جديد للتذكير ${reminder.id}');
                updatedReminders.add(reminder);
              }
            } else {
              print(
                  'بيانات غير كافية لإعادة جدولة التذكير ${reminder.id}: url أو importance مفقود');
              updatedReminders.add(reminder);
            }
          } else {
            updatedReminders.add(reminder);
          }
        } catch (e) {
          print('خطأ في معالجة التذكير ${reminder.id}: $e');
          updatedReminders.add(reminder);
        }
      } else {
        updatedReminders.add(reminder);
      }
    }

    // تحديث قائمة التذكيرات غير المقروءة
    _unreadReminders
      ..clear()
      ..addAll(updatedReminders)
      ..sort((a, b) => b.id.compareTo(a.id));
    notifyListeners();
  }

  /// تعيين حالة التحميل
  void _setLoadingState(bool isLoadMore) {
    if (!isLoadMore) {
      _isLoading = true;
    }
    _isLoadingMore = isLoadMore;
    notifyListeners();
  }

  /// حفظ البيانات المخزنة مؤقتاً
  Future<void> _saveCachedData(RemindersResponse response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_categoriesKey, jsonEncode(response.categories));
      await prefs.setString(
          _complexitiesKey, jsonEncode(response.complexities));
      await prefs.setString(_domainsKey, jsonEncode(response.domains!));
      await prefs.setInt(_totalKey, response.total ?? 0);
    } catch (e) {
      print('خطأ في حفظ البيانات: $e');
    }
  }

  /// تخزين التذكيرات لصفحة معينة
  Future<void> _cacheRemindersForPage(
      int page, List<Reminder> reminders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_sessionRemindersKeyPrefix$page';
      final validReminders = reminders.where((r) => r.id != 0).toList();
      if (validReminders.isEmpty) return;
      final remindersJson =
          jsonEncode(validReminders.map((r) => r.toJson()).toList());
      await prefs.setString(key, remindersJson);
    } catch (e) {
      print('خطأ في تخزين التذكيرات للصفحة $page: $e');
    }
  }

  Future<List<Reminder>> _loadCachedReminders(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_sessionRemindersKeyPrefix$page';
      final cachedReminders = prefs.getString(key);
      if (cachedReminders != null) {
        final List<dynamic> remindersList = jsonDecode(cachedReminders);
        return remindersList
            .map((r) => Reminder.fromJson(r as Map<String, dynamic>))
            .where((r) => r.id != 0)
            .toList();
      }
    } catch (e) {
      print('خطأ في تحميل التذكيرات المخزنة للصفحة $page: $e');
    }
    return [];
  }

  Future<void> _clearSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith(_sessionRemindersKeyPrefix)) {
          await prefs.remove(key);
        }
      }
      _readReminders.clear();
      _unreadReminders.clear();
      _currentPage = 1;
      notifyListeners();
    } catch (e) {
      print('خطأ في مسح التخزين المؤقت للجلسة: $e');
    }
  }

  Future<void> _deleteCachedReminder(int id) async {
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
      print('خطأ في إزالة التذكير من التخزين المؤقت: $e');
    }
  }
}
