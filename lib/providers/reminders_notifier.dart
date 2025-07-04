import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemindersNotifier extends ChangeNotifier {
  List<Reminder> _readReminders = [];
  List<Reminder> _unreadReminders = [];
  List<String> _categories = [];
  List<String> _complexities = [];
  List<String> _domains = [];
  int _totalReminders = 0;
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;

  List<Reminder> get readReminders => _readReminders;
  List<Reminder> get unreadReminders => _unreadReminders;
  List<String> get categories => _categories;
  List<String> get complexities => _complexities;
  List<String> get domains => _domains;
  int get totalReminders => _totalReminders;
  int get currentPage => _currentPage;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;

  static const String _categoriesKey = 'cached_categories';
  static const String _complexitiesKey = 'cached_complexities';
  static const String _domainsKey = 'cached_domains';
  static const String _totalKey = 'cached_total';
  static const String _sessionRemindersKeyPrefix = 'session_reminders_page_';

  final ApiService _apiService = ApiService();

  Future<void> initialize() async {
    if (_readReminders.isEmpty && _unreadReminders.isEmpty) {
      await loadCachedData();
      if (_readReminders.isEmpty && _unreadReminders.isEmpty) {
        await fetchReminders(forceFetch: true);
      }
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
      throw e;
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

          // فحص وإعادة جدولة التذكيرات غير المقروءة
          await _checkAndRescheduleUnreadReminders();

          _categories = [allLabel]..addAll(response.categories);
          _complexities = [allLabel]..addAll(response.complexities);
          _domains = [allLabel]..addAll(response.domains ?? []);
          _totalReminders = response.total ?? 0;
          _currentPage = 2;

          await _cacheRemindersForPage(1, response.reminders);
          await _saveCachedData(response);
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

          // فحص وإعادة جدولة التذكيرات غير المقروءة
          await _checkAndRescheduleUnreadReminders();

          _currentPage++;

          await _cacheRemindersForPage(_currentPage - 1, response.reminders);
        }
      }
    } catch (e) {
      print('خطأ في جلب التذكيرات: $e');
      throw e;
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> updateSingleReminder(int reminderId) async {
    try {
      final updatedReminder = await _apiService.getReminderById(reminderId);
      if (updatedReminder.id == reminderId) {
        _readReminders.removeWhere((r) => r.id == reminderId);
        _unreadReminders.removeWhere((r) => r.id == reminderId);

        final targetList =
            updatedReminder.isOpened == 1 ? _readReminders : _unreadReminders;
        targetList.add(updatedReminder);
        targetList.sort((a, b) => b.id.compareTo(a.id));

        await _updateCachedReminder(updatedReminder);
        notifyListeners();
      }
    } catch (e) {
      print('خطأ في تحديث التذكير: $e');
      throw e;
    }
  }

  Future<void> deleteReminder(int id) async {
    try {
      await _apiService.deleteReminder(id);
      _readReminders.removeWhere((r) => r.id == id);
      _unreadReminders.removeWhere((r) => r.id == id);
      await _deleteCachedReminder(id);
      _totalReminders = _totalReminders > 0 ? _totalReminders - 1 : 0;
      notifyListeners();
    } catch (e) {
      print('خطأ في حذف التذكير: $e');
      throw e;
    }
  }

  Future<void> forceRefreshReminders() async {
    _currentPage = 1;
    _readReminders.clear();
    _unreadReminders.clear();
    await _clearSessionCache();
    await fetchReminders(forceFetch: true);
  }

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

  void _setLoadingState(bool isLoadMore) {
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
      if (response.domains != null) {
        await prefs.setString(_domainsKey, jsonEncode(response.domains!));
      }
      await prefs.setInt(_totalKey, response.total ?? 0);
    } catch (e) {
      print('خطأ في حفظ البيانات: $e');
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

  Future<void> _updateCachedReminder(Reminder updatedReminder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith(_sessionRemindersKeyPrefix)) {
          final cachedRemindersJson = prefs.getString(key);
          if (cachedRemindersJson != null) {
            final List<dynamic> remindersList = jsonDecode(cachedRemindersJson);
            final updatedList = remindersList.map((r) {
              if (r['id'] == updatedReminder.id) {
                return updatedReminder.toJson();
              }
              return r;
            }).toList();
            await prefs.setString(key, jsonEncode(updatedList));
          }
        }
      }
    } catch (e) {
      print('خطأ في تحديث التذكير في التخزين المؤقت: $e');
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
