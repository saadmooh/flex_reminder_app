import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemindersNotifier extends ChangeNotifier {
  // Singleton pattern
  static RemindersNotifier? _instance;
  static RemindersNotifier get instance {
    _instance ??= RemindersNotifier._internal();
    return _instance!;
  }

  // Private constructor for singleton
  RemindersNotifier._internal();

  // Factory constructor to return singleton instance
  factory RemindersNotifier({GlobalKey<NavigatorState>? navigatorKey}) {
    final instance = RemindersNotifier.instance;
    if (navigatorKey != null) {
      instance.navigatorKey = navigatorKey;
    }
    return instance;
  }

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
  bool _isInitialized = false; // إضافة متغير للتحقق من التهيئة

  // متغيرات حماية من تكرار إعادة الجدولة
  static bool _isReschedulingInProgress = false;
  static final Set<int> _currentlyRescheduling = <int>{};
  static DateTime? _lastRescheduleCheck;
  static const Duration _rescheduleInterval = Duration(minutes: 30);

  // متغيرات حماية من تكرار التهيئة
  static bool _isInitializingInProgress = false;
  static DateTime? _lastInitialization;
  static const Duration _initializationCooldown = Duration(seconds: 30);

  // إضافة متغيرات جديدة
  static DateTime? _lastFcmUpdate;
  static const Duration _fcmUpdateWindow = Duration(minutes: 5);

  // الخدمات
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  GlobalKey<NavigatorState>? navigatorKey;

  // مفاتيح التخزين المؤقت
  static const String _categoriesKey = 'cached_categories';
  static const String _complexitiesKey = 'cached_complexities';
  static const String _domainsKey = 'cached_domains';
  static const String _totalKey = 'cached_total';
  static const String _sessionRemindersKeyPrefix = 'session_reminders_page_';
  static const String _lastInitKey = 'last_initialization';

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
  bool get isInitialized => _isInitialized;

  // ================== دوال التهيئة المحسنة ==================

  /// تهيئة الخدمة مع حماية من التكرار
  Future<void> initializeImproved({bool forceRefresh = false}) async {
    print('🔄 محاولة تهيئة RemindersNotifier...');

    // التحقق من التهيئة السابقة
    if (_isInitialized && !forceRefresh) {
      // ===== فحص إضافي: هل تم تحديث FCM مؤخراً؟ =====
      if (_lastFcmUpdate != null) {
        final timeSinceLastFcm = DateTime.now().difference(_lastFcmUpdate!);
        if (timeSinceLastFcm < _fcmUpdateWindow) {
          print(
              '✅ تم تجاهل التهيئة لأن هناك تحديث FCM حديث (${timeSinceLastFcm.inMinutes} دقائق)');
          return;
        }
      }

      print('✅ RemindersNotifier مهيء مسبقاً');
      return;
    }

    // التحقق من فترة التهدئة
    if (!forceRefresh && _lastInitialization != null) {
      final timeSinceLastInit = DateTime.now().difference(_lastInitialization!);
      if (timeSinceLastInit < _initializationCooldown) {
        print('🚫 لم تمر فترة التهدئة بعد');
        return;
      }
    }

    _isInitializingInProgress = true;
    _setLoading(true);

    try {
      print('🚀 بدء عملية التهيئة...');

      // ===== استخدام الدالة المحسنة =====
      await loadCachedDataImproved();

      if ((_readReminders.isEmpty && _unreadReminders.isEmpty) ||
          forceRefresh) {
        print('📥 جلب البيانات من السيرفر...');
        await fetchReminders(forceFetch: true);
      }

      _isInitialized = true;
      _lastInitialization = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastInitKey, _lastInitialization!.toIso8601String());

      print('✅ تم تهيئة RemindersNotifier بنجاح');
    } catch (e) {
      print('❌ خطأ في تهيئة RemindersNotifier: $e');
      rethrow;
    } finally {
      _isInitializingInProgress = false;
      _setLoading(false);
    }
  }

  /// تحديث حالة التحميل
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  /// تحميل البيانات المخزنة مؤقتاً مع مزامنة مع السيرفر
  Future<void> loadCachedDataImproved() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ===== حفظ التحديثات الحالية قبل إعادة التحميل =====
      final Map<int, Reminder> currentInMemoryReminders = {};

      // حفظ جميع التذكيرات الحالية في الذاكرة
      for (final reminder in [..._readReminders, ..._unreadReminders]) {
        currentInMemoryReminders[reminder.id] = reminder;
      }

      // 1. جلب جميع المعرفات من السيرفر
      late List<int> serverIds;
      try {
        serverIds = await _apiService.getRemindersIds();
        print('تم جلب ${serverIds.length} معرف من السيرفر');
      } catch (e) {
        print('فشل في جلب المعرفات من السيرفر: $e');
        serverIds = [];
      }

      // 2. جلب التذكيرات المخزنة محليًا من جميع الصفحات
      List<Reminder> localReminders = [];
      int page = 1;
      while (true) {
        final reminders = await _loadCachedReminders(page);
        if (reminders.isEmpty) break;
        localReminders.addAll(reminders);
        page++;
      }

      // ===== دمج التحديثات الحالية مع البيانات المخزنة =====
      for (final entry in currentInMemoryReminders.entries) {
        final id = entry.key;
        final inMemoryReminder = entry.value;

        // العثور على التذكير في البيانات المخزنة
        final localIndex = localReminders.indexWhere((r) => r.id == id);

        if (localIndex != -1) {
          // مقارنة timestamps للتأكد من أن البيانات في الذاكرة أحدث
          final localReminder = localReminders[localIndex];

          // إذا كان التحديث في الذاكرة أحدث، نستخدمه
          if (_isReminderNewer(inMemoryReminder, localReminder)) {
            localReminders[localIndex] = inMemoryReminder;
            // تحديث التخزين المؤقت فوراً
            await _updateCachedReminderFixed(inMemoryReminder);
          }
        } else if (serverIds.contains(id)) {
          // التذكير موجود في السيرفر ولكن ليس في التخزين المحلي
          localReminders.add(inMemoryReminder);
          await _updateCachedReminderFixed(inMemoryReminder);
        }
      }

      final Set<int> localIds = localReminders.map((r) => r.id).toSet();
      final Set<int> serverIdSet = serverIds.toSet();

      // 3. تحديد التذكيرات المحذوفة
      final List<int> deletedIds = localIds.difference(serverIdSet).toList();
      for (int id in deletedIds) {
        // ===== تحقق إضافي: لا تحذف التذكيرات المحدثة حديثاً =====
        if (!currentInMemoryReminders.containsKey(id)) {
          print('حذف التذكير المحلي $id لأنه لم يعد موجودًا في السيرفر');
          await deleteReminderLocally(id);
          localReminders.removeWhere((r) => r.id == id);
        }
      }

      // 4. باقي المعالجة كما هي...
      final List<int> missingIds = serverIdSet.difference(localIds).toList();
      if (missingIds.isNotEmpty) {
        print('جاري جلب ${missingIds.length} تذكير مفقود من السيرفر');
        final missingReminders = await Future.wait(
          missingIds.map((id) async {
            try {
              return await _apiService.getReminderById(id);
            } catch (e) {
              print('فشل في جلب التذكير $id: $e');
              return null;
            }
          }).where((f) => f != null),
          eagerError: true,
        );

        for (final reminder in missingReminders.whereType<Reminder>()) {
          localReminders.add(reminder);
          await _updateCachedReminderFixed(reminder);
        }
      }

      // 5. تحديث القوائم
      _readReminders = localReminders.where((r) => r.isOpened == 1).toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      _unreadReminders = localReminders.where((r) => r.isOpened == 0).toList()
        ..sort((a, b) => b.id.compareTo(a.id));

      final unclassified = localReminders
          .where((r) => r.isOpened != 0 && r.isOpened != 1)
          .toList();
      if (unclassified.isNotEmpty) {
        _unreadReminders.addAll(unclassified);
        _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      }

      // باقي الكود...
      await _loadFiltersFromCache(prefs);
      _totalReminders = serverIds.length;
      _currentPage = page;
      await _checkAndRescheduleUnreadReminders();
      notifyListeners();
    } catch (e) {
      print('خطأ في تحميل البيانات المخزنة: $e');
      await _loadCachedDataFallback();
    }
  }

  /// فحص وإعادة جدولة التذكيرات غير المقروءة مع حماية من التكرار
  Future<void> _checkAndRescheduleUnreadReminders() async {
    // حماية من التكرار
    if (_isReschedulingInProgress) {
      print('عملية إعادة الجدولة قيد التقدم بالفعل، تجاهل الطلب');
      return;
    }

    _isReschedulingInProgress = true;

    try {
      final now = DateTime.now(); // تصحيح: إضافة DateTime قبل now
      final List<Reminder> updatedReminders = [];

      for (var reminder in _unreadReminders) {
        // تجاهل التذكيرات التي يتم معالجتها حالياً
        if (_currentlyRescheduling.contains(reminder.id)) {
          updatedReminders.add(reminder);
          continue;
        }

        if (reminder.nextReminderTime != null &&
            reminder.nextReminderTime!.isNotEmpty) {
          try {
            final nextReminderTime = DateTime.parse(reminder.nextReminderTime!);
            if (nextReminderTime.isBefore(now)) {
              print('التذكير ${reminder.id} فات موعده: $nextReminderTime');

              if (reminder.url != null && reminder.importance != null) {
                // إضافة للقائمة المعالجة حالياً
                _currentlyRescheduling.add(reminder.id);

                try {
                  // إعادة جدولة التذكير
                  final rescheduleResponse = await _apiService.reschedulePost(
                    reminder.url!,
                    reminder.importance!,
                  );

                  final newReminderTime = rescheduleResponse['post']
                      ['next_reminder_time'] as String?;

                  if (newReminderTime != null && newReminderTime.isNotEmpty) {
                    // تحديث التذكير بالتاريخ الجديد
                    final updatedReminder = reminder.copyWith(
                      nextReminderTime: newReminderTime,
                    );
                    updatedReminders.add(updatedReminder);
                    await _updateCachedReminderFixed(updatedReminder);
                    print(
                        'تم إعادة جدولة التذكير ${reminder.id} إلى: $newReminderTime');
                  } else {
                    print(
                        'فشل في الحصول على تاريخ جديد للتذكير ${reminder.id}');
                    updatedReminders.add(reminder);
                  }
                } catch (e) {
                  print('خطأ في إعادة جدولة التذكير ${reminder.id}: $e');
                  updatedReminders.add(reminder);
                } finally {
                  // إزالة من القائمة المعالجة
                  _currentlyRescheduling.remove(reminder.id);
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
    } finally {
      _isReschedulingInProgress = false;
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
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
        await _updateCachedReminderFixed(updatedReminder);

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
          final List<dynamic> remindersList = jsonDecode(cachedData);

          // إزالة التذكير من القائمة
          remindersList.removeWhere((item) => item['id'] == reminderId);

          // حفظ البيانات المحدثة
          await prefs.setString(key, jsonEncode(remindersList));
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
  Future<void> _updateCachedReminderFixed(Reminder updatedReminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool reminderUpdated = false;

      print('🔧 تحديث التذكير ${updatedReminder.id} في التخزين المؤقت...');

      // البحث في جميع صفحات التخزين المؤقت
      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            final List<Reminder> reminders = remindersList
                .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
                .toList();

            // البحث عن التذكير وتحديثه أو إزالته
            int index = reminders.indexWhere((r) => r.id == updatedReminder.id);
            if (index != -1) {
              print(
                  '✅ تم العثور على التذكير ${updatedReminder.id} في الصفحة $page');

              // تحديث التذكير
              reminders[index] = updatedReminder;
              reminderUpdated = true;

              // حفظ القائمة المحدثة فوراً
              final updatedJson =
                  jsonEncode(reminders.map((r) => r.toJson()).toList());
              await prefs.setString(key, updatedJson);

              print('💾 تم حفظ التذكير المحدث في الصفحة $page');
            }
          } catch (e) {
            print('خطأ في معالجة الصفحة $page: $e');
            continue;
          }
        }
      }

      // إذا لم يتم العثور على التذكير، أضفه إلى الصفحة الأولى
      if (!reminderUpdated) {
        print('⚠️ لم يتم العثور على التذكير، إضافته إلى الصفحة الأولى...');
        await _addReminderToFirstPageFixed(updatedReminder);
      }

      print('✅ تم تحديث التذكير ${updatedReminder.id} بنجاح في التخزين المؤقت');
    } catch (e) {
      print('❌ خطأ في تحديث التذكير في التخزين المؤقت: $e');
      rethrow;
    }
  }

// ===== دالة محسنة لإضافة التذكير للصفحة الأولى =====
  Future<void> _addReminderToFirstPageFixed(Reminder reminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_sessionRemindersKeyPrefix}1';

      List<Reminder> reminders = [];
      final cachedData = prefs.getString(key);

      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          reminders = remindersList
              .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          print('خطأ في قراءة البيانات المخزنة، إنشاء قائمة جديدة: $e');
          reminders = [];
        }
      }

      // إزالة التذكير إذا كان موجوداً (لتجنب التكرار)
      reminders.removeWhere((r) => r.id == reminder.id);

      // إضافة التذكير الجديد
      reminders.add(reminder);
      reminders.sort((a, b) => b.id.compareTo(a.id));

      // حفظ القائمة المحدثة
      final updatedJson = jsonEncode(reminders.map((r) => r.toJson()).toList());
      await prefs.setString(key, updatedJson);

      print('✅ تم إضافة التذكير ${reminder.id} إلى الصفحة الأولى');
    } catch (e) {
      print('❌ خطأ في إضافة التذكير إلى الصفحة الأولى: $e');
    }
  }

// ===== دالة للتحقق من التخزين المؤقت (للتطوير) =====
  Future<void> debugCacheContents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      print('=== فحص محتويات التخزين المؤقت ===');

      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          print('الصفحة $page: ${remindersList.length} تذكير');

          for (var item in remindersList) {
            final reminder = Reminder.fromJson(item as Map<String, dynamic>);
            print(
                '  - ID: ${reminder.id}, العنوان: ${reminder.title}, مقروء: ${reminder.isOpened}');
          }
        } else {
          print('الصفحة $page: فارغة');
        }
      }
      print('=== انتهاء فحص التخزين المؤقت ===');
    } catch (e) {
      print('خطأ في فحص التخزين المؤقت: $e');
    }
  }

// ===== حل إضافي: دالة تنظيف التخزين المؤقت =====
  Future<void> cleanupCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      print('🧹 تنظيف التخزين المؤقت...');

      // الحصول على جميع مفاتيح التخزين المؤقت
      final keys = prefs.getKeys();
      final sessionKeys =
          keys.where((k) => k.startsWith(_sessionRemindersKeyPrefix)).toList();

      for (String key in sessionKeys) {
        final cachedData = prefs.getString(key);
        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            // التحقق من صحة البيانات
            final List<dynamic> remindersList = jsonDecode(cachedData);
            final validReminders = remindersList
                .where((item) =>
                    item is Map<String, dynamic> && item['id'] != null)
                .toList();

            if (validReminders.length != remindersList.length) {
              // إعادة حفظ البيانات الصحيحة فقط
              await prefs.setString(key, jsonEncode(validReminders));
              print(
                  'تم تنظيف $key: ${remindersList.length} -> ${validReminders.length}');
            }
          } catch (e) {
            // إذا كانت البيانات فاسدة، احذف المفتاح
            await prefs.remove(key);
            print('تم حذف مفتاح فاسد: $key');
          }
        }
      }

      print('✅ تم تنظيف التخزين المؤقت');
    } catch (e) {
      print('❌ خطأ في تنظيف التخزين المؤقت: $e');
    }
  }

// ===== دالة اختبار شاملة =====
  Future<void> testCacheConsistency() async {
    try {
      print('🔍 اختبار تطابق البيانات...');

      // الحصول على جميع التذكيرات من التخزين المؤقت
      List<Reminder> cachedReminders = [];
      for (int page = 1; page <= _currentPage; page++) {
        final pageReminders = await _loadCachedReminders(page);
        cachedReminders.addAll(pageReminders);
      }

      // الحصول على التذكيرات من الذاكرة
      final memoryReminders = [..._readReminders, ..._unreadReminders];

      print('التخزين المؤقت: ${cachedReminders.length} تذكير');
      print('الذاكرة: ${memoryReminders.length} تذكير');

      // فحص التطابق
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
          print(
              '⚠️ التذكير ${memoryReminder.id} موجود في الذاكرة لكن مفقود من التخزين المؤقت');
          // إصلاح فوري
          await _updateCachedReminderFixed(memoryReminder);
        } else if (cachedReminder.isOpened != memoryReminder.isOpened ||
            cachedReminder.title != memoryReminder.title) {
          print('⚠️ عدم تطابق في البيانات للتذكير ${memoryReminder.id}');
          print(
              '   الذاكرة: مقروء=${memoryReminder.isOpened}, العنوان=${memoryReminder.title}');
          print(
              '   التخزين: مقروء=${cachedReminder.isOpened}, العنوان=${cachedReminder.title}');
          // إصلاح فوري
          await _updateCachedReminderFixed(memoryReminder);
        }
      }

      print('✅ انتهاء اختبار التطابق');
    } catch (e) {
      print('❌ خطأ في اختبار التطابق: $e');
    }
  }

// ===== دالة مساعدة: التحقق من أن التذكير أحدث =====
  bool _isReminderNewer(Reminder reminder1, Reminder reminder2) {
    try {
      // مقارنة التواريخ إذا كانت متوفرة
      if (reminder1.updatedAt != null && reminder2.updatedAt != null) {
        final date1 = DateTime.parse(reminder1.updatedAt!);
        final date2 = DateTime.parse(reminder2.updatedAt!);
        return date1.isAfter(date2);
      }

      // إذا لم تكن التواريخ متوفرة، نفضل البيانات في الذاكرة
      return true;
    } catch (e) {
      // في حالة الخطأ، نفضل البيانات في الذاكرة
      return true;
    }
  }

// ===== دالة مساعدة: تحميل الفلاتر من التخزين المؤقت =====
  Future<void> _loadFiltersFromCache(SharedPreferences prefs) async {
    try {
      final cachedCategoriesJson = prefs.getString(_categoriesKey);
      final cachedComplexitiesJson = prefs.getString(_complexitiesKey);
      final cachedDomainsJson = prefs.getString(_domainsKey);

      final isArabic = cachedCategoriesJson?.contains('الكل') ?? false;
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
    } catch (e) {
      print('خطأ في تحميل الفلاتر: $e');
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
        await _updateCachedReminderFixed(reminder);
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
      await _updateCachedReminderFixed(newReminder);

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
      await _updateCachedReminderFixed(finalUpdatedReminder);

      notifyListeners();
    } catch (e) {
      print('خطأ في تحديث التذكير: $e');
      rethrow;
    }
  }

  /// وضع علامة "مقروء" على التذكير وإلغاء إشعاراته
  Future<void> markReminderAsRead(int reminderId) async {
    try {
      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);

      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];

        // تحديث حالة التذكير عبر API
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

        // إلغاء الإشعارات
        await _notificationService.cancelReminderNotifications(reminderId);

        // ===== استخدام الدالة المحسنة بدلاً من _updateCachedReminder =====
        await _updateCachedReminderFixed(updatedReminder);
        await forceSaveCurrentState();

        notifyListeners();
        print('✅ تم وضع علامة "مقروء" على التذكير $reminderId وحفظه بشكل صحيح');
      }
    } catch (e) {
      print('❌ خطأ في وضع علامة "مقروء" على التذكير: $e');
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

  /// تحميل البيانات بدون مزامنة (في حال فشل الاتصال)
  Future<void> _loadCachedDataFallback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int page = 1;
      List<Reminder> cachedReminders = [];
      while (true) {
        final reminders = await _loadCachedReminders(page);
        if (reminders.isEmpty) break;
        cachedReminders.addAll(reminders);
        page++;
      }

      final cachedCategoriesJson = prefs.getString(_categoriesKey);
      final cachedComplexitiesJson = prefs.getString(_complexitiesKey);
      final cachedDomainsJson = prefs.getString(_domainsKey);

      final isArabic = cachedCategoriesJson?.contains('الكل') ?? false;
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

      _totalReminders = cachedReminders.length;
      _currentPage = page;

      await _checkAndRescheduleUnreadReminders();
      notifyListeners();
    } catch (e) {
      print('فشل في التحميل الاحتياطي: $e');
    }
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

      if (cachedReminders != null && cachedReminders.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedReminders);
          final reminders = remindersList
              .map((r) => Reminder.fromJson(r as Map<String, dynamic>))
              .where((r) => r.id != 0)
              .toList();

          print('تم تحميل ${reminders.length} تذكير من الصفحة $page');
          return reminders;
        } catch (parseError) {
          print('خطأ في تحليل بيانات الصفحة $page: $parseError');
          // في حالة فساد البيانات، احذف المفتاح
          await prefs.remove(key);
          return [];
        }
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
// إضافة هذه الدوال إلى RemindersNotifier class

// ================== دوال معالجة رسائل FCM ==================

  /// معالجة رسائل FCM العامة
  Future<void> handleFcmMessage(RemoteMessage message) async {
    try {
      print('معالجة رسالة FCM: ${message.messageId}');

      // استخراج البيانات من الرسالة
      final String title =
          message.data['title'] ?? message.notification?.title ?? '';
      final String body =
          message.data['body'] ?? message.notification?.body ?? '';

      if (title.isEmpty || body.isEmpty) {
        print('بيانات الرسالة غير مكتملة');
        return;
      }

      // استخراج ID التذكير من body
      int? reminderId;
      try {
        reminderId = int.parse(body);
      } catch (e) {
        print('خطأ في تحويل body إلى رقم: $e');
        return;
      }

      if (reminderId == null) {
        print('معرف التذكير غير صحيح');
        return;
      }

      print('معالجة FCM للتذكير $reminderId - نوع العملية: $title');

      // معالجة الرسالة حسب نوع العملية
      switch (title.toLowerCase()) {
        case 'update':
          await handleUpdateFromFcm(reminderId);
          break;

        case 'reschedule':
          await handleRescheduleFromFcm(reminderId);
          break;

        case 'new':
          await handleNewReminderFromFcm(reminderId);
          break;

        case 'markas_read':
          await handleMarkAsReadFromFcm(reminderId);
          break;

        default:
          print('نوع العملية غير مدعوم: $title');
      }
    } catch (e) {
      print('خطأ في معالجة رسالة FCM: $e');
    }
  }

  /// معالجة تحديث التذكير من FCM
  Future<void> handleUpdateFromFcm(int reminderId) async {
    try {
      _lastFcmUpdate = DateTime.now(); // تسجيل وقت التحديث

      _safeShowMessage('معالجة تحديث التذكير من FCM: $reminderId');

      // جلب التذكير المحدث من السيرفر
      final updatedReminder = await _apiService.getReminderById(reminderId);

      if (updatedReminder.id == reminderId) {
        // إزالة التذكير القديم من القوائم
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);

        // إضافة التذكير المحدث للقائمة المناسبة
        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));

        // إدارة الإشعارات
        await _notificationService.cancelReminderNotifications(reminderId);
        if (updatedReminder.isOpened != 1) {
          await _scheduleReminderNotifications(updatedReminder);
        }

        // ===== الإصلاح الرئيسي: استخدام الدالة المحسنة =====
        await _updateCachedReminderFixed(updatedReminder);

        // ===== حفظ إضافي للتأكد =====
        await forceSaveCurrentState();

        notifyListeners();
        print('✅ تم تحديث التذكير $reminderId بنجاح من FCM مع حفظ شامل');

        // ===== تحقق للتطوير =====
        if (kDebugMode) {
          await debugCacheContents();
        }
      }
    } catch (e) {
      print('❌ خطأ في معالجة تحديث التذكير من FCM: $e');
    }
  }

  /// معالجة إعادة جدولة التذكير من FCM
  Future<void> handleRescheduleFromFcm(int reminderId) async {
    try {
      print('معالجة إعادة جدولة التذكير من FCM: $reminderId');

      // جلب التذكير المحدث من السيرفر
      final updatedReminder = await _apiService.getReminderById(reminderId);

      if (updatedReminder.id == reminderId) {
        // البحث عن التذكير في القوائم المحلية
        bool foundInRead = _readReminders.any((r) => r.id == reminderId);
        bool foundInUnread = _unreadReminders.any((r) => r.id == reminderId);

        if (foundInRead || foundInUnread) {
          // إزالة التذكير القديم
          _readReminders.removeWhere((r) => r.id == reminderId);
          _unreadReminders.removeWhere((r) => r.id == reminderId);

          // إضافة التذكير المحدث للقائمة المناسبة
          final targetList =
              updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
          targetList.add(updatedReminder);
          targetList.sort((a, b) => b.id.compareTo(a.id));

          // إعادة جدولة الإشعارات
          await _notificationService.cancelReminderNotifications(reminderId);
          if (updatedReminder.isOpened != 1 &&
              updatedReminder.nextReminderTime != null &&
              updatedReminder.nextReminderTime!.isNotEmpty) {
            await _scheduleReminderNotifications(updatedReminder);
          }

          // تحديث التخزين المؤقت
          await _updateCachedReminderFixed(updatedReminder);

          notifyListeners();
          print('تم إعادة جدولة التذكير $reminderId بنجاح من FCM');
        } else {
          print('التذكير $reminderId غير موجود في القوائم المحلية');
        }
      } else {
        print('فشل في جلب التذكير المُعاد جدولته $reminderId من السيرفر');
      }
    } catch (e) {
      print('خطأ في معالجة إعادة جدولة التذكير من FCM: $e');
    }
  }

  /// معالجة التذكير الجديد من FCM
  Future<void> handleNewReminderFromFcm(int reminderId) async {
    try {
      print('معالجة تذكير جديد من FCM: $reminderId');

      // التحقق من وجود التذكير في القوائم المحلية
      bool exists = _readReminders.any((r) => r.id == reminderId) ||
          _unreadReminders.any((r) => r.id == reminderId);

      if (!exists) {
        // جلب التذكير الجديد من السيرفر
        final newReminder = await _apiService.getReminderById(reminderId);

        if (newReminder.id == reminderId) {
          // إضافة التذكير الجديد للقائمة المناسبة
          final targetList =
              newReminder.isOpened == 1 ? _readReminders : _unreadReminders;
          targetList.add(newReminder);
          targetList.sort((a, b) => b.id.compareTo(a.id));

          // جدولة الإشعارات للتذكير الجديد
          if (newReminder.isOpened != 1) {
            await _scheduleReminderNotifications(newReminder);
          }

          // تحديث التخزين المؤقت
          await _updateCachedReminderFixed(newReminder);

          // تحديث العدد الإجمالي
          _totalReminders++;

          notifyListeners();
          print('تم إضافة التذكير الجديد $reminderId بنجاح من FCM');
        } else {
          print('فشل في جلب التذكير الجديد $reminderId من السيرفر');
        }
      } else {
        print('التذكير $reminderId موجود بالفعل في القوائم المحلية');
        // تحديث التذكير الموجود
        await handleUpdateFromFcm(reminderId);
      }
    } catch (e) {
      print('خطأ في معالجة التذكير الجديد من FCM: $e');
    }
  }

  /// معالجة وضع علامة "مقروء" من FCM
  Future<void> handleMarkAsReadFromFcm(int reminderId) async {
    try {
      print('معالجة وضع علامة "مقروء" من FCM: $reminderId');

      // البحث عن التذكير في قائمة غير المقروءة
      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);

      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];

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
        await _updateCachedReminderFixed(updatedReminder);

        notifyListeners();
        print('تم وضع علامة "مقروء" على التذكير $reminderId من FCM');
      } else {
        print('التذكير $reminderId غير موجود في قائمة غير المقروءة');

        // محاولة جلب التذكير من السيرفر للتأكد من حالته
        try {
          final reminder = await _apiService.getReminderById(reminderId);
          if (reminder.id == reminderId && reminder.isOpened == 1) {
            // التحقق من وجوده في قائمة المقروءة
            final existsInRead = _readReminders.any((r) => r.id == reminderId);
            if (!existsInRead) {
              _readReminders.add(reminder);
              _readReminders.sort((a, b) => b.id.compareTo(a.id));
              await _updateCachedReminderFixed(reminder);
              notifyListeners();
              print('تم إضافة التذكير المقروء $reminderId من السيرفر');
            }
          }
        } catch (e) {
          print('خطأ في جلب التذكير من السيرفر: $e');
        }
      }
    } catch (e) {
      print('خطأ في معالجة وضع علامة "مقروء" من FCM: $e');
    }
  }

  /// دالة مساعدة لتحديث تذكير من البيانات المُستلمة
  Future<void> updateReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;

      if (reminderId == 0) {
        print('معرف التذكير غير صحيح');
        return;
      }

      // إزالة التذكير من القوائم المحلية
      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);

      // إضافة التذكير المحدث للقائمة المناسبة
      final targetList =
          reminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));

      // إدارة الإشعارات
      await _notificationService.cancelReminderNotifications(reminderId);
      if (reminder.isOpened != 1) {
        await _scheduleReminderNotifications(reminder);
      }

      // تحديث التخزين المؤقت
      await _updateCachedReminderFixed(reminder);

      notifyListeners();
      print('تم تحديث التذكير $reminderId من البيانات المُستلمة');
    } catch (e) {
      print('خطأ في تحديث التذكير من البيانات المُستلمة: $e');
    }
  }

  /// دالة مساعدة لإضافة تذكير جديد من البيانات المُستلمة
  Future<void> addNewReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;

      if (reminderId == 0) {
        print('معرف التذكير غير صحيح');
        return;
      }

      // التحقق من عدم وجود التذكير مسبقاً
      bool exists = _readReminders.any((r) => r.id == reminderId) ||
          _unreadReminders.any((r) => r.id == reminderId);

      if (!exists) {
        // إضافة التذكير الجديد للقائمة المناسبة
        final targetList =
            reminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(reminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));

        // جدولة الإشعارات للتذكير الجديد
        if (reminder.isOpened != 1) {
          await _scheduleReminderNotifications(reminder);
        }

        // تحديث التخزين المؤقت
        await _updateCachedReminderFixed(reminder);

        // تحديث العدد الإجمالي
        _totalReminders++;

        notifyListeners();
        print('تم إضافة التذكير الجديد $reminderId من البيانات المُستلمة');
      } else {
        print('التذكير $reminderId موجود بالفعل، سيتم تحديثه');
        await updateReminderFromServerData(reminderData);
      }
    } catch (e) {
      print('خطأ في إضافة التذكير الجديد من البيانات المُستلمة: $e');
    }
  }

  /// دالة لمعالجة استجابة السيرفر من getReminderById
  Future<void> handleGetReminderByIdResponse(
      Map<String, dynamic> response) async {
    try {
      if (response['success'] == true && response['reminder'] != null) {
        final reminderData = response['reminder'] as Map<String, dynamic>;
        await updateReminderFromServerData(reminderData);
      } else {
        print('فشل في الحصول على التذكير من السيرفر: ${response['message']}');
      }
    } catch (e) {
      print('خطأ في معالجة استجابة getReminderById: $e');
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

  // ===== الحل الرابع: إضافة دالة للحفظ الفوري =====
  Future<void> forceSaveCurrentState() async {
    try {
      print('🔄 حفظ فوري للحالة الحالية...');

      // حفظ جميع التذكيرات الحالية في الصفحة الأولى
      final allCurrentReminders = [..._readReminders, ..._unreadReminders];
      if (allCurrentReminders.isNotEmpty) {
        await _cacheRemindersForPage(1, allCurrentReminders);

        // تحديث عداد الصفحات
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_totalKey, _totalReminders);
      }

      print('✅ تم الحفظ الفوري للحالة');
    } catch (e) {
      print('❌ خطأ في الحفظ الفوري: $e');
    }
  }

  /// تهيئة النظام للعمل بدون إنترنت
  Future<void> initializeOfflineMode() async {
    print('🔄 تهيئة النظام للعمل بدون إنترنت...');

    try {
      _setLoading(true);

      // تحميل البيانات المخزنة محلياً بدون محاولة المزامنة مع السيرفر
      await _loadOfflineCachedData();

      // جدولة الإشعارات للتذكيرات المحلية
      await _scheduleOfflineNotifications();

      _isInitialized = true;
      print('✅ تم تهيئة النظام للعمل بدون إنترنت بنجاح');
    } catch (e) {
      print('❌ خطأ في تهيئة النظام للعمل بدون إنترنت: $e');
      // حتى لو فشلت التهيئة، نحاول تحميل البيانات الأساسية
      await _loadBasicOfflineData();
    } finally {
      _setLoading(false);
    }
  }

  /// تحميل البيانات المخزنة محلياً بدون محاولة الاتصال بالسيرفر
  Future<void> _loadOfflineCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      print('📁 تحميل البيانات المخزنة محلياً...');

      // تحميل التذكيرات من جميع الصفحات المخزنة
      List<Reminder> allCachedReminders = [];
      int page = 1;

      while (true) {
        final pageReminders = await _loadCachedReminders(page);
        if (pageReminders.isEmpty) break;

        allCachedReminders.addAll(pageReminders);
        page++;
      }

      if (allCachedReminders.isNotEmpty) {
        // تصنيف التذكيرات
        _readReminders = allCachedReminders
            .where((r) => r.isOpened == 1)
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));

        _unreadReminders = allCachedReminders
            .where((r) => r.isOpened == 0)
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));

        // معالجة التذكيرات غير المصنفة
        final unclassified = allCachedReminders
            .where((r) => r.isOpened != 0 && r.isOpened != 1)
            .toList();
        if (unclassified.isNotEmpty) {
          _unreadReminders.addAll(unclassified);
          _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
        }

        print(
            '✅ تم تحميل ${allCachedReminders.length} تذكير من التخزين المحلي');
        print('   - مقروءة: ${_readReminders.length}');
        print('   - غير مقروءة: ${_unreadReminders.length}');
      } else {
        print('⚠️ لا توجد تذكيرات مخزنة محلياً');
      }

      // تحميل الفلاتر المخزنة
      await _loadFiltersFromCache(prefs);

      // تحديث العدد الإجمالي
      _totalReminders = allCachedReminders.length;
      _currentPage = page;

      notifyListeners();
    } catch (e) {
      print('❌ خطأ في تحميل البيانات المخزنة محلياً: $e');
      throw e;
    }
  }

  /// جدولة الإشعارات للتذكيرات المحلية (بدون إنترنت)
  Future<void> _scheduleOfflineNotifications() async {
    try {
      print('📅 جدولة الإشعارات للتذكيرات المحلية...');

      // إلغاء جميع الإشعارات الحالية أولاً
      await _notificationService.cancelAllNotifications();

      // جدولة إشعارات للتذكيرات غير المقروءة فقط
      int scheduledCount = 0;
      for (final reminder in _unreadReminders) {
        try {
          if (reminder.nextReminderTime != null &&
              reminder.nextReminderTime!.isNotEmpty) {
            final scheduledDate = DateTime.parse(reminder.nextReminderTime!);
            final now = DateTime.now();

            // جدولة الإشعار فقط إذا كان الموعد في المستقبل
            if (scheduledDate.isAfter(now)) {
              await _scheduleReminderNotifications(reminder);
              scheduledCount++;
            } else {
              print('تم تخطي التذكير ${reminder.id} - الموعد في الماضي');
            }
          }
        } catch (e) {
          print('خطأ في جدولة إشعار التذكير ${reminder.id}: $e');
          continue;
        }
      }

      print('✅ تم جدولة $scheduledCount إشعار تذكير للوضع بدون إنترنت');
    } catch (e) {
      print('❌ خطأ في جدولة الإشعارات للوضع بدون إنترنت: $e');
    }
  }

  /// تحميل البيانات الأساسية في حالة فشل التحميل الكامل
  Future<void> _loadBasicOfflineData() async {
    try {
      print('📋 تحميل البيانات الأساسية للوضع بدون إنترنت...');

      final prefs = await SharedPreferences.getInstance();

      // تحميل الفلاتر الأساسية
      _categories = ['الكل'];
      _complexities = ['الكل'];
      _domains = ['الكل'];

      // محاولة تحميل أي تذكيرات متاحة
      try {
        final firstPageReminders = await _loadCachedReminders(1);
        if (firstPageReminders.isNotEmpty) {
          _readReminders =
              firstPageReminders.where((r) => r.isOpened == 1).toList();
          _unreadReminders =
              firstPageReminders.where((r) => r.isOpened == 0).toList();
          _totalReminders = firstPageReminders.length;
        }
      } catch (e) {
        print('لا توجد تذكيرات محلية متاحة: $e');
        _readReminders = [];
        _unreadReminders = [];
        _totalReminders = 0;
      }

      _currentPage = 1;
      notifyListeners();

      print('✅ تم تحميل البيانات الأساسية للوضع بدون إنترنت');
    } catch (e) {
      print('❌ خطأ في تحميل البيانات الأساسية: $e');
    }
  }

  /// التحقق من وجود تذكيرات مخزنة محلياً
  Future<bool> hasOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // فحص الصفحة الأولى على الأقل
      final firstPageKey = '${_sessionRemindersKeyPrefix}1';
      final cachedData = prefs.getString(firstPageKey);

      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          return remindersList.isNotEmpty;
        } catch (e) {
          print('خطأ في قراءة البيانات المحلية: $e');
          return false;
        }
      }

      return false;
    } catch (e) {
      print('خطأ في فحص البيانات المحلية: $e');
      return false;
    }
  }
}
