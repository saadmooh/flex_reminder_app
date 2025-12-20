import 'package:flutter/material.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/models/reminders_response.dart';
import 'package:flex_reminder/models/user_free_time.dart';
import 'package:flex_reminder/models/user.dart';
import 'api_functions/api_config.dart';
import 'package:flex_reminder/services/reminders_service.dart';
import 'api_functions/auth_service.dart';
import 'api_functions/subscription_service.dart';
import 'api_functions/reminder_service.dart';
import 'api_functions/user_service.dart';
import 'api_functions/stats_service.dart';
import 'api_functions/utils_service.dart';
import 'api_functions/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  final ApiConfig _apiConfig = ApiConfig();
  final AuthService _authService;
  final SubscriptionService _subscriptionService;
  final ReminderService _reminderService;
  final UserService _userService;
  final StatsService _statsService;
  final UtilsService _utilsService;

  ApiService()
      : _utilsService = UtilsService(ApiConfig()),
        _authService = AuthService(ApiConfig()),
        _subscriptionService = SubscriptionService(UtilsService(ApiConfig())),
        _reminderService = ReminderService(UtilsService(ApiConfig())),
        _userService = UserService(UtilsService(ApiConfig())),
        _statsService = StatsService(UtilsService(ApiConfig()));

  // دالة مساعدة لتغليف الطلبات وحمايتها من انتهاء الاشتراك
  Future<T> _safeRequest<T>(Future<T> Function() apiCall) async {
    try {
      return await apiCall();
    } on NoValidSubscriptionException {
      // تسجيل الخروج فورًا
      await logout();
      rethrow; // ليتعامل الـ UI مع الحالة (مثل إظهار شاشة تسجيل الدخول)
    } catch (e) {
      rethrow;
    }
  }

  // Authentication
  Future<Map<String, dynamic>> loginWithGoogle({
    required String firebaseToken,
    required Map<String, String> googleUser,
    String language = 'en',
  }) async {
    return await _authService.loginWithGoogle(
      firebaseToken: firebaseToken,
      googleUser: googleUser,
      language: language,
    );
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String language = 'en',
    String? firebaseUid,
    String? firebaseToken,
  }) async {
    return await _authService.register(
      name,
      email,
      password,
      language: language,
      firebaseUid: firebaseUid,
      firebaseToken: firebaseToken,
    );
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String language = 'en'}) async {
    return await _authService.login(email, password, language: language);
  }

  Future<Map<String, dynamic>> loginWithFirebase({
    required String firebaseToken,
    String language = 'en',
  }) async {
    return await _authService.loginWithFirebase(
        firebaseToken: firebaseToken, language: language);
  }

  Future<void> logout() async {
    await _authService.logout();
    // مسح user_id من SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    return await _authService.verifyEmail(email, code);
  }

  Future<void> resendVerificationCode(String email) async {
    await _authService.resendVerificationCode(email);
  }

  // Token Management
  Future<bool> checkTokenValidity() async {
    return await _safeRequest(() => _apiConfig.checkTokenValidity());
  }

  Future<String?> getToken() async {
    return await _apiConfig.getToken();
  }

  // Subscription
  Future<Map<String, dynamic>> checkSubscription() async {
    return await _safeRequest(() => _subscriptionService.checkSubscription());
  }

  Future<String> getCustomerPortalUrl() async {
    return await _safeRequest(() => _subscriptionService.getCustomerPortalUrl());
  }

  Future<void> cancelSubscription() async {
    await _safeRequest(() => _subscriptionService.cancelSubscription());
  }

  Future<Map<String, dynamic>> resumeSubscription() async {
    return await _safeRequest(() => _subscriptionService.resumeSubscription());
  }

  Future<void> changeOffer(String variantId) async {
    await _safeRequest(() => _subscriptionService.changeOffer(variantId));
  }

  Future<String> buySubscription(String subscriptionId) async {
    return await _safeRequest(() => _subscriptionService.buySubscription(subscriptionId));
  }

  // Reminders
  Future<List<int>> getRemindersIds() async {
    return await _safeRequest(() => _reminderService.getRemindersIds());
  }

  Future<RemindersResponse> fetchReminders({
    int page = 1,
    int perPage = 10,
    String searchQuery = '',
    String? category,
    String? complexity,
    String? domain,
    bool forceFetch = false,
    List<int> excludeIds = const [],
  }) async {
    return await _safeRequest(() => _reminderService.fetchReminders(
          page: page,
          perPage: perPage,
          searchQuery: searchQuery,
          category: category,
          complexity: complexity,
          domain: domain,
          forceFetch: forceFetch,
          excludeIds: excludeIds,
        ));
  }

  Future<void> deleteReminder(int id) async {
    await _safeRequest(() => _reminderService.deleteReminder(id));
  }

  Future<Reminder> getReminder(String postUrl) async {
    return await _safeRequest(() => _reminderService.getReminder(postUrl));
  }

  Future<Reminder> getReminderById(int postId) async {
    return await _safeRequest(() => _reminderService.getReminderById(postId));
  }

  Future<Map<String, dynamic>> reschedulePost(
      String postUrl, String importance) async {
    return await _safeRequest(
        () => _reminderService.reschedulePost(postUrl, importance));
  }

  Future<Map<String, dynamic>> updateReminder(Reminder reminder) async {
    return await _safeRequest(() => _reminderService.updateReminder(reminder));
  }

  Future<Map<String, dynamic>> savePost(Map<String, dynamic> data) async {
    return await _safeRequest(() => _reminderService.savePost(data));
  }

  // User
  Future<Map<String, dynamic>> getUser() async {
    return await _safeRequest(() => _userService.getUser());
  }

  Future<User> getCurrentUser() async {
    return await _safeRequest(() => _userService.getCurrentUser());
  }

  Future<Map<String, dynamic>> updateLanguage(String language) async {
    return await _safeRequest(() => _userService.updateLanguage(language));
  }

  Future<UserFreeTime> createFreeTime(
      String day, TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    return await _safeRequest(() =>
        _userService.createFreeTime(day, startTime, endTime, isOffDay));
  }

  Future<Map<String, dynamic>> updateFreeTime(int id, String day,
      TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    return await _safeRequest(() => _userService.updateFreeTime(
        id, day, startTime, endTime, isOffDay));
  }

  Future<List<UserFreeTime>> fetchFreeTimes() async {
    return await _safeRequest(() => _userService.fetchFreeTimes());
  }

  Future<void> deleteFreeTime(int id) async {
    await _safeRequest(() => _userService.deleteFreeTime(id));
  }

  Future<void> updateUserProfile(Map<String, dynamic> data,
      {dynamic image}) async {
    await _safeRequest(() => _userService.updateUserProfile(data, image: image));
  }

  // Stats
  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    return await _safeRequest(() => _statsService.getSavedPostStatistics());
  }

  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    return await _safeRequest(() => _statsService.getOpenedStatsAnalysis());
  }

  Future<void> updateStats(String postUrl, bool opened) async {
    await _safeRequest(() => _statsService.updateStats(postUrl, opened));
  }

  Future<Map<String, dynamic>> getStats(String userId, String period) async {
    return await _safeRequest(() => _statsService.getStats(userId, period));
  }

  Future<Map<String, dynamic>> fetchRemindersData(
      String userId, String period) async {
    return await _safeRequest(
        () => _statsService.fetchRemindersData(userId, period));
  }

  Future<List<Map<String, dynamic>>> fetchCategoryStats(int userId) async {
    return await _safeRequest(() => _statsService.fetchCategoryStats(userId));
  }

  // Utilities
  Future<Map<String, dynamic>> request(String method, String endpoint,
      {Map<String, dynamic>? data}) async {
    return await _safeRequest(
        () => _utilsService.request(method, endpoint, data: data));
  }

  Future<DateTime> getServerTime() async {
    return await _safeRequest(() => _utilsService.getServerTime());
  }

  Future<Map<String, dynamic>> getApiConfig() async {
    return await _safeRequest(() => _utilsService.getApiConfig());
  }

  Future<Map<String, dynamic>> getApiCredentials() async {
    return await _safeRequest(() => _utilsService.getApiCredentials());
  }

  Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }
}