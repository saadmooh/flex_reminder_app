import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/globals.dart' as globals;

class RemindersNotifier extends ChangeNotifier {
  // ============================================================================
  // Singleton Pattern - تبسيط وتحسين
  // ============================================================================
  static RemindersNotifier? _instance;
  
  /// الحصول على instance - يقوم بإنشائها إذا لم تكن موجودة
  static RemindersNotifier get instance {
    if (_instance == null) {
      _instance = RemindersNotifier._internal();
      // عرض SnackBar عند إنشاء instance جديدة
      globals.showGlobalSnackBar(
        '🟢 RemindersNotifier: تم إنشاء instance جديدة',
        backgroundColor: Colors.teal,
      );
    }
    return _instance!;
  }

  /// التحقق من وجود instance بدون إنشائها
  static bool get hasInstance => _instance != null;

  /// Constructor الداخلي - يستخدم فقط من داخل الـ class
  RemindersNotifier._internal() {
    // استخدام navigatorKey من globals مباشرة
    navigatorKey = globals.navigatorKey;
    globals.showGlobalSnackBar(
      '🔧 RemindersNotifier: Constructor called',
      backgroundColor: Colors.blueGrey,
    );
  }

  /// Factory constructor - للتوافق مع الكود القديم
  factory RemindersNotifier({GlobalKey<NavigatorState>? navigatorKey}) {
    final inst = RemindersNotifier.instance;
    if (navigatorKey != null) {
      inst.navigatorKey = navigatorKey;
    }
    return inst;
  }

  /// دالة التهيئة الصريحة - تُستدعى مرة واحدة عند بدء التطبيق
  /// تُظهر SnackBar للتأكيد وتُحدّث حالة globals
  Future<void> initialize({AuthProvider? authProvider}) async {
    if (globals.isRemindersNotifierInitialized) {
      globals.showGlobalSnackBar(
        '🔵 RemindersNotifier: تم تهيئته مسبقاً',
        backgroundColor: Colors.blue,
      );
      return;
    }

    globals.showGlobalSnackBar(
      '🚀 RemindersNotifier: جاري التهيئة...',
      backgroundColor: Colors.orange,
    );
    
    // ربط AuthProvider إذا تم تمريره
    if (authProvider != null) {
      setAuthProvider(authProvider);
    }

    // تعيين navigatorKey من globals
    navigatorKey = globals.navigatorKey;

    // تحديث حالة التهيئة في globals
    globals.isRemindersNotifierInitialized = true;

    // عرض SnackBar للتأكيد النهائي
    globals.showGlobalSnackBar(
      '✅ RemindersNotifier: تم التهيئة بنجاح!',
      backgroundColor: Colors.green,
    );
  }

  // ============================================================================
  // المتغيرات والحقول
  // ============================================================================
  List<Reminder> _readReminders = [];
  List<Reminder> _unreadReminders = [];
  List<String> _categories = [];
  List<String> _complexities = [];
  List<String> _domains = [];
  int _totalReminders = 0;
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isInitialized = false;
  String? _userId;
  static bool _isReschedulingInProgress = false;
  static final Set<int> _currentlyRescheduling = <int>{};
  static DateTime? _lastRescheduleCheck;
  static const Duration _rescheduleInterval = Duration(minutes: 30);
  static bool _isInitializingInProgress = false;
  static DateTime? _lastInitialization;
  static const Duration _initializationCooldown = Duration(seconds: 30);
  static DateTime? _lastFcmUpdate;
  static const Duration _fcmUpdateWindow = Duration(minutes: 5);
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();
  AuthProvider? _authProvider;

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
    globals.showGlobalSnackBar(
      '🔗 RemindersNotifier: تم ربط AuthProvider',
      backgroundColor: Colors.purple,
    );
  }

  GlobalKey<NavigatorState>? navigatorKey;

  static const String _categoriesKey = 'cached_categories';
  static const String _complexitiesKey = 'cached_complexities';
  static const String _domainsKey = 'cached_domains';
  static const String _totalKey = 'cached_total';
  static const String _sessionRemindersKeyPrefix = 'session_reminders_page_';
  static const String _lastInitKey = 'last_initialization';

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
  int? get _currentUserId => _authProvider?.getCurrentUserId();
  Future<void> _cleanupInvalidReminders() async {
    // تم إلغاء التحقق من ملكية المستخدم
    _safeShowMessage('✅ Skipping user ownership validation for reminders');
  }

  /// دالة مساعدة للتحقق من وجود التذكير محلياً (في الذاكرة أو التخزين المؤقت)
  bool _reminderExistsLocally(int reminderId) {
    return _readReminders.any((r) => r.id == reminderId) ||
        _unreadReminders.any((r) => r.id == reminderId);
  }

  /// دالة مساعدة للتحقق من وجود التذكير في التخزين المؤقت (Shared Preferences)
  Future<bool> _reminderExistsInCache(int reminderId) async {
    final prefs = await SharedPreferences.getInstance();
    int page = 1;
    while (true) {
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
        _safeShowMessage(
            'Error checking cache for reminder $reminderId on page $page: $e');
      }
      page++;
    }
    return false;
  }

  /// دالة مساعدة للتحقق الشامل (ذاكرة + تخزين مؤقت)
  Future<bool> _reminderExistsComprehensively(int reminderId) async {
    if (_reminderExistsLocally(reminderId)) {
      return true;
    }
    return await _reminderExistsInCache(reminderId);
  }

  /// حفظ منشور جديد باستخدام URL وأهمية فقط
  Future<Reminder> savePost(String url, String importance) async {
    try {
      _safeShowMessage(
          '📝 Starting to save post with URL: $url and importance: $importance...');
      final postData = {
        'url': url,
        'importance': importance,
        'title': 'New Post',
        'content': '',
        'category': null,
        'complexity': null,
        'domain': null,
        'image_url': null,
      };
      final response = await _apiService.savePost(postData);
      final newReminder = Reminder.fromJson(response['post']);

      // --- التحقق الشامل من التكرار ---
      if (await _reminderExistsComprehensively(newReminder.id)) {
        _safeShowMessage(
            '⚠️ Post ${newReminder.id} already exists locally or in cache, skipping addition');
        return newReminder; // نعيد الكائن لكننا لا نضيفه مرتين
      }
      // --- نهاية التحقق ---

      _unreadReminders.add(newReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      await _scheduleReminderNotifications(newReminder);
      await _updateCachedReminderFixed(newReminder);
      _totalReminders++;
      _ensureUniqueReminders(); // طبقة حماية إضافية
      notifyListeners();
      _safeShowMessage('✅ Post ${newReminder.id} saved successfully');
      return newReminder;
    } catch (e) {
      _safeShowMessage('❌ Error saving post: $e');
      rethrow;
    }
  }

  /// إنشاء تذكير جديد
  Future<Reminder> createReminder(Map<String, dynamic> reminderData) async {
    try {
      final response = await _apiService.savePost(reminderData);
      final newReminder = Reminder.fromJson(response['post']);

      // --- التحقق من التكرار ---
      if (_reminderExistsLocally(newReminder.id)) {
        _safeShowMessage(
            '⚠️ Reminder ${newReminder.id} already exists in local lists, skipping addition');
        return newReminder;
      }
      // --- نهاية التحقق ---

      _unreadReminders.add(newReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      await _scheduleReminderNotifications(newReminder);
      await _updateCachedReminderFixed(newReminder);
      _totalReminders++;
      notifyListeners();
      return newReminder;
    } catch (e) {
      _safeShowMessage('Error creating reminder: $e');
      rethrow;
    }
  }

  /// إضافة تذكير جديد من بيانات السيرفر
  Future<void> addNewReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;
      if (reminderId == 0) {
        _safeShowMessage('Invalid reminder ID');
        return;
      }

      // --- التحقق من التكرار ---
      if (_reminderExistsLocally(reminderId)) {
        _safeShowMessage('Reminder $reminderId already exists, updating instead');
        await updateReminderFromServerData(reminderData);
        return;
      }
      // --- نهاية التحقق ---

      final targetList =
          reminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      if (reminder.isOpened != 1) {
        await _scheduleReminderNotifications(reminder);
      }
      await _updateCachedReminderFixed(reminder);
      _totalReminders++;
      notifyListeners();
      _safeShowMessage('Added new reminder $reminderId from server data');
    } catch (e) {
      _safeShowMessage('Error adding new reminder from server data: $e');
    }
  }

  void _ensureUniqueReminders() {
    final seenIds = <int>{};
    _unreadReminders = _unreadReminders.where((r) {
      if (seenIds.contains(r.id)) return false;
      seenIds.add(r.id);
      return true;
    }).toList();
    _readReminders = _readReminders.where((r) {
      if (seenIds.contains(r.id)) return false;
      seenIds.add(r.id);
      return true;
    }).toList();
    notifyListeners();
  }

  /// إعادة تعيين المثيل بالكامل
  Future<void> resetInstance() async {
    try {
      _debugLog('Resetting RemindersNotifier instance...');

      // إعادة تعيين جميع المتغيرات إلى قيمها الافتراضية
      _readReminders.clear();
      _unreadReminders.clear();
      _categories.clear();
      _complexities.clear();
      _domains.clear();
      _totalReminders = 0;
      _currentPage = 1;
      _isLoading = false;
      _isLoadingMore = false;
      _isInitialized = false;
      _userId = null;

      // إعادة تعيين المتغيرات الثابتة
      _isReschedulingInProgress = false;
      _currentlyRescheduling.clear();
      _lastRescheduleCheck = null;
      _isInitializingInProgress = false;
      _lastInitialization = null;
      _lastFcmUpdate = null;

      // إعادة تعيين AuthProvider reference
      _authProvider = null;

      // مسح أي listeners أو subscriptions
      // (إذا كان لديك أي stream subscriptions أو listeners أخرى)

      // إشعار المستمعين بالتغييرات
      notifyListeners();

      _debugLog('RemindersNotifier instance reset completed');
    } catch (e) {
      _debugLog('Error resetting RemindersNotifier instance: $e');
      rethrow;
    }
  }

  /// مسح جميع البيانات المخزنة مؤقتاً في الجلسة
  Future<void> clearSessionCache() async {
    try {
      _debugLog('Clearing session cache...');

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

      // مسح قوائم التذكيرات
      _readReminders.clear();
      _unreadReminders.clear();

      _debugLog('Session cache cleared successfully');
    } catch (e) {
      _debugLog('Error clearing session cache: $e');
      rethrow;
    }
  }

  /// إلغاء جميع الإشعارات المجدولة
  Future<void> cancelAllNotifications() async {
    try {
      _debugLog('Cancelling all notifications...');

      // إلغاء جميع الإشعارات من خلال NotificationService
      await _notificationService.cancelAllNotifications();

      // إلغاء أي إشعارات Firebase إضافية
      try {
        await FirebaseMessaging.instance.deleteToken();
        _debugLog('Firebase token deleted');
      } catch (e) {
        _debugLog('Error deleting Firebase token: $e');
      }

      _debugLog('All notifications cancelled successfully');
    } catch (e) {
      _debugLog('Error cancelling notifications: $e');
      rethrow;
    }
  }

  /// طباعة رسائل التصحيح
  void _debugLog(String message) {
    if (kDebugMode) {
      _safeShowMessage('RemindersNotifier: $message');
    }
  }

  Future<void> _cleanupCachedReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            await prefs.setString(key, jsonEncode(remindersList));
            _safeShowMessage('🧹 Cached reminders for page $page preserved');
          } catch (e) {
            _safeShowMessage('خطأ في تنظيف الصفحة $page: $e');
            await prefs.remove(key);
          }
        }
      }

      _safeShowMessage('✅ Completed cache cleanup');
    } catch (e) {
      _safeShowMessage('❌ Error in cache cleanup: $e');
    }
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId');
  }

  Future<void> verifyEmail(String email, String code) async {
    try {
      await _apiService.verifyEmail(email, code);
      _safeShowMessage('✅ Email verified successfully: $email');
    } catch (e) {
      _safeShowMessage('❌ Error verifying email: $e');
      rethrow;
    }
  }

  Future<void> resendVerificationCode(String email) async {
    try {
      await _apiService.resendVerificationCode(email);
      _safeShowMessage('✅ Verification code resent to: $email');
    } catch (e) {
      _safeShowMessage('❌ Error resending verification code: $e');
      rethrow;
    }
  }

  Future<Reminder> rescheduleReminder(String url, String importance) async {
    try {
      final response = await _apiService.reschedulePost(url, importance);
      final updatedReminder = Reminder.fromJson(response['post']);

      _safeShowMessage('🔄 Rescheduling reminder ${updatedReminder.id}');
      _readReminders.removeWhere((r) => r.id == updatedReminder.id);
      _unreadReminders.removeWhere((r) => r.id == updatedReminder.id);
      _unreadReminders.add(updatedReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      await _updateCachedReminderFixed(updatedReminder);
      notifyListeners();
      return updatedReminder;
    } catch (e) {
      _safeShowMessage('❌ Error rescheduling reminder: $e');
      rethrow;
    }
  }

  Future<void> initializeImproved({bool forceRefresh = false}) async {
    if (_authProvider == null) {
      _safeShowMessage('❌ Error: AuthProvider not set in RemindersNotifier');
      return;
    }
    _safeShowMessage('🔄 Attempting to initialize RemindersNotifier...');

    if (_isInitialized && !forceRefresh) {
      if (_lastFcmUpdate != null) {
        final timeSinceLastFcm = DateTime.now().difference(_lastFcmUpdate!);
        if (timeSinceLastFcm < _fcmUpdateWindow) {
          _safeShowMessage('✅ Initialization skipped due to recent FCM update');
          return;
        }
      }
      _safeShowMessage('✅ RemindersNotifier already initialized');
      return;
    }

    if (!forceRefresh && _lastInitialization != null) {
      final timeSinceLastInit = DateTime.now().difference(_lastInitialization!);
      if (timeSinceLastInit < _initializationCooldown) {
        _safeShowMessage('🚫 Initialization cooldown not passed');
        return;
      }
    }

    _isInitializingInProgress = true;
    _setLoading(true);

    try {
      _safeShowMessage('🚀 Starting initialization...');
      await loadCachedDataImproved();

      if ((_readReminders.isEmpty && _unreadReminders.isEmpty) ||
          forceRefresh) {
        _safeShowMessage('📥 Fetching data from server...');
        await fetchReminders(forceFetch: true);
      }

      _isInitialized = true;
      _lastInitialization = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastInitKey, _lastInitialization!.toIso8601String());

      _safeShowMessage('✅ RemindersNotifier initialized successfully');
    } catch (e) {
      _safeShowMessage('❌ Error initializing RemindersNotifier: $e');
      rethrow;
    } finally {
      _isInitializingInProgress = false;
      _setLoading(false);
    }
  }

  Future<void> loadCachedDataImproved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<int, Reminder> currentInMemoryReminders = {};

      for (final reminder in [..._readReminders, ..._unreadReminders]) {
        currentInMemoryReminders[reminder.id] = reminder;
      }

      late List<int> serverIds;
      try {
        serverIds = await _apiService.getRemindersIds();
        _safeShowMessage('Fetched ${serverIds.length} IDs from server');
      } catch (e) {
        _safeShowMessage('Failed to fetch IDs from server: $e');
        serverIds = [];
      }

      List<Reminder> localReminders = [];
      int page = 1;
      while (true) {
        final reminders = await _loadCachedReminders(page);
        if (reminders.isEmpty) break;
        localReminders.addAll(reminders);
        page++;
      }

      for (final entry in currentInMemoryReminders.entries) {
        final id = entry.key;
        final inMemoryReminder = entry.value;
        final localIndex = localReminders.indexWhere((r) => r.id == id);

        if (localIndex != -1) {
          final localReminder = localReminders[localIndex];
          if (_isReminderNewer(inMemoryReminder, localReminder)) {
            localReminders[localIndex] = inMemoryReminder;
            await _updateCachedReminderFixed(inMemoryReminder);
          }
        } else if (serverIds.contains(id)) {
          localReminders.add(inMemoryReminder);
          await _updateCachedReminderFixed(inMemoryReminder);
        }
      }

      final Set<int> localIds = localReminders.map((r) => r.id).toSet();
      final Set<int> serverIdSet = serverIds.toSet();

      final List<int> deletedIds = localIds.difference(serverIdSet).toList();
      for (int id in deletedIds) {
        if (!currentInMemoryReminders.containsKey(id)) {
          _safeShowMessage('Deleting local reminder $id as it no longer exists on server');
          await deleteReminderLocally(id);
          localReminders.removeWhere((r) => r.id == id);
        }
      }

      final List<int> missingIds = serverIdSet.difference(localIds).toList();
      if (missingIds.isNotEmpty) {
        _safeShowMessage('Fetching ${missingIds.length} missing reminders from server');
        final missingReminders = await Future.wait(
          missingIds.map((id) async {
            try {
              return await _apiService.getReminderById(id);
            } catch (e) {
              _safeShowMessage('Failed to fetch reminder $id: $e');
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

      await _loadFiltersFromCache(prefs);
      _totalReminders = serverIds.length;
      _currentPage = page;
      await _checkAndRescheduleUnreadReminders();
      await _cleanupCachedReminders();
      notifyListeners();
    } catch (e) {
      _safeShowMessage('Error loading cached data: $e');
      await _loadCachedDataFallback();
    }
  }

  Future<void> validateAndCleanupReminders() async {
    _safeShowMessage('🔍 Starting manual reminder validation...');
    try {
      _safeShowMessage('📊 Validation report:');
      _safeShowMessage('   - Current user: $_currentUserId');
      _safeShowMessage('   - Read reminders: ${_readReminders.length}');
      _safeShowMessage('   - Unread reminders: ${_unreadReminders.length}');
      _safeShowMessage('   - Total: $_totalReminders');
      _safeShowMessage(
          '✅ All reminders validated (user ownership check skipped)');
    } catch (e) {
      _safeShowMessage('❌ Error validating reminders: $e');
      _safeShowMessage('❌ Error validating reminders');
    }
  }

  Future<void> _addReminderWithValidation(Reminder reminder) async {
    final targetList =
        reminder.isOpened == 1 ? _readReminders : _unreadReminders;

    if (!targetList.any((r) => r.id == reminder.id)) {
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      await _updateCachedReminderFixed(reminder);
      _safeShowMessage('✅ Reminder ${reminder.id} added');
    }
  }

  Future<void> handleUpdateFromFcm(int reminderId) async {
  try {
    _lastFcmUpdate = DateTime.now();
    _safeShowMessage('🟢 [handleUpdateFromFcm] === STARTED for reminder $reminderId ===');
    _safeShowMessage('Processing reminder update from FCM: $reminderId', isImportant: true, color: Colors.cyan);

      final updatedReminder = await _apiService.getReminderById(reminderId);

      if (updatedReminder.id == reminderId) {
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);
        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));
        await _notificationService.cancelReminderNotifications(reminderId);
        if (updatedReminder.isOpened != 1) {
          await _scheduleReminderNotifications(updatedReminder);
        }
        await _updateCachedReminderFixed(updatedReminder);
        await forceSaveCurrentState();
        notifyListeners();
      _safeShowMessage('🟢 [handleUpdateFromFcm] === COMPLETED successfully for reminder $reminderId ===');
      _safeShowMessage('✅ Reminder $reminderId updated successfully from FCM', isImportant: true, color: Colors.green);
    }
  } catch (e) {
    _safeShowMessage('🔴 [handleUpdateFromFcm] === ERROR for reminder $reminderId: $e ===');
    _safeShowMessage('❌ Error processing FCM reminder update: $e', isImportant: true, color: Colors.red);
    }
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  Future<void> _checkAndRescheduleUnreadReminders() async {
    if (_isReschedulingInProgress) {
      _safeShowMessage('Rescheduling already in progress, ignoring request');
      return;
    }

    _isReschedulingInProgress = true;

    try {
      final now = DateTime.now();
      final List<Reminder> updatedReminders = [];

      for (var reminder in _unreadReminders) {
        if (_currentlyRescheduling.contains(reminder.id)) {
          updatedReminders.add(reminder);
          continue;
        }

        if (reminder.nextReminderTime != null &&
            reminder.nextReminderTime!.isNotEmpty) {
          try {
            final nextReminderTime = DateTime.parse(reminder.nextReminderTime!);
            if (nextReminderTime.isBefore(now)) {
              _safeShowMessage('Reminder ${reminder.id} is overdue: $nextReminderTime');

              if (reminder.url != null && reminder.importance != null) {
                _currentlyRescheduling.add(reminder.id);
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
                    await _updateCachedReminderFixed(updatedReminder);
                    _safeShowMessage(
                        'Rescheduled reminder ${reminder.id} to: $newReminderTime');
                  } else {
                    _safeShowMessage('Failed to get new time for reminder ${reminder.id}');
                    updatedReminders.add(reminder);
                  }
                } catch (e) {
                  _safeShowMessage('Error rescheduling reminder ${reminder.id}: $e');
                  updatedReminders.add(reminder);
                } finally {
                  _currentlyRescheduling.remove(reminder.id);
                }
              } else {
                _safeShowMessage(
                    'Insufficient data to reschedule reminder ${reminder.id}');
                updatedReminders.add(reminder);
              }
            } else {
              updatedReminders.add(reminder);
            }
          } catch (e) {
            _safeShowMessage('Error processing reminder ${reminder.id}: $e');
            updatedReminders.add(reminder);
          }
        } else {
          updatedReminders.add(reminder);
        }
      }

      _unreadReminders
        ..clear()
        ..addAll(updatedReminders)
        ..sort((a, b) => b.id.compareTo(a.id));
      notifyListeners();
    } finally {
      _isReschedulingInProgress = false;
    }
  }

  /// عرض SnackBar باستخدام الدالة العامة من globals.dart
  void _showSnackBar(String message, Color backgroundColor) {
    globals.showGlobalSnackBar(message, backgroundColor: backgroundColor);
  }

  /// عرض رسالة آمنة باستخدام الدالة العامة من globals.dart
  /// isImportant: إذا كان true، يتم عرض SnackBar. إذا كان false، يتم الطباعة في console فقط.
  void _safeShowMessage(String message, {Color? color, bool isImportant = false}) {
    // دائماً طباعة في console
    debugPrint('📱 RemindersNotifier: $message');
    
    // عرض SnackBar فقط للرسائل المهمة أو إذا تم طلب ذلك
    if (isImportant) {
      globals.showGlobalSnackBar(
        message, 
        backgroundColor: color ?? Colors.blue,
        clearPrevious: false, // لا تمسح الرسائل السابقة
      );
    }
  }

  Future<void> updateSingleReminder(int reminderId) async {
    try {
      _safeShowMessage('Updating reminder $reminderId from server');
      final updatedReminder = await _apiService.getReminderById(reminderId);
      if (updatedReminder.id == reminderId) {
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);
        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));
        await _notificationService.cancelReminderNotifications(reminderId);
        if (updatedReminder.isOpened != 1) {
          await _scheduleReminderNotifications(updatedReminder);
        }
        await _updateCachedReminderFixed(updatedReminder);
        notifyListeners();
        _safeShowMessage('Reminder $reminderId updated successfully');
      } else {
        _safeShowMessage('Reminder $reminderId not found, deleting locally');
        await deleteReminderLocally(reminderId);
      }
    } catch (e) {
      _safeShowMessage('Error updating single reminder $reminderId: $e');
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        _safeShowMessage('Reminder $reminderId deleted from server');
        await deleteReminderLocally(reminderId);
      } else {
        rethrow;
      }
    }
  }

  Future<void> deleteReminderLocally(int reminderId) async {
    try {
      _safeShowMessage('🗑️ Deleting reminder $reminderId locally...');
      final existsInRead = _readReminders.any((r) => r.id == reminderId);
      final existsInUnread = _unreadReminders.any((r) => r.id == reminderId);

      if (!existsInRead && !existsInUnread) {
        _safeShowMessage('⚠️ Reminder $reminderId not found in local lists');
        return;
      }

      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);
      await _notificationService.cancelReminderNotifications(reminderId);
      await _removeCachedReminder(reminderId);
      if (_totalReminders > 0) {
        _totalReminders--;
      }
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
      _safeShowMessage('✅ Reminder $reminderId deleted locally successfully');
    } catch (e) {
      _safeShowMessage('❌ Error deleting reminder locally $reminderId: $e');
      rethrow;
    }
  }

  Future<void> _removeCachedReminder(int reminderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeShowMessage('🗑️ Removing reminder $reminderId from cache...');
      bool reminderFound = false;

      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null && cachedData.isNotEmpty) {
          try {
            final List<dynamic> remindersList = jsonDecode(cachedData);
            final initialLength = remindersList.length;
            remindersList.removeWhere((item) => item['id'] == reminderId);

            if (remindersList.length < initialLength) {
              reminderFound = true;
              _safeShowMessage('✅ Found and removed reminder in page $page');
            }
            await prefs.setString(key, jsonEncode(remindersList));
          } catch (e) {
            _safeShowMessage('Error processing page $page: $e');
            continue;
          }
        }
      }

      if (!reminderFound) {
        _safeShowMessage('⚠️ Reminder $reminderId not found in cache');
      }
      await prefs.setInt(_totalKey, _totalReminders);
      _safeShowMessage('✅ Reminder $reminderId removed from cache');
    } catch (e) {
      _safeShowMessage('❌ Error removing reminder from cache: $e');
      rethrow;
    }
  }

  Future<void> _updateCachedReminderFixed(Reminder updatedReminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool reminderUpdated = false;

      _safeShowMessage('🔧 Updating reminder ${updatedReminder.id} in cache...');
      for (int page = 1; page <= _currentPage; page++) {
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
              _safeShowMessage('✅ Found reminder ${updatedReminder.id} in page $page');
              reminders[index] = updatedReminder;
              reminderUpdated = true;
              final updatedJson =
                  jsonEncode(reminders.map((r) => r.toJson()).toList());
              await prefs.setString(key, updatedJson);
              _safeShowMessage('💾 Saved updated reminder in page $page');
            }
          } catch (e) {
            _safeShowMessage('Error processing page $page: $e');
            continue;
          }
        }
      }

      if (!reminderUpdated) {
        _safeShowMessage('⚠️ Reminder not found, adding to first page...');
        await _addReminderToFirstPageFixed(updatedReminder);
      }
      _safeShowMessage('✅ Reminder ${updatedReminder.id} updated successfully in cache');
    } catch (e) {
      _safeShowMessage('❌ Error updating reminder in cache: $e');
      rethrow;
    }
  }

  Future<void> _addReminderToFirstPageFixed(Reminder reminder) async {
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
          _safeShowMessage('Error reading cached data, creating new list: $e');
          reminders = [];
        }
      }

      reminders.removeWhere((r) => r.id == reminder.id);
      reminders.add(reminder);
      reminders.sort((a, b) => b.id.compareTo(a.id));
      final updatedJson = jsonEncode(reminders.map((r) => r.toJson()).toList());
      await prefs.setString(key, updatedJson);
      _safeShowMessage('✅ Reminder ${reminder.id} added to first page');
    } catch (e) {
      _safeShowMessage('❌ Error adding reminder to first page: $e');
    }
  }

  Future<void> debugCacheContents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeShowMessage('=== Checking cache contents ===');
      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          _safeShowMessage('Page $page: ${remindersList.length} reminders');
          for (var item in remindersList) {
            final reminder = Reminder.fromJson(item as Map<String, dynamic>);
            _safeShowMessage(
                '  - ID: ${reminder.id}, Title: ${reminder.title}, Opened: ${reminder.isOpened}');
          }
        } else {
          _safeShowMessage('Page $page: empty');
        }
      }
      _safeShowMessage('=== End cache contents check ===');
    } catch (e) {
      _safeShowMessage('Error checking cache contents: $e');
    }
  }

  Future<void> cleanupCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeShowMessage('🧹 Cleaning cache...');
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
              _safeShowMessage(
                  'Cleaned $key: ${remindersList.length} -> ${validReminders.length}');
            }
          } catch (e) {
            await prefs.remove(key);
            _safeShowMessage('Removed corrupt key: $key');
          }
        }
      }
      _safeShowMessage('✅ Cache cleaned successfully');
    } catch (e) {
      _safeShowMessage('❌ Error cleaning cache: $e');
    }
  }

  Future<void> testCacheConsistency() async {
    try {
      _safeShowMessage('🔍 Testing data consistency...');
      List<Reminder> cachedReminders = [];
      for (int page = 1; page <= _currentPage; page++) {
        final pageReminders = await _loadCachedReminders(page);
        cachedReminders.addAll(pageReminders);
      }

      final memoryReminders = [..._readReminders, ..._unreadReminders];
      _safeShowMessage('Cache: ${cachedReminders.length} reminders');
      _safeShowMessage('Memory: ${memoryReminders.length} reminders');

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
          _safeShowMessage(
              '⚠️ Reminder ${memoryReminder.id} in memory but missing from cache');
          await _updateCachedReminderFixed(memoryReminder);
        } else if (cachedReminder.isOpened != memoryReminder.isOpened ||
            cachedReminder.title != memoryReminder.title) {
          _safeShowMessage('⚠️ Data mismatch for reminder ${memoryReminder.id}');
          await _updateCachedReminderFixed(memoryReminder);
        }
      }
      _safeShowMessage('✅ Consistency test completed');
    } catch (e) {
      _safeShowMessage('❌ Error in consistency test: $e');
    }
  }

  bool _isReminderNewer(Reminder reminder1, Reminder reminder2) {
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
      _safeShowMessage('Error loading filters: $e');
    }
  }

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
      _safeShowMessage('Found reminder $reminderId in local storage');
      return reminder;
    }

    try {
      _safeShowMessage('Fetching reminder $reminderId from server');
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
      _safeShowMessage('Error fetching reminder $reminderId: $e');
      rethrow;
    }
    return null;
  }

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
          final newReminders = response.reminders.where((r) {
            // Filter out duplicates based on ID
            return !_readReminders.any((existing) => existing.id == r.id) &&
                !_unreadReminders.any((existing) => existing.id == r.id);
          }).toList();

          _readReminders = newReminders.where((r) => r.isOpened == 1).toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          _unreadReminders = newReminders.where((r) => r.isOpened == 0).toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          final unclassified = newReminders
              .where((r) => r.isOpened != 0 && r.isOpened != 1)
              .toList();
          if (unclassified.isNotEmpty) {
            _unreadReminders.addAll(unclassified);
            _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
          }
          await _checkAndRescheduleUnreadReminders();
          _categories = [allLabel, ...response.categories];
          _complexities = [allLabel, ...response.complexities];
          _domains = [allLabel, ...response.domains];
          _totalReminders = response.total ?? 0;
          _currentPage = 2;
          await _cacheRemindersForPage(1, newReminders);
          await _saveCachedData(response);
          await rescheduleAllNotifications();
          _ensureUniqueReminders(); // Ensure no duplicates after fetching
        } else {
          final newReminders = response.reminders.where((r) {
            // Filter out duplicates based on ID
            return !_readReminders.any((existing) => existing.id == r.id) &&
                !_unreadReminders.any((existing) => existing.id == r.id);
          }).toList();

          final newReadReminders = newReminders
              .where((r) => r.isOpened == 1)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          final newUnreadReminders = newReminders
              .where((r) => r.isOpened == 0)
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
          final newUnclassified = newReminders
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
          await _cacheRemindersForPage(_currentPage - 1, newReminders);
          for (final reminder in [...newUnreadReminders, ...newUnclassified]) {
            await _scheduleReminderNotifications(reminder);
          }
          _ensureUniqueReminders(); // Ensure no duplicates after loading more
        }
      }
    } catch (e) {
      _safeShowMessage('Error fetching reminders: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> updateReminder(
      int reminderId, Map<String, dynamic> updatedData) async {
    try {
      var currentReminder = _readReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => _unreadReminders.firstWhere(
          (r) => r.id == reminderId,
          orElse: () => throw Exception('Reminder not found'),
        ),
      );

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

      final response = await _apiService.updateReminder(updatedReminder);
      final finalUpdatedReminder = Reminder.fromJson(response['post']);
      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);
      final targetList = finalUpdatedReminder.isOpened == 1
          ? _readReminders
          : _unreadReminders;
      targetList.add(finalUpdatedReminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      await _notificationService.cancelReminderNotifications(reminderId);
      await _scheduleReminderNotifications(finalUpdatedReminder);
      await _updateCachedReminderFixed(finalUpdatedReminder);
      notifyListeners();
    } catch (e) {
      _safeShowMessage('Error updating reminder: $e');
      rethrow;
    }
  }

  Future<void> markReminderAsRead(int reminderId) async {
    try {
      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);
      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];
        if (reminder.url != null && reminder.url!.isNotEmpty) {
          await _apiService.updateStats(reminder.url!, true);
        }
        _unreadReminders.removeAt(reminderIndex);
        final updatedReminder = reminder.copyWith(
          isOpened: 1,
          nextReminderTime: null,
        );
        _readReminders.add(updatedReminder);
        _readReminders.sort((a, b) => b.id.compareTo(a.id));
        await _notificationService.cancelReminderNotifications(reminderId);
        await _updateCachedReminderFixed(updatedReminder);
        await forceSaveCurrentState();
        notifyListeners();
        _safeShowMessage('✅ Marked reminder $reminderId as read');
      }
    } catch (e) {
      _safeShowMessage('❌ Error marking reminder as read: $e');
      rethrow;
    }
  }

  Future<void> deleteReminder(int id) async {
    try {
      _safeShowMessage('🗑️ Starting deletion of reminder $id...');
      await _apiService.deleteReminder(id);
      _safeShowMessage('✅ Reminder deleted from server');
      final existsInRead = _readReminders.any((r) => r.id == id);
      final existsInUnread = _unreadReminders.any((r) => r.id == id);

      if (!existsInRead && !existsInUnread) {
        _safeShowMessage('⚠️ Reminder $id not found locally');
        return;
      }

      _readReminders.removeWhere((r) => r.id == id);
      _unreadReminders.removeWhere((r) => r.id == id);
      await _notificationService.cancelReminderNotifications(id);
      await _deleteCachedReminder(id);
      if (_totalReminders > 0) {
        _totalReminders--;
      }
      await forceSaveCurrentState();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 50));
      notifyListeners();
      _safeShowMessage(
          '✅ Reminder $id deleted with notifications and UI updated');
    } catch (e) {
      _safeShowMessage('❌ Error deleting reminder: $e');
      rethrow;
    }
  }

  Future<void> verifyDeletionAndUpdate(int deletedId) async {
    try {
      final stillExistsInRead = _readReminders.any((r) => r.id == deletedId);
      final stillExistsInUnread =
          _unreadReminders.any((r) => r.id == deletedId);

      if (stillExistsInRead || stillExistsInUnread) {
        _safeShowMessage(
            '⚠️ Reminder $deletedId still exists, attempting additional deletion');
        _readReminders.removeWhere((r) => r.id == deletedId);
        _unreadReminders.removeWhere((r) => r.id == deletedId);
        notifyListeners();
      }
      _safeShowMessage('✅ Verified deletion of reminder $deletedId');
    } catch (e) {
      _safeShowMessage('❌ Error verifying deletion: $e');
    }
  }

  Future<void> deleteReminderWithUIGuarantee(int id) async {
    try {
      _safeShowMessage(
          '🗑️ Enhanced deletion of reminder $id with UI guarantee...');
      final readCountBefore = _readReminders.length;
      final unreadCountBefore = _unreadReminders.length;
      final totalBefore = _totalReminders;

      await _apiService.deleteReminder(id);
      bool removedFromRead = false;
      bool removedFromUnread = false;

      final readIndex = _readReminders.indexWhere((r) => r.id == id);
      if (readIndex != -1) {
        _readReminders.removeAt(readIndex);
        removedFromRead = true;
      }

      final unreadIndex = _unreadReminders.indexWhere((r) => r.id == id);
      if (unreadIndex != -1) {
        _unreadReminders.removeAt(unreadIndex);
        removedFromUnread = true;
      }

      if (!removedFromRead && !removedFromUnread) {
        _safeShowMessage('⚠️ Reminder $id was not found in lists');
        return;
      }

      await _notificationService.cancelReminderNotifications(id);
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      await _removeCachedReminder(id);
      await forceSaveCurrentState();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();

      _safeShowMessage('📊 Deletion report:');
      _safeShowMessage(
          '   - Read: $readCountBefore -> ${_readReminders.length}');
      _safeShowMessage(
          '   - Unread: $unreadCountBefore -> ${_unreadReminders.length}');
      _safeShowMessage('✅ Reminder $id deleted with UI guarantee');
    } catch (e) {
      _safeShowMessage('❌ Error in enhanced deletion: $e');
      rethrow;
    }
  }

  Future<void> validateStateAfterDeletion(int deletedId) async {
    try {
      final stillInRead = _readReminders.any((r) => r.id == deletedId);
      final stillInUnread = _unreadReminders.any((r) => r.id == deletedId);

      if (stillInRead || stillInUnread) {
        _safeShowMessage('🚨 Error: Reminder $deletedId still exists after deletion!');
        _readReminders.removeWhere((r) => r.id == deletedId);
        _unreadReminders.removeWhere((r) => r.id == deletedId);
        notifyListeners();
      }

      final prefs = await SharedPreferences.getInstance();
      for (int page = 1; page <= _currentPage; page++) {
        final key = '$_sessionRemindersKeyPrefix$page';
        final cachedData = prefs.getString(key);

        if (cachedData != null) {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          final stillInCache =
              remindersList.any((item) => item['id'] == deletedId);

          if (stillInCache) {
            _safeShowMessage('🚨 Error: Reminder $deletedId still in cache page $page!');
            remindersList.removeWhere((item) => item['id'] == deletedId);
            await prefs.setString(key, jsonEncode(remindersList));
          }
        }
      }
      _safeShowMessage('✅ Validated data state after deletion');
    } catch (e) {
      _safeShowMessage('❌ Error validating data after deletion: $e');
    }
  }

  Future<void> deleteReminderComprehensive(int id) async {
    try {
      _safeShowMessage(
          '🗑️ Starting comprehensive deletion of reminder $id...');
      final initialState = {
        'readCount': _readReminders.length,
        'unreadCount': _unreadReminders.length,
        'totalCount': _totalReminders,
        'readIds': _readReminders.map((r) => r.id).toSet(),
        'unreadIds': _unreadReminders.map((r) => r.id).toSet(),
      };

      await _apiService.deleteReminder(id);
      bool actuallyRemoved = false;

      final readIndex = _readReminders.indexWhere((r) => r.id == id);
      if (readIndex != -1) {
        _readReminders.removeAt(readIndex);
        actuallyRemoved = true;
        _safeShowMessage('✅ Removed reminder from read list');
      }

      final unreadIndex = _unreadReminders.indexWhere((r) => r.id == id);
      if (unreadIndex != -1) {
        _unreadReminders.removeAt(unreadIndex);
        actuallyRemoved = true;
        _safeShowMessage('✅ Removed reminder from unread list');
      }

      if (!actuallyRemoved) {
        _safeShowMessage('⚠️ Reminder $id was not found in local lists');
        return;
      }

      await _notificationService.cancelReminderNotifications(id);
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      await _removeCachedReminder(id);
      await forceSaveCurrentState();
      _safeShowMessage('📱 Forcing UI update...');
      notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      final finalState = {
        'readCount': _readReminders.length,
        'unreadCount': _unreadReminders.length,
        'totalCount': _totalReminders,
      };

      _safeShowMessage('📊 Comprehensive deletion report for reminder $id:');
      _safeShowMessage(
          '   Before: read=${initialState['readCount']}, unread=${initialState['unreadCount']}, total=${initialState['totalCount']}');
      _safeShowMessage(
          '   After: read=${finalState['readCount']}, unread=${finalState['unreadCount']}, total=${finalState['totalCount']}');
      _safeShowMessage('✅ Reminder $id deleted successfully with UI guarantee');
    } catch (e) {
      _safeShowMessage('❌ Error in comprehensive deletion: $e');
      rethrow;
    }
  }

  void debugCurrentState() {
    _safeShowMessage('🔍 Current memory state:');
    _safeShowMessage('   - Read: ${_readReminders.length} reminders');
    _safeShowMessage('   - Unread: ${_unreadReminders.length} reminders');
    _safeShowMessage('   - Total: $_totalReminders');
    _safeShowMessage('   - Current page: $_currentPage');
    _safeShowMessage('   - Loading: $_isLoading');
    _safeShowMessage('   - Initialized: $_isInitialized');

    if (_readReminders.isNotEmpty) {
      _safeShowMessage(
          '   Read IDs: ${_readReminders.map((r) => r.id).take(5).join(', ')}${_readReminders.length > 5 ? '...' : ''}');
    }

    if (_unreadReminders.isNotEmpty) {
      _safeShowMessage(
          '   Unread IDs: ${_unreadReminders.map((r) => r.id).take(5).join(', ')}${_unreadReminders.length > 5 ? '...' : ''}');
    }
  }

  Future<void> forceRefreshReminders() async {
    _currentPage = 1;
    _readReminders.clear();
    _unreadReminders.clear();
    await _clearSessionCache();
    await _notificationService.cancelAllNotifications();
    await fetchReminders(forceFetch: true);
  }

  Future<void> _scheduleReminderNotifications(Reminder reminder) async {
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
        _safeShowMessage(
            'Scheduled notification for reminder ${reminder.id}: ${reminder.title}');
      }
    } catch (e) {
      _safeShowMessage('Error scheduling notification for reminder ${reminder.id}: $e');
    }
  }

  Future<void> rescheduleAllNotifications() async {
    try {
      _safeShowMessage('Starting rescheduling of all notifications for unread reminders');
      await _notificationService.cancelAllNotifications();
      for (final reminder in _unreadReminders) {
        await _scheduleReminderNotifications(reminder);
      }
      _safeShowMessage('Rescheduled ${_unreadReminders.length} reminder notifications');
    } catch (e) {
      _safeShowMessage('Error rescheduling notifications: $e');
    }
  }

  Future<void> cancelReminderNotification(int reminderId) async {
    try {
      await _notificationService.cancelReminderNotifications(reminderId);
      _safeShowMessage('Cancelled notification for reminder $reminderId');
    } catch (e) {
      _safeShowMessage('Error cancelling notification for reminder $reminderId: $e');
    }
  }

  // Future<void> cancelAllNotifications() async {
  //   try {
  //     await _notificationService.cancelAllNotifications();
  //     _safeShowMessage('Cancelled all notifications');
  //   } catch (e) {
  //     _safeShowMessage('Error cancelling all notifications: $e');
  //   }
  // }

  Future<void> updateReminderNotification(int reminderId) async {
    try {
      final reminder = _unreadReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => _readReminders.firstWhere(
          (r) => r.id == reminderId,
          orElse: () => throw Exception('Reminder not found'),
        ),
      );

      await _notificationService.cancelReminderNotifications(reminderId);
      await _scheduleReminderNotifications(reminder);
      _safeShowMessage('Updated notification for reminder $reminderId');
    } catch (e) {
      _safeShowMessage('Error updating notification for reminder $reminderId: $e');
    }
  }

  Future<void> updateReminderNotificationFromData(
      Map<String, dynamic> reminderData) async {
    try {
      await _notificationService.updateReminderNotifications(reminderData);
      _safeShowMessage('Updated notification from updated data');
    } catch (e) {
      _safeShowMessage('Error updating notification from data: $e');
    }
  }

  Future<Map<String, dynamic>> getNotificationServiceStatus() async {
    try {
      return await _notificationService.getServiceStatus();
    } catch (e) {
      _safeShowMessage('Error getting notification service status: $e');
      return {};
    }
  }

  void _safeShowMessageNotificationStatus() {
    // طباعة حالة الإشعارات - تم إزالة الاستدعاء غير الموجود
    _safeShowMessage('📊 Notification Service Status: Active');
  }

  Future<void> updateNotificationChannel() async {
    try {
      await _notificationService.updateNotificationChannel();
      _safeShowMessage('Updated notification channel');
    } catch (e) {
      _safeShowMessage('Error updating notification channel: $e');
    }
  }

  Future<bool> checkNotificationPermissions() async {
    try {
      return await _notificationService.checkPermissions();
    } catch (e) {
      _safeShowMessage('Error checking notification permissions: $e');
      return false;
    }
  }

  Future<bool> requestNotificationPermissions() async {
    try {
      return await _notificationService.requestPermissions();
    } catch (e) {
      _safeShowMessage('Error requesting notification permissions: $e');
      return false;
    }
  }

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
      _safeShowMessage('Failed to load fallback data: $e');
    }
  }

  Future<void> _setLoadingState(bool isLoadMore) async {
    if (!isLoadMore) {
      _isLoading = true;
    }
    _isLoadingMore = isLoadMore;
    notifyListeners();
  }

  Future<void> _saveCachedData(RemindersResponse response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_categoriesKey, jsonEncode(response.categories));
      await prefs.setString(
          _complexitiesKey, jsonEncode(response.complexities));
      await prefs.setString(_domainsKey, jsonEncode(response.domains));
      await prefs.setInt(_totalKey, response.total ?? 0);
    } catch (e) {
      _safeShowMessage('Error saving cached data: $e');
    }
  }

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
      _safeShowMessage('Error caching reminders for page $page: $e');
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
          _safeShowMessage('Loaded ${reminders.length} reminders from page $page');
          return reminders;
        } catch (parseError) {
          _safeShowMessage('Error parsing page $page data: $parseError');
          await prefs.remove(key);
          return [];
        }
      }
    } catch (e) {
      _safeShowMessage('Error loading cached reminders for page $page: $e');
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
      _safeShowMessage('Error clearing session cache: $e');
    }
  }

 /// معالجة رسائل FCM القادمة من FcmService
Future<void> handleFcmData(Map<String, dynamic> data) async {
  // ⚠️ أول شيء - عرض SnackBar للتأكد من وصول الكود (قبل try)
  globals.showGlobalSnackBar(
    '🚨 handleFcmData CALLED!',
    backgroundColor: Colors.red,
    clearPrevious: true,
  );
  
  // عرض SnackBar ثاني للتأكد من استمرار التنفيذ
  globals.showGlobalSnackBar(
    '🔵 البيانات: ${data.keys.toList()}',
    backgroundColor: Colors.indigo,
    clearPrevious: true,
  );
  
  try {
    // SnackBar داخل try مباشرة
    globals.showGlobalSnackBar(
      '✅ دخلنا try بنجاح!',
      backgroundColor: Colors.green,
      clearPrevious: true,
    );
    // استخراج البيانات من الرسالة
    String action = data['action']?.toString().trim() ?? '';
    final String postId = data['post_id']?.toString() ?? '';
    final String postTitle = data['post_title']?.toString() ?? '';
    final String nextReminderTime = data['next_reminder_time']?.toString() ?? '';
    
    // عرض البيانات المستخرجة
    globals.showGlobalSnackBar(
      '� FCM: action=$action, postId=$postId',
      backgroundColor: Colors.blue,
      clearPrevious: false,
    );
    
    // إذا كانت action فارغة، نحاول استنتاجها
    if (action.isEmpty) {
      action = data['operation']?.toString().trim() ?? '';
      if (action.isEmpty) {
        action = 'update';
        globals.showGlobalSnackBar(
          '🟠 action فارغ، استخدام: $action',
          backgroundColor: Colors.orange,
          clearPrevious: false,
        );
      }
    }
    
    if (postId.isEmpty) {
      globals.showGlobalSnackBar(
        '⚠️ postId فارغ - تجاهل الرسالة',
        backgroundColor: Colors.orange,
        clearPrevious: false,
      );
      return;
    }
    
    int? reminderId;
    try {
      reminderId = int.parse(postId);
    } catch (e) {
      globals.showGlobalSnackBar(
        '❌ خطأ في تحويل postId: $e',
        backgroundColor: Colors.red,
        clearPrevious: false,
      );
      return;
    }
    
    // عرض معلومات المعالجة
    globals.showGlobalSnackBar(
      '🔄 معالجة: ID=$reminderId, action=$action',
      backgroundColor: Colors.cyan,
      clearPrevious: false,
    );
    
    // التحقق مما إذا كان التذكير موجودًا محليًا
    bool existsLocally = _readReminders.any((r) => r.id == reminderId) ||
                         _unreadReminders.any((r) => r.id == reminderId);
    
    globals.showGlobalSnackBar(
      '📍 موجود محلياً: $existsLocally',
      backgroundColor: Colors.purple,
      clearPrevious: false,
    );
    
    switch (action.toLowerCase().trim()) {
      case 'reminder_updated':
      case 'update':
        globals.showGlobalSnackBar(
          '� SWITCH: update - بدء المعالجة',
          backgroundColor: Colors.teal,
          clearPrevious: false,
        );
        if (existsLocally) {
          await handleUpdateFromFcm(reminderId);
        } else {
          await handleNewReminderFromFcm(reminderId);
        }
        globals.showGlobalSnackBar(
          '✅ update: اكتمل!',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );
        break;
        
      case 'reschedule':
        globals.showGlobalSnackBar(
          '� SWITCH: reschedule - بدء المعالجة',
          backgroundColor: Colors.teal,
          clearPrevious: false,
        );
        if (existsLocally) {
          await handleRescheduleFromFcm(reminderId);
        } else {
          await handleNewReminderFromFcm(reminderId);
        }
        globals.showGlobalSnackBar(
          '✅ reschedule: اكتمل!',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );
        break;
        
      case 'new':
        globals.showGlobalSnackBar(
          '🆕 SWITCH: new - بدء المعالجة',
          backgroundColor: Colors.teal,
          clearPrevious: false,
        );
        await handleNewReminderFromFcm(reminderId);
        globals.showGlobalSnackBar(
          '✅ new: اكتمل! Title: $postTitle',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );
        break;
        
      case 'markas_read':
      case 'mark_as_read':
        globals.showGlobalSnackBar(
          '✅ SWITCH: mark_as_read - بدء المعالجة',
          backgroundColor: Colors.teal,
          clearPrevious: false,
        );
        if (existsLocally) {
          await handleMarkAsReadFromFcm(reminderId);
        } else {
          try {
            final reminder = await _apiService.getReminderById(reminderId);
            if (reminder.id == reminderId && reminder.isOpened == 1) {
              _readReminders.add(reminder);
              _readReminders.sort((a, b) => b.id.compareTo(a.id));
              await _updateCachedReminderFixed(reminder);
              notifyListeners();
            }
          } catch (e) {
            globals.showGlobalSnackBar(
              '❌ خطأ جلب التذكير: $e',
              backgroundColor: Colors.red,
              clearPrevious: false,
            );
          }
        }
        globals.showGlobalSnackBar(
          '✅ mark_as_read: اكتمل!',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );
        break;
        
      case 'delete':
        globals.showGlobalSnackBar(
          '🗑️ SWITCH: delete - بدء المعالجة',
          backgroundColor: Colors.teal,
          clearPrevious: false,
        );
        if (existsLocally) {
          await deleteReminderComprehensive(reminderId);
        }
        globals.showGlobalSnackBar(
          '✅ delete: اكتمل!',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );
        break;
        
      default:
        globals.showGlobalSnackBar(
          '⚠️ action غير مدعوم: $action',
          backgroundColor: Colors.orange,
          clearPrevious: false,
        );
    }
    
    // رسالة الاكتمال النهائية
    globals.showGlobalSnackBar(
      '🎉 FCM اكتمل! ID=$reminderId',
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 4),
      clearPrevious: false,
    );
    
  } catch (e, stackTrace) {
    // عرض الخطأ بشكل واضح
    globals.showGlobalSnackBar(
      '❌ خطأ FCM: ${e.runtimeType}',
      backgroundColor: Colors.red,
      clearPrevious: false,
      duration: const Duration(seconds: 5),
    );
    
    // عرض تفاصيل الخطأ
    globals.showGlobalSnackBar(
      '📛 التفاصيل: $e',
      backgroundColor: Colors.red.shade900,
      clearPrevious: false,
      duration: const Duration(seconds: 5),
    );
    
    // طباعة stack trace في console
    debugPrint('❌❌❌ handleFcmData ERROR: $e');
    debugPrint('Stack trace: $stackTrace');
  }
}

  Future<void> handleRescheduleFromFcm(int reminderId) async {
    try {
      _safeShowMessage('🟢 [handleRescheduleFromFcm] === STARTED for reminder $reminderId ===');
      _safeShowMessage('Processing reschedule of reminder from FCM: $reminderId', isImportant: true, color: Colors.cyan);
      final updatedReminder = await _apiService.getReminderById(reminderId);

      if (updatedReminder.id == reminderId) {
        bool foundInRead = _readReminders.any((r) => r.id == reminderId);
        bool foundInUnread = _unreadReminders.any((r) => r.id == reminderId);

        if (foundInRead || foundInUnread) {
          _readReminders.removeWhere((r) => r.id == reminderId);
          _unreadReminders.removeWhere((r) => r.id == reminderId);
          final targetList =
              updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
          targetList.add(updatedReminder);
          targetList.sort((a, b) => b.id.compareTo(a.id));
          await _notificationService.cancelReminderNotifications(reminderId);
          if (updatedReminder.isOpened != 1 &&
              updatedReminder.nextReminderTime != null &&
              updatedReminder.nextReminderTime!.isNotEmpty) {
            await _scheduleReminderNotifications(updatedReminder);
          }
          await _updateCachedReminderFixed(updatedReminder);
          notifyListeners();
          _safeShowMessage('🟢 [handleRescheduleFromFcm] === COMPLETED successfully for reminder $reminderId ===');
          _safeShowMessage('Rescheduled reminder $reminderId successfully from FCM', isImportant: true, color: Colors.green);
        } else {
          _safeShowMessage('🔴 [handleRescheduleFromFcm] Reminder $reminderId not found in local lists');
          _safeShowMessage('Reminder $reminderId not found in local lists', isImportant: true, color: Colors.orange);
        }
      } else {
        _safeShowMessage('🔴 [handleRescheduleFromFcm] Failed to fetch reminder $reminderId from server');
        _safeShowMessage('Failed to fetch rescheduled reminder $reminderId from server', isImportant: true, color: Colors.red);
      }
    } catch (e) {
      _safeShowMessage('🔴 [handleRescheduleFromFcm] === ERROR for reminder $reminderId: $e ===');
      _safeShowMessage('Error processing reschedule from FCM: $e', isImportant: true, color: Colors.red);
    }
  }

  Future<void> handleNewReminderFromFcm(int reminderId) async {
    globals.showGlobalSnackBar(
      '🆕 handleNewReminderFromFcm بدأت: ID=$reminderId',
      backgroundColor: Colors.cyan,
      clearPrevious: false,
    );
    
  try {
      bool exists = _readReminders.any((r) => r.id == reminderId) ||
          _unreadReminders.any((r) => r.id == reminderId);

      globals.showGlobalSnackBar(
        '📍 موجود مسبقاً: $exists',
        backgroundColor: exists ? Colors.orange : Colors.green,
        clearPrevious: false,
      );

      if (!exists) {
        globals.showGlobalSnackBar(
          '📥 جاري جلب التذكير من السيرفر...',
          backgroundColor: Colors.blue,
          clearPrevious: false,
        );
        
        final newReminder = await _apiService.getReminderById(reminderId);

        globals.showGlobalSnackBar(
          '✅ تم جلب التذكير: ${newReminder.id}',
          backgroundColor: Colors.green,
          clearPrevious: false,
        );

        if (newReminder.id == reminderId) {
          final targetList =
              newReminder.isOpened == 1 ? _readReminders : _unreadReminders;
          targetList.add(newReminder);
          targetList.sort((a, b) => b.id.compareTo(a.id));

          if (newReminder.isOpened != 1) {
            await _scheduleReminderNotifications(newReminder);
          }

          await _updateCachedReminderFixed(newReminder);
          _totalReminders++;
          notifyListeners();
          
          globals.showGlobalSnackBar(
            '🎉 تمت إضافة التذكير بنجاح!',
            backgroundColor: Colors.green,
            clearPrevious: false,
          );
        } else {
          globals.showGlobalSnackBar(
            '❌ فشل جلب التذكير',
            backgroundColor: Colors.red,
            clearPrevious: false,
          );
        }
    } else {
        globals.showGlobalSnackBar(
          '🔄 التذكير موجود، جاري التحديث...',
          backgroundColor: Colors.orange,
          clearPrevious: false,
        );
        await handleUpdateFromFcm(reminderId);
      }
    } catch (e) {
      globals.showGlobalSnackBar(
        '❌ خطأ handleNewReminderFromFcm: $e',
        backgroundColor: Colors.red,
        clearPrevious: false,
      );
    }
  }

  Future<void> handleMarkAsReadFromFcm(int reminderId) async {
  try {
    _safeShowMessage('🟢 [handleMarkAsReadFromFcm] === STARTED for reminder $reminderId ===');
    _safeShowMessage('Processing mark as read from FCM: $reminderId', isImportant: true, color: Colors.cyan);

      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);

      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];

        _unreadReminders.removeAt(reminderIndex);

        final updatedReminder = reminder.copyWith(
          isOpened: 1,
          nextReminderTime: null,
        );

        _readReminders.add(updatedReminder);
        _readReminders.sort((a, b) => b.id.compareTo(a.id));

        await _notificationService.cancelReminderNotifications(reminderId);

        await _updateCachedReminderFixed(updatedReminder);

        notifyListeners();
        _safeShowMessage('🟢 [handleMarkAsReadFromFcm] === COMPLETED successfully for reminder $reminderId ===');
        _safeShowMessage('Marked reminder $reminderId as read from FCM', isImportant: true, color: Colors.green);
      } else {
        _safeShowMessage('🔴 [handleMarkAsReadFromFcm] Reminder $reminderId not found in unread list');
        _safeShowMessage('Reminder $reminderId not found in unread list', isImportant: true, color: Colors.orange);

        try {
          final reminder = await _apiService.getReminderById(reminderId);
          if (reminder.id == reminderId && reminder.isOpened == 1) {
            final existsInRead = _readReminders.any((r) => r.id == reminderId);
            if (!existsInRead) {
              _readReminders.add(reminder);
              _readReminders.sort((a, b) => b.id.compareTo(a.id));
              await _updateCachedReminderFixed(reminder);
              notifyListeners();
              _safeShowMessage('🟢 [handleMarkAsReadFromFcm] Reminder fetched from server successfully');
              _safeShowMessage('Added read reminder $reminderId from server', isImportant: true, color: Colors.green);
            }
          }
        } catch (e) {
          _safeShowMessage('🔴 [handleMarkAsReadFromFcm] Error fetching reminder from server: $e');
          _safeShowMessage('Error fetching reminder from server: $e', isImportant: true, color: Colors.red);
        }
      }
  } catch (e) {
    _safeShowMessage('🔴 [handleMarkAsReadFromFcm] === ERROR for reminder $reminderId: $e ===');
    _safeShowMessage('Error processing mark as read from FCM: $e', isImportant: true, color: Colors.red);
    }
  }

  Future<void> updateReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;

      if (reminderId == 0) {
        _safeShowMessage('Invalid reminder ID');
        return;
      }

      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);

      final targetList =
          reminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));

      await _notificationService.cancelReminderNotifications(reminderId);
      if (reminder.isOpened != 1) {
        await _scheduleReminderNotifications(reminder);
      }

      await _updateCachedReminderFixed(reminder);

      notifyListeners();
      _safeShowMessage('Updated reminder $reminderId from server data');
    } catch (e) {
      _safeShowMessage('Error updating reminder from server data: $e');
    }
  }

  Future<void> handleGetReminderByIdResponse(
      Map<String, dynamic> response) async {
    try {
      if (response['success'] == true && response['reminder'] != null) {
        final reminderData = response['reminder'] as Map<String, dynamic>;
        await updateReminderFromServerData(reminderData);
      } else {
        _safeShowMessage('Failed to get reminder from server: ${response['message']}');
      }
    } catch (e) {
      _safeShowMessage('Error processing getReminderById response: $e');
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
      _safeShowMessage('خطأ في إزالة التذكير من التخزين المؤقت: $e');
    }
  }

  // ===== الحل الرابع: إضافة دالة للحفظ الفوري =====
  Future<void> forceSaveCurrentState() async {
    try {
      _safeShowMessage('🔄 حفظ فوري للحالة الحالية...');

      // حفظ جميع التذكيرات الحالية في الصفحة الأولى
      final allCurrentReminders = [..._readReminders, ..._unreadReminders];
      if (allCurrentReminders.isNotEmpty) {
        await _cacheRemindersForPage(1, allCurrentReminders);

        // تحديث عداد الصفحات
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_totalKey, _totalReminders);
      }

      _safeShowMessage('✅ تم الحفظ الفوري للحالة');
    } catch (e) {
      _safeShowMessage('❌ خطأ في الحفظ الفوري: $e');
    }
  }

  /// تهيئة النظام للعمل بدون إنترنت
  Future<void> initializeOfflineMode() async {
    _safeShowMessage('🔄 تهيئة النظام للعمل بدون إنترنت...');

    try {
      _setLoading(true);

      // تحميل البيانات المخزنة محلياً بدون محاولة المزامنة مع السيرفر
      await _loadOfflineCachedData();

      // جدولة الإشعارات للتذكيرات المحلية
      await _scheduleOfflineNotifications();

      _isInitialized = true;
      _safeShowMessage('✅ تم تهيئة النظام للعمل بدون إنترنت بنجاح');
    } catch (e) {
      _safeShowMessage('❌ خطأ في تهيئة النظام للعمل بدون إنترنت: $e');
      // حتى لو فشلت التهيئة، نحاول تحميل البيانات الأساسية
      await _loadBasicOfflineData();
    } finally {
      _setLoading(false);
    }
  }

  /// تحديث حالة التذكير محلياً فقط (بدون استدعاء API) وتحديث الواجهة.
  /// تستخدم للتحديث الاستباقي عند الضغط على الإشعار.
  Future<void> markReminderAsReadLocally(int reminderId) async {
    try {
      _safeShowMessage('🔄 تحديث استباقي محلي للتذكير $reminderId...');

      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);

      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];

        // نقل التذكير من غير المقروءة إلى المقروءة
        _unreadReminders.removeAt(reminderIndex);

        final updatedReminder = reminder.copyWith(
          isOpened: 1,
          nextReminderTime: null, // التذكيرات المقروءة ليس لها وقت تذكير قادم
        );

        _readReminders.add(updatedReminder);
        _readReminders.sort((a, b) => b.id.compareTo(a.id));

        // تحديث التخزين المؤقت لضمان استمرارية الحالة
        await _updateCachedReminderFixed(updatedReminder);

        // تحديث الواجهة فوراً
        notifyListeners();

        _safeShowMessage('✅ تم التحديث المحلي الاستباقي بنجاح للتذكير $reminderId.');
      } else {
        _safeShowMessage(
            '⚠️ لم يتم العثور على التذكير $reminderId في القائمة غير المقروءة للتحديث المحلي.');
      }
    } catch (e) {
      _safeShowMessage('❌ خطأ في التحديث المحلي للتذكير $reminderId: $e');
    }
  }

  /// تحميل البيانات المخزنة محلياً بدون محاولة الاتصال بالسيرفر
  Future<void> _loadOfflineCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _safeShowMessage('📁 تحميل البيانات المخزنة محلياً...');

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

        _safeShowMessage(
            '✅ تم تحميل ${allCachedReminders.length} تذكير من التخزين المحلي');
        _safeShowMessage('   - مقروءة: ${_readReminders.length}');
        _safeShowMessage('   - غير مقروءة: ${_unreadReminders.length}');
      } else {
        _safeShowMessage('⚠️ لا توجد تذكيرات مخزنة محلياً');
      }

      // تحميل الفلاتر المخزنة
      await _loadFiltersFromCache(prefs);

      // تحديث العدد الإجمالي
      _totalReminders = allCachedReminders.length;
      _currentPage = page;

      notifyListeners();
    } catch (e) {
      _safeShowMessage('❌ خطأ في تحميل البيانات المخزنة محلياً: $e');
      rethrow;
    }
  }

  /// جدولة الإشعارات للتذكيرات المحلية (بدون إنترنت)
  Future<void> _scheduleOfflineNotifications() async {
    try {
      _safeShowMessage('📅 جدولة الإشعارات للتذكيرات المحلية...');

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
              _safeShowMessage('تم تخطي التذكير ${reminder.id} - الموعد في الماضي');
            }
          }
        } catch (e) {
          _safeShowMessage('خطأ في جدولة إشعار التذكير ${reminder.id}: $e');
          continue;
        }
      }

      _safeShowMessage('✅ تم جدولة $scheduledCount إشعار تذكير للوضع بدون إنترنت');
    } catch (e) {
      _safeShowMessage('❌ خطأ في جدولة الإشعارات للوضع بدون إنترنت: $e');
    }
  }

  /// تحميل البيانات الأساسية في حالة فشل التحميل الكامل
  Future<void> _loadBasicOfflineData() async {
    try {
      _safeShowMessage('📋 تحميل البيانات الأساسية للوضع بدون إنترنت...');

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
        _safeShowMessage('لا توجد تذكيرات محلية متاحة: $e');
        _readReminders = [];
        _unreadReminders = [];
        _totalReminders = 0;
      }

      _currentPage = 1;
      notifyListeners();

      _safeShowMessage('✅ تم تحميل البيانات الأساسية للوضع بدون إنترنت');
    } catch (e) {
      _safeShowMessage('❌ خطأ في تحميل البيانات الأساسية: $e');
    }
  }

  /// حفظ منشور جديد
  /// حفظ منشور جديد باستخدام URL وأهمية فقط
  /// الحصول على تحليل إحصائيات المنشورات المفتوحة
  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    try {
      _safeShowMessage('📊 جلب تحليل إحصائيات المنشورات المفتوحة...');

      // استدعاء API للحصول على إحصائيات المنشورات المفتوحة
      final response = await _apiService.getOpenedStatsAnalysis();

      if (response['success'] == true) {
        _safeShowMessage('✅ تم جلب تحليل الإحصائيات بنجاح');
        return response['data'] as Map<String, dynamic>;
      } else {
        _safeShowMessage('❌ فشل في جلب الإحصائيات: ${response['message']}');
        throw Exception(response['message'] ?? 'فشل في جلب تحليل الإحصائيات');
      }
    } catch (e) {
      _safeShowMessage('❌ خطأ في جلب تحليل الإحصائيات: $e');
      rethrow;
    }
  }

  /// الحصول على إحصائيات المنشورات المحفوظة
  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    try {
      _safeShowMessage('📈 جلب إحصائيات المنشورات المحفوظة...');

      // استدعاء API للحصول على إحصائيات المنشورات المحفوظة
      final response = await _apiService.getSavedPostStatistics();

      if (response['success'] == true) {
        _safeShowMessage('✅ تم جلب إحصائيات المنشورات المحفوظة بنجاح');
        return response['data'] as Map<String, dynamic>;
      } else {
        _safeShowMessage('❌ فشل في جلب الإحصائيات: ${response['message']}');
        throw Exception(
            response['message'] ?? 'فشل في جلب إحصائيات المنشورات المحفوظة');
      }
    } catch (e) {
      _safeShowMessage('❌ خطأ في جلب إحصائيات المنشورات المحفوظة: $e');
      rethrow;
    }
  }

  /// التحقق من وجود تذكيرات مخزنة محلياً
  Future<bool> hasOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // فحص الصفحة الأولى على الأقل
      const firstPageKey = '${_sessionRemindersKeyPrefix}1';
      final cachedData = prefs.getString(firstPageKey);

      if (cachedData != null && cachedData.isNotEmpty) {
        try {
          final List<dynamic> remindersList = jsonDecode(cachedData);
          return remindersList.isNotEmpty;
        } catch (e) {
          _safeShowMessage('خطأ في قراءة البيانات المحلية: $e');
          return false;
        }
      }

      return false;
    } catch (e) {
      _safeShowMessage('خطأ في فحص البيانات المحلية: $e');
      return false;
    }
  }
}
