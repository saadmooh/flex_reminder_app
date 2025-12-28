import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/reminders_service.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/globals.dart' as globals;

/// Provider لإدارة حالة التذكيرات والتفاعل مع الواجهة
class RemindersNotifier extends ChangeNotifier {
  // ============================================================================
  // Singleton Pattern
  // ============================================================================
  static RemindersNotifier? _instance;
  
  static RemindersNotifier get instance {
    if (_instance == null) {
      _instance = RemindersNotifier._internal();
    }
    return _instance!;
  }

  static bool get hasInstance => _instance != null;

  RemindersNotifier._internal() {
    navigatorKey = globals.navigatorKey;
  }

  factory RemindersNotifier({GlobalKey<NavigatorState>? navigatorKey}) {
    final inst = RemindersNotifier.instance;
    if (navigatorKey != null) {
      inst.navigatorKey = navigatorKey;
    }
    return inst;
  }

  // ============================================================================
  // المتغيرات والحقول
  // ============================================================================
  final RemindersService _service = RemindersService.instance;
  
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
  
  AuthProvider? _authProvider;
  GlobalKey<NavigatorState>? navigatorKey;

  static bool _isInitializingInProgress = false;
  static DateTime? _lastInitialization;
  static DateTime? _lastFcmUpdate;
  static const Duration _initializationCooldown = Duration(seconds: 30);
  static const Duration _fcmUpdateWindow = Duration(minutes: 5);

  // ============================================================================
  // Getters
  // ============================================================================
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

  // ============================================================================
  // دوال التهيئة والإعداد
  // ============================================================================

  /// دالة التهيئة الصريحة - تُستدعى مرة واحدة عند بدء التطبيق
  Future<void> initialize({AuthProvider? authProvider}) async {
    if (globals.isRemindersNotifierInitialized) {
      return;
    }
    
    if (authProvider != null) {
      setAuthProvider(authProvider);
    }

    navigatorKey = globals.navigatorKey;
    globals.isRemindersNotifierInitialized = true;
  }

  /// ربط AuthProvider
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  /// تهيئة محسّنة
  Future<void> initializeImproved({bool forceRefresh = false}) async {
    if (_authProvider == null) {
      return;
    }

    if (_isInitialized && !forceRefresh) {
      if (_lastFcmUpdate != null) {
        final timeSinceLastFcm = DateTime.now().difference(_lastFcmUpdate!);
        if (timeSinceLastFcm < _fcmUpdateWindow) {
          return;
        }
      }
      return;
    }

    if (!forceRefresh && _lastInitialization != null) {
      final timeSinceLastInit = DateTime.now().difference(_lastInitialization!);
      if (timeSinceLastInit < _initializationCooldown) {
        return;
      }
    }

    _isInitializingInProgress = true;
    _setLoading(true);

    try {
      await loadCachedDataImproved();

      if ((_readReminders.isEmpty && _unreadReminders.isEmpty) ||
          forceRefresh) {
        await fetchReminders(forceFetch: true);
      }
      await RemindersService.instance.rescheduleAllNotifications(unreadReminders);
  
      _isInitialized = true;
      _lastInitialization = DateTime.now();
      await _service.saveLastInitialization(_lastInitialization!);
    } catch (e) {
      rethrow;
    } finally {
      _isInitializingInProgress = false;
      _setLoading(false);
    }
  }

  /// تهيئة الوضع غير المتصل
  Future<void> initializeOfflineMode() async {
    try {
      _setLoading(true);

      await _loadOfflineCachedData();
      await _service.scheduleOfflineNotifications(_unreadReminders);

      _isInitialized = true;
    } catch (e) {
      await _loadBasicOfflineData();
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================================
  // دوال تحميل البيانات
  // ============================================================================

  /// تحميل البيانات المخزنة مؤقتاً - محسّن
  Future<void> loadCachedDataImproved() async {
    try {
      final Map<int, Reminder> currentInMemoryReminders = {};

      for (final reminder in [..._readReminders, ..._unreadReminders]) {
        currentInMemoryReminders[reminder.id] = reminder;
      }

      late List<int> serverIds;
      try {
        serverIds = await _service.getRemindersIds();
      } catch (e) {
        serverIds = [];
      }

      List<Reminder> localReminders = [];
      int page = 1;
      while (true) {
        final reminders = await _service.loadCachedReminders(page);
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
          if (_service.isReminderNewer(inMemoryReminder, localReminder)) {
            localReminders[localIndex] = inMemoryReminder;
            await _service.updateCachedReminder(inMemoryReminder, _currentPage);
          }
        } else if (serverIds.contains(id)) {
          localReminders.add(inMemoryReminder);
          await _service.updateCachedReminder(inMemoryReminder, _currentPage);
        }
      }

      final Set<int> localIds = localReminders.map((r) => r.id).toSet();
      final Set<int> serverIdSet = serverIds.toSet();

      final List<int> deletedIds = localIds.difference(serverIdSet).toList();
      for (int id in deletedIds) {
        if (!currentInMemoryReminders.containsKey(id)) {
          await deleteReminderLocally(id);
          localReminders.removeWhere((r) => r.id == id);
        }
      }

      final List<int> missingIds = serverIdSet.difference(localIds).toList();
      if (missingIds.isNotEmpty) {
        final missingReminders = await Future.wait(
          missingIds.map((id) async {
            try {
              return await _service.getReminderById(id);
            } catch (e) {
              return null;
            }
          }).where((f) => f != null),
          eagerError: true,
        );

        for (final reminder in missingReminders.whereType<Reminder>()) {
          localReminders.add(reminder);
          await _service.updateCachedReminder(reminder, _currentPage);
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

      final filters = await _service.loadFiltersFromCache();
      _categories = filters['categories']!;
      _complexities = filters['complexities']!;
      _domains = filters['domains']!;
      
      _totalReminders = serverIds.length;
      _currentPage = page;
      
      await _checkAndRescheduleUnreadReminders();
      await _service.cleanupCachedReminders(_currentPage);
      notifyListeners();
    } catch (e) {
      await _loadCachedDataFallback();
    }
  }

  /// تحميل البيانات المخزنة - احتياطي
  Future<void> _loadCachedDataFallback() async {
    try {
      int page = 1;
      List<Reminder> cachedReminders = [];
      while (true) {
        final reminders = await _service.loadCachedReminders(page);
        if (reminders.isEmpty) break;
        cachedReminders.addAll(reminders);
        page++;
      }

      final filters = await _service.loadFiltersFromCache();
      _categories = filters['categories']!;
      _complexities = filters['complexities']!;
      _domains = filters['domains']!;

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
      // Handle error silently
    }
  }

  /// تحميل البيانات المخزنة محلياً (بدون إنترنت)
  Future<void> _loadOfflineCachedData() async {
    try {
      List<Reminder> allCachedReminders = [];
      int page = 1;

      while (true) {
        final pageReminders = await _service.loadCachedReminders(page);
        if (pageReminders.isEmpty) break;
        allCachedReminders.addAll(pageReminders);
        page++;
      }

      if (allCachedReminders.isNotEmpty) {
        _readReminders = allCachedReminders
            .where((r) => r.isOpened == 1)
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));

        _unreadReminders = allCachedReminders
            .where((r) => r.isOpened == 0)
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));

        final unclassified = allCachedReminders
            .where((r) => r.isOpened != 0 && r.isOpened != 1)
            .toList();
        if (unclassified.isNotEmpty) {
          _unreadReminders.addAll(unclassified);
          _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
        }

        final filters = await _service.loadFiltersFromCache();
        _categories = filters['categories']!;
        _complexities = filters['complexities']!;
        _domains = filters['domains']!;

        _totalReminders = allCachedReminders.length;
        _currentPage = page;

        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// تحميل البيانات الأساسية (احتياطي)
  Future<void> _loadBasicOfflineData() async {
    try {
      _categories = ['الكل'];
      _complexities = ['الكل'];
      _domains = ['الكل'];

      try {
        final firstPageReminders = await _service.loadCachedReminders(1);
        if (firstPageReminders.isNotEmpty) {
          _readReminders =
              firstPageReminders.where((r) => r.isOpened == 1).toList();
          _unreadReminders =
              firstPageReminders.where((r) => r.isOpened == 0).toList();
          _totalReminders = firstPageReminders.length;
        }
      } catch (e) {
        _readReminders = [];
        _unreadReminders = [];
        _totalReminders = 0;
      }

      _currentPage = 1;
      notifyListeners();
    } catch (e) {
      // Handle error silently
    }
  }

  // ============================================================================
  // دوال جلب التذكيرات
  // ============================================================================

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
      
      final response = await _service.fetchReminders(
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
          await _service.clearSessionCache();
          
          final newReminders = response.reminders.where((r) {
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
          
          await _service.cacheRemindersForPage(1, newReminders);
          await _service.saveCachedData(response);
          await _service.rescheduleAllNotifications(_unreadReminders);
          _ensureUniqueReminders();
        } else {
          final newReminders = response.reminders.where((r) {
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
          
          await _service.cacheRemindersForPage(_currentPage - 1, newReminders);
          
          for (final reminder in [...newUnreadReminders, ...newUnclassified]) {
            await _service.scheduleReminderNotifications(reminder);
          }
          _ensureUniqueReminders();
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// إعادة تحميل التذكيرات بالقوة
  Future<void> forceRefreshReminders() async {
    _currentPage = 1;
    _readReminders.clear();
    _unreadReminders.clear();
    await _service.clearSessionCache();
    await _service.cancelAllNotifications();
    await fetchReminders(forceFetch: true);
  }

  // ============================================================================
  // دوال إدارة التذكيرات - الإضافة والتحديث
  // ============================================================================

  /// حفظ منشور جديد
  Future<Reminder> savePost(String url, String importance) async {
    try {
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
      
      final response = await _service.savePost(postData);
      final newReminder = Reminder.fromJson(response['post']);

      if (await _reminderExistsComprehensively(newReminder.id)) {
        return newReminder;
      }

      _unreadReminders.add(newReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      await _service.scheduleReminderNotifications(newReminder);
      await _service.updateCachedReminder(newReminder, _currentPage);
      _totalReminders++;
      _ensureUniqueReminders();
      notifyListeners();
      return newReminder;
    } catch (e) {
      rethrow;
    }
  }

  /// إنشاء تذكير جديد
  Future<Reminder> createReminder(Map<String, dynamic> reminderData) async {
    try {
      final response = await _service.savePost(reminderData);
      final newReminder = Reminder.fromJson(response['post']);

      if (_reminderExistsLocally(newReminder.id)) {
        return newReminder;
      }

      _unreadReminders.add(newReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      await _service.scheduleReminderNotifications(newReminder);
      await _service.updateCachedReminder(newReminder, _currentPage);
      _totalReminders++;
      notifyListeners();
      return newReminder;
    } catch (e) {
      rethrow;
    }
  }

  /// تحديث تذكير موجود
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

      final response = await _service.updateReminder(updatedReminder);
      final finalUpdatedReminder = Reminder.fromJson(response['post']);
      
      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);
      
      final targetList = finalUpdatedReminder.isOpened == 1
          ? _readReminders
          : _unreadReminders;
      targetList.add(finalUpdatedReminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      
      await _service.cancelReminderNotification(reminderId);
      await _service.scheduleReminderNotifications(finalUpdatedReminder);
      await _service.updateCachedReminder(finalUpdatedReminder, _currentPage);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// تحديث تذكير واحد من السيرفر
  Future<void> updateSingleReminder(int reminderId) async {
    try {
      final updatedReminder = await _service.getReminderById(reminderId);
      
      if (updatedReminder.id == reminderId) {
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);
        
        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));
        
        await _service.cancelReminderNotification(reminderId);
        if (updatedReminder.isOpened != 1) {
          await _service.scheduleReminderNotifications(updatedReminder);
        }
        await _service.updateCachedReminder(updatedReminder, _currentPage);
        notifyListeners();
      } else {
        await deleteReminderLocally(reminderId);
      }
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        await deleteReminderLocally(reminderId);
      } else {
        rethrow;
      }
    }
  }

  /// إضافة تذكير جديد من بيانات السيرفر
  Future<void> addNewReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;
      
      if (reminderId == 0) {
        return;
      }

      if (_reminderExistsLocally(reminderId)) {
        await updateReminderFromServerData(reminderData);
        return;
      }

      final targetList =
          reminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      
      if (reminder.isOpened != 1) {
        await _service.scheduleReminderNotifications(reminder);
      }
      await _service.updateCachedReminder(reminder, _currentPage);
      _totalReminders++;
      notifyListeners();
    } catch (e) {
      // Handle error silently
    }
  }

  /// تحديث تذكير من بيانات السيرفر
  Future<void> updateReminderFromServerData(
      Map<String, dynamic> reminderData) async {
    try {
      final reminder = Reminder.fromJson(reminderData);
      final reminderId = reminder.id;

      if (reminderId == 0) {
        return;
      }

      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);

      final targetList =
          reminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(reminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));

      await _service.cancelReminderNotification(reminderId);
      if (reminder.isOpened != 1) {
        await _service.scheduleReminderNotifications(reminder);
      }

      await _service.updateCachedReminder(reminder, _currentPage);
      notifyListeners();
    } catch (e) {
      // Handle error silently
    }
  }

  /// إعادة جدولة تذكير
  Future<Reminder> rescheduleReminder(String url, String importance) async {
    try {
      final response = await _service.reschedulePost(url, importance);
      final updatedReminder = Reminder.fromJson(response['post']);

      _readReminders.removeWhere((r) => r.id == updatedReminder.id);
      _unreadReminders.removeWhere((r) => r.id == updatedReminder.id);
      _unreadReminders.add(updatedReminder);
      _unreadReminders.sort((a, b) => b.id.compareTo(a.id));
      
      await _service.updateCachedReminder(updatedReminder, _currentPage);
      notifyListeners();
      return updatedReminder;
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // دوال إدارة التذكيرات - الحذف
  // ============================================================================

  /// حذف تذكير محلياً فقط
  Future<void> deleteReminderLocally(int reminderId) async {
    try {
      final existsInRead = _readReminders.any((r) => r.id == reminderId);
      final existsInUnread = _unreadReminders.any((r) => r.id == reminderId);

      if (!existsInRead && !existsInUnread) {
        return;
      }

      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);
      
      await _service.cancelReminderNotification(reminderId);
      await _service.removeCachedReminder(reminderId, _currentPage, _totalReminders);
      
      if (_totalReminders > 0) {
        _totalReminders--;
      }
      
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// حذف تذكير من السيرفر والمحلي
  Future<void> deleteReminder(int id) async {
    try {
      await _service.deleteReminder(id);
      
      final existsInRead = _readReminders.any((r) => r.id == id);
      final existsInUnread = _unreadReminders.any((r) => r.id == id);

      if (!existsInRead && !existsInUnread) {
        return;
      }

      _readReminders.removeWhere((r) => r.id == id);
      _unreadReminders.removeWhere((r) => r.id == id);
      
      await _service.cancelReminderNotification(id);
      await _service.deleteCachedReminder(id, _currentPage);
      
      if (_totalReminders > 0) {
        _totalReminders--;
      }
      
      await forceSaveCurrentState();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 50));
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// حذف تذكير شامل مع ضمان تحديث الواجهة
  Future<void> deleteReminderComprehensive(int id) async {
    try {
      await _service.deleteReminder(id);
      bool actuallyRemoved = false;

      final readIndex = _readReminders.indexWhere((r) => r.id == id);
      if (readIndex != -1) {
        _readReminders.removeAt(readIndex);
        actuallyRemoved = true;
      }

      final unreadIndex = _unreadReminders.indexWhere((r) => r.id == id);
      if (unreadIndex != -1) {
        _unreadReminders.removeAt(unreadIndex);
        actuallyRemoved = true;
      }

      if (!actuallyRemoved) {
        return;
      }

      await _service.cancelReminderNotification(id);
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      await _service.removeCachedReminder(id, _currentPage, _totalReminders);
      await forceSaveCurrentState();
      notifyListeners();
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      rethrow;
    }
  }

  /// حذف تذكير مع ضمان تحديث الواجهة
  Future<void> deleteReminderWithUIGuarantee(int id) async {
    try {
      await _service.deleteReminder(id);
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
        return;
      }

      await _service.cancelReminderNotification(id);
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      await _service.removeCachedReminder(id, _currentPage, _totalReminders);
      await forceSaveCurrentState();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // دوال وضع العلامة كمقروء
  // ============================================================================

  /// وضع علامة كمقروء
  Future<void> markReminderAsRead(int reminderId) async {
    try {
      final reminderIndex =
          _unreadReminders.indexWhere((r) => r.id == reminderId);
          
      if (reminderIndex != -1) {
        final reminder = _unreadReminders[reminderIndex];
        
        if (reminder.url != null && reminder.url!.isNotEmpty) {
          await _service.updateStats(reminder.url!, true);
        }
        
        _unreadReminders.removeAt(reminderIndex);
        
        final updatedReminder = reminder.copyWith(
          isOpened: 1,
          nextReminderTime: null,
        );
        
        _readReminders.add(updatedReminder);
        _readReminders.sort((a, b) => b.id.compareTo(a.id));
        
        await _service.cancelReminderNotification(reminderId);
        await _service.updateCachedReminder(updatedReminder, _currentPage);
        await forceSaveCurrentState();
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// وضع علامة كمقروء محلياً فقط (بدون API)
  Future<void> markReminderAsReadLocally(int reminderId) async {
    try {
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

        await _service.updateCachedReminder(updatedReminder, _currentPage);
        notifyListeners();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // ============================================================================
  // دوال FCM والتحديثات
  // ============================================================================

 // ============================================================================
  // دوال FCM والتحديثات
  // ============================================================================

  /// معالجة بيانات FCM
  Future<void> handleFcmData(Map<String, dynamic> data) async {
    try {
      // 1. استخراج المعرف (ID) وتحويله إلى رقم
      // نفترض أن title يحمل الـ ID بناءً على الكود السابق، أو يمكن استخدام 'id' أو 'post_id'
      final String idString = data['body']?.toString() ?? data['id']?.toString() ?? '';
      final int? reminderId = int.tryParse(idString);
      
      if (reminderId == null) {
        return;
      }

      String action = data['event_type']?.toString().trim() ?? '';
      final actionLower = action.toLowerCase().trim();
      
      // إذا كان الإجراء حذف، لا نحتاج لجلب البيانات من السيرفر (قد تكون حذفت بالفعل)
      if (actionLower == 'delete') {
         // نتحقق إذا كان موجود محلياً لحذفه
         bool existsLocally = _readReminders.any((r) => r.id == reminderId) ||
                              _unreadReminders.any((r) => r.id == reminderId);
         if (existsLocally) {
            await deleteReminderComprehensive(reminderId);
         }
         return;
      }

      // 2. جلب بيانات التذكير مرة واحدة فقط كما طلبت
      final Reminder updatedReminder = await _service.getReminderById(reminderId);

      // التحقق من صحة البيانات المرجعة
      if (updatedReminder.id != reminderId) {
        return; 
      }

      bool existsLocally = _readReminders.any((r) => r.id == reminderId) ||
                           _unreadReminders.any((r) => r.id == reminderId);
      
      // 3. اختيار الحالة المناسبة وتمرير الكائن updatedReminder
      switch (actionLower) {
        case 'update':
          if (existsLocally) {
            await handleUpdateFromFcm(updatedReminder);
          } else {
            await handleNewReminderFromFcm(updatedReminder);
          }
          break;
          
        case 'reschedule':
          if (existsLocally) {
            await handleRescheduleFromFcm(updatedReminder);
          } else {
            await handleNewReminderFromFcm(updatedReminder);
          }
          break;
          
        case 'new':
          await handleNewReminderFromFcm(updatedReminder);
          break;
          
        case 'mark_as_read':
          if (existsLocally) {
            // نمرر الـ ID فقط هنا لأن الدالة تعتمد على الحذف المحلي والنقل
            await handleMarkAsReadFromFcm(reminderId);
          } else {
            // إذا لم يكن موجوداً محلياً وجاء أمر بأنه مقروء، نضيفه للمقروء مباشرة
            if (updatedReminder.isOpened == 1) {
              _readReminders.add(updatedReminder);
              _readReminders.sort((a, b) => b.id.compareTo(a.id));
              await _service.updateCachedReminder(updatedReminder, _currentPage);
              notifyListeners();
            }
          }
          break;
          
        default:
          if (existsLocally) {
            await handleUpdateFromFcm(updatedReminder);
          } else {
            await handleNewReminderFromFcm(updatedReminder);
          }
      }
      
    } catch (e, stackTrace) {
      // Handle error silently
    }
  }

  /// معالجة تحديث من FCM - تم التعديل لاستقبال Reminder
  Future<void> handleUpdateFromFcm(Reminder updatedReminder, {bool isBackground = false}) async {
    try {
      final reminderId = updatedReminder.id;

      _readReminders.removeWhere((r) => r.id == reminderId);
      _unreadReminders.removeWhere((r) => r.id == reminderId);
      
      final targetList =
          updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
      targetList.add(updatedReminder);
      targetList.sort((a, b) => b.id.compareTo(a.id));
      
      await _service.cancelReminderNotification(reminderId);
      if (updatedReminder.isOpened != 1) {
        await _service.scheduleReminderNotifications(updatedReminder);
      }
      await _service.updateCachedReminder(updatedReminder, _currentPage);
      
      _lastFcmUpdate = DateTime.now();

      if (!isBackground) {
        await forceSaveCurrentState();
        notifyListeners();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// معالجة تذكير جديد من FCM - تم التعديل لاستقبال Reminder
  Future<void> handleNewReminderFromFcm(Reminder reminder, {bool isBackground = false}) async {
    try {
      final reminderId = reminder.id;
      bool exists = _readReminders.any((r) => r.id == reminderId) ||
          _unreadReminders.any((r) => r.id == reminderId);

      if (exists) {
        await handleUpdateFromFcm(reminder, isBackground: isBackground);
      } else {
        final targetList =
            reminder.isOpened == 1 ? _readReminders : _unreadReminders;
        
        if (!targetList.any((r) => r.id == reminder.id)) {
          targetList.add(reminder);
          targetList.sort((a, b) => b.id.compareTo(a.id));
          await _service.updateCachedReminder(reminder, _currentPage);
        }
        
        _lastFcmUpdate = DateTime.now();

        if (reminder.isOpened != 1) {
          try {
            await _service.scheduleReminderNotifications(reminder);
          } catch (e) {
            // Handle background error silently
          }
        }
        
        if (!isBackground) notifyListeners();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// معالجة إعادة جدولة من FCM - تم التعديل لاستقبال Reminder
  Future<void> handleRescheduleFromFcm(Reminder updatedReminder, {bool isBackground = false}) async {
    try {
      final reminderId = updatedReminder.id;

      bool foundInRead = _readReminders.any((r) => r.id == reminderId);
      bool foundInUnread = _unreadReminders.any((r) => r.id == reminderId);

      if (foundInRead || foundInUnread) {
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);

        // في إعادة الجدولة عادة يعود إلى غير المقروء إلا إذا نص السيرفر على غير ذلك
        // هنا نلتزم بما جاء من السيرفر في updatedReminder
        final targetList = updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));

        await _service.updateCachedReminder(updatedReminder, _currentPage);
        
        if (!isBackground) {
          await forceSaveCurrentState();
          notifyListeners();
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// معالجة وضع علامة كمقروء من FCM (لم تتغير التوقيع لأنها تعتمد على المنطق المحلي غالباً)
  Future<void> handleMarkAsReadFromFcm(int reminderId, {bool isBackground = false}) async {
    try {
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

        await _service.cancelReminderNotification(reminderId);
        await _service.updateCachedReminder(updatedReminder, _currentPage);
        
        if (!isBackground) {
          await forceSaveCurrentState();
          notifyListeners();
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }


  /// معالجة استجابة getReminderById
  Future<void> handleGetReminderByIdResponse(
      Map<String, dynamic> response) async {
    try {
      if (response['success'] == true && response['reminder'] != null) {
        final reminderData = response['reminder'] as Map<String, dynamic>;
        await updateReminderFromServerData(reminderData);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // ============================================================================
  // دوال التحقق والتنظيف
  // ============================================================================

  /// التحقق من التذكيرات وتنظيفها
  Future<void> validateAndCleanupReminders() async {
    try {
      // Validation logic without prints
    } catch (e) {
      // Handle error silently
    }
  }

  /// التحقق من الحالة بعد الحذف
  Future<void> validateStateAfterDeletion(int deletedId) async {
    try {
      final stillInRead = _readReminders.any((r) => r.id == deletedId);
      final stillInUnread = _unreadReminders.any((r) => r.id == deletedId);

      if (stillInRead || stillInUnread) {
        _readReminders.removeWhere((r) => r.id == deletedId);
        _unreadReminders.removeWhere((r) => r.id == deletedId);
        notifyListeners();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// التحقق من الحذف والتحديث
  Future<void> verifyDeletionAndUpdate(int deletedId) async {
    try {
      final stillExistsInRead = _readReminders.any((r) => r.id == deletedId);
      final stillExistsInUnread =
          _unreadReminders.any((r) => r.id == deletedId);

      if (stillExistsInRead || stillExistsInUnread) {
        _readReminders.removeWhere((r) => r.id == deletedId);
        _unreadReminders.removeWhere((r) => r.id == deletedId);
        notifyListeners();
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// التأكد من عدم وجود تذكيرات مكررة
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
  }

  /// التحقق من وجود التذكير محلياً
  bool _reminderExistsLocally(int reminderId) {
    return _readReminders.any((r) => r.id == reminderId) ||
        _unreadReminders.any((r) => r.id == reminderId);
  }

  /// التحقق الشامل من وجود التذكير
  Future<bool> _reminderExistsComprehensively(int reminderId) async {
    if (_reminderExistsLocally(reminderId)) {
      return true;
    }
    return await _service.reminderExistsInCache(reminderId, _currentPage);
  }

  /// التحقق وإعادة جدولة التذكيرات غير المقروءة
  Future<void> _checkAndRescheduleUnreadReminders() async {
    final updatedReminders = await _service.checkAndRescheduleUnreadReminders(
      _unreadReminders,
    );

    _unreadReminders
      ..clear()
      ..addAll(updatedReminders)
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  // ============================================================================
  // دوال إعادة التعيين والمسح
  // ============================================================================

  /// إعادة تعيين المثيل بالكامل
  Future<void> resetInstance() async {
    try {
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

      _isInitializingInProgress = false;
      _lastInitialization = null;
      _lastFcmUpdate = null;

      _authProvider = null;

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// مسح جميع البيانات المخزنة مؤقتاً
  Future<void> clearSessionCache() async {
    try {
      await _service.clearSessionCache();
      _readReminders.clear();
      _unreadReminders.clear();
    } catch (e) {
      rethrow;
    }
  }

  /// إلغاء جميع الإشعارات
  Future<void> cancelAllNotifications() async {
    try {
      await _service.cancelAllNotifications();
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // دوال مساعدة وخدمات إضافية
  // ============================================================================

  /// الحصول على تذكير بواسطة المعرف
  Future<Reminder?> getReminderById(int reminderId) async {
    var reminder = _readReminders.firstWhere(
      (r) => r.id == reminderId,
      orElse: () => _unreadReminders.firstWhere(
        (r) => r.id == reminderId,
        orElse: () => Reminder(
          id: 0,
          userId: 0,
          title: '',
          scheduledTimes: [],
          nextReminderTime: '',
          isOpened: 0,
        ),
      ),
    );

    if (reminder.id == reminderId) {
      return reminder;
    }

    try {
      reminder = await _service.getReminderById(reminderId);
      if (reminder.id == reminderId) {
        final targetList =
            reminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.removeWhere((r) => r.id == reminderId);
        targetList.add(reminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));
        await _service.updateCachedReminder(reminder, _currentPage);
        notifyListeners();
        return reminder;
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// حفظ الحالة الحالية فوراً
  Future<void> forceSaveCurrentState() async {
    try {
      final allCurrentReminders = [..._readReminders, ..._unreadReminders];
      if (allCurrentReminders.isNotEmpty) {
        await _service.forceSaveCurrentState(
          allCurrentReminders,
          _totalReminders,
        );
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// التحقق من وجود بيانات محلية
  Future<bool> hasOfflineData() async {
    try {
      return await _service.hasOfflineData();
    } catch (e) {
      return false;
    }
  }

  /// الحصول على إحصائيات المنشورات المفتوحة
  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    try {
      return await _service.getOpenedStatsAnalysis();
    } catch (e) {
      rethrow;
    }
  }

  /// الحصول على إحصائيات المنشورات المحفوظة
  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    try {
      return await _service.getSavedPostStatistics();
    } catch (e) {
      rethrow;
    }
  }

  /// التحقق من البريد الإلكتروني
  Future<void> verifyEmail(String email, String code) async {
    try {
      await _service.verifyEmail(email, code);
    } catch (e) {
      rethrow;
    }
  }

  /// إعادة إرسال رمز التحقق
  Future<void> resendVerificationCode(String email) async {
    try {
      await _service.resendVerificationCode(email);
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // دوال الإشعارات (Delegation to Service)
  // ============================================================================

  /// تحديث قناة الإشعارات
  Future<void> updateNotificationChannel() async {
    try {
      await _service.updateNotificationChannel();
    } catch (e) {
      // Handle error silently
    }
  }

  /// التحقق من صلاحيات الإشعارات
  Future<bool> checkNotificationPermissions() async {
    try {
      return await _service.checkNotificationPermissions();
    } catch (e) {
      return false;
    }
  }

  /// طلب صلاحيات الإشعارات
  Future<bool> requestNotificationPermissions() async {
    try {
      return await _service.requestNotificationPermissions();
    } catch (e) {
      return false;
    }
  }

  /// الحصول على حالة خدمة الإشعارات
  Future<Map<String, dynamic>> getNotificationServiceStatus() async {
    try {
      return await _service.getNotificationServiceStatus();
    } catch (e) {
      return {};
    }
  }

  // ============================================================================
  // دوال داخلية مساعدة
  // ============================================================================

  /// تعيين حالة التحميل
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  /// تعيين حالة التحميل (عادي أو تحميل المزيد)
  void _setLoadingState(bool isLoadMore) {
    if (!isLoadMore) {
      _isLoading = true;
    }
    _isLoadingMore = isLoadMore;
    notifyListeners();
  }

  /// طباعة الحالة الحالية للتصحيح
  void debugCurrentState() {
    // No-op - removed all prints
  }
}