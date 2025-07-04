import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/user.dart';
import 'package:flex_reminder/models/category_statistic.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class DeepSeekService {
  late String apiKey;
  late String apiUrl;
  late String model;
  final ApiService apiService;
  bool _isInitialized = false;
  Map<String, dynamic>? _cachedStats;
  String? _cachedUserId;
  String? _cachedPeriod;

  DeepSeekService({required this.apiService}) {
    _initializeService();
  }

  Future<void> _initializeService() async {
    if (_isInitialized) return;
    try {
      await _initializeApiCredentials();
      await fetchApiConfig();
      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize DeepSeekService: $e');
      rethrow;
    }
  }

  Future<void> _initializeApiCredentials() async {
    try {
      final credentials = await apiService.getApiCredentials();
      final Map<String, dynamic> credentialsMap =
          _convertToMapStringDynamic(credentials);
      print('Credentials Map: $credentialsMap');
      apiKey = credentialsMap['apiKey'] ?? '';
      if (apiKey.isEmpty) throw Exception('API Key is missing or empty');
    } catch (e) {
      print('Error fetching API credentials: $e');
      throw Exception('Failed to fetch API credentials: $e');
    }
  }

  Future<Map<String, dynamic>> fetchApiConfig() async {
    try {
      final response = await apiService.getApiConfig();
      final Map<String, dynamic> responseMap =
          _convertToMapStringDynamic(response);
      print('API Config Response Map: $responseMap');

      final fetchedApiUrl = responseMap['apiUrl'] as String?;
      final fetchedModel = responseMap['model'] as String?;
      final fetchedApiKey = responseMap['apiKey'] as String?;

      if (fetchedApiUrl == null || fetchedApiUrl.isEmpty) {
        throw Exception('API URL is missing or empty in the config');
      }
      if (fetchedModel == null || fetchedModel.isEmpty) {
        throw Exception('Model is missing or empty in the config');
      }
      if (fetchedApiKey == null || fetchedApiKey.isEmpty) {
        throw Exception('API Key is missing or empty in the config');
      }

      apiUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/$fetchedModel:generateContent';
      model = fetchedModel;
      apiKey = fetchedApiKey;

      return {'apiUrl': apiUrl, 'model': model, 'apiKey': apiKey};
    } catch (e) {
      print('Error fetching API configuration: $e');
      throw Exception('Failed to fetch API configuration: $e');
    }
  }

  Future<Map<String, dynamic>> _getStats(String userId, String period) async {
    if (_cachedStats != null &&
        _cachedUserId == userId &&
        _cachedPeriod == period) {
      print('Returning cached stats for user $userId and period $period');
      return Map<String, dynamic>.from(_cachedStats!);
    }

    print('Fetching new stats from API for user $userId and period $period');
    final response = await apiService.getStats(userId, period);
    final Map<String, dynamic> responseMap =
        _convertToMapStringDynamic(response);

    final bool status = responseMap['status'] == 'success';
    final String message =
        responseMap['message'] as String? ?? 'No message provided';

    final updatedResponseMap = {
      'status': status,
      'message': message,
      'data': responseMap['data'] ?? [],
    };

    _cachedStats = updatedResponseMap;
    _cachedUserId = userId;
    _cachedPeriod = period;

    return Map<String, dynamic>.from(_cachedStats!);
  }

  Map<String, dynamic> _convertToMapStringDynamic(dynamic data) {
    if (data is Map) {
      return data.map((key, value) {
        final String newKey = key.toString();
        final dynamic newValue = value is Map
            ? _convertToMapStringDynamic(value)
            : (value is List
                ? value
                    .map((item) =>
                        item is Map ? _convertToMapStringDynamic(item) : item)
                    .toList()
                : value);
        return MapEntry(newKey, newValue);
      });
    }
    return {};
  }

  Future<Map<String, dynamic>> analyzeRecentEngagementTimes(
    User user,
    String userLocale,
    BuildContext context,
  ) async {
    await _initializeService();
    try {
      final responseMap = await _getStats(user.id.toString(), 'week');

      print("--- Cached/Fetched Response ---");
      print("Response Content: $responseMap");
      print("--- End Response ---");

      final status = responseMap['status'];
      final String message =
          responseMap['message'] as String? ?? 'No message provided';

      if (status != true) {
        return {
          'post_opening_trend': [],
          'recommendations': message.isNotEmpty
              ? message
              : (userLocale == 'ar'
                  ? 'لا توجد إحصائيات متاحة'
                  : 'No statistics available'),
          'raw_old_data': [],
          'no_data': true,
        };
      }

      final now = DateTime.now();
      final postOpeningTrend = <Map<String, dynamic>>[];

      final List<int> simulatedOpenings = [2, 3, 1, 4, 0, 5, 2];
      for (int i = 0; i < 7; i++) {
        final day = now.subtract(Duration(days: 6 - i));
        postOpeningTrend.add({
          'day': day.weekdayName,
          'openings': simulatedOpenings[i],
        });
      }

      return {
        'post_opening_trend': postOpeningTrend,
        'recommendations': 'No analysis performed (direct from backend)',
        'raw_old_data': [],
        'no_data': false,
      };
    } catch (e) {
      print("Error in analyzeRecentEngagementTimes: $e");
      final localizations = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userLocale == 'ar'
              ? 'حدث خطأ أثناء تحليل تطور فتح المنشورات'
              : 'An error occurred while analyzing post opening trends'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return {
        'post_opening_trend': [],
        'recommendations': userLocale == 'ar'
            ? 'حدث خطأ أثناء تحليل تطور فتح المنشورات: $e'
            : 'An error occurred while analyzing post opening trends: $e',
        'raw_old_data': [],
      };
    }
  }

  Future<Map<String, dynamic>> analyzeRecentUserStats(
    User user,
    String userLocale,
  ) async {
    await _initializeService();
    try {
      final responseMap = await _getStats(user.id.toString(), 'week');

      final status = responseMap['status'];
      if (status != true) {
        return {
          'total_reminders': 0,
          'opened_reminders': 0,
          'unopened_reminders': 0,
          'raw_old_reminders': [],
        };
      }

      final List<dynamic> data = responseMap['data'] ?? [];
      final totalReminders = data.length;
      final openedReminders = 0;
      final unopenedReminders = totalReminders - openedReminders;
      final rawOldReminders = <Map<String, dynamic>>[];

      return {
        'total_reminders': totalReminders,
        'opened_reminders': openedReminders,
        'unopened_reminders': unopenedReminders,
        'raw_old_reminders': rawOldReminders,
      };
    } catch (e) {
      print("Error in analyzeRecentUserStats: $e");
      return {
        'total_reminders': 0,
        'opened_reminders': 0,
        'unopened_reminders': 0,
        'raw_old_reminders': [],
      };
    }
  }

  Future<Map<String, dynamic>> analyzeRecentCategoryDistribution(
    User user,
    String userLocale,
  ) async {
    await _initializeService();
    try {
      final responseMap = await _getStats(user.id.toString(), 'week');

      final status = responseMap['status'];
      if (status != true) {
        return {
          'categories': {},
          'complexities': {},
          'raw_old_reminders': [],
        };
      }

      final List<dynamic> data = responseMap['data'] ?? [];
      final categories = <String, int>{};
      final complexities = <String, int>{};
      final rawOldReminders = <Map<String, dynamic>>[];

      for (var item in data) {
        final Map<String, dynamic> statItem = item as Map<String, dynamic>;
        final category = statItem['category'] as String? ?? 'Uncategorized';
        final complexity = statItem['complexity'] as String? ?? 'Unknown';

        categories[category] = (categories[category] ?? 0) + 1;
        complexities[complexity] = (complexities[complexity] ?? 0) + 1;
      }

      return {
        'categories': categories,
        'complexities': complexities,
        'raw_old_reminders': rawOldReminders,
      };
    } catch (e) {
      print("Error in analyzeRecentCategoryDistribution: $e");
      return {
        'categories': {},
        'complexities': {},
        'raw_old_reminders': [],
      };
    }
  }

  Future<Map<String, dynamic>> generateRecentRecommendations(
    User user,
    String userLocale,
  ) async {
    await _initializeService();
    try {
      final responseMap = await _getStats(user.id.toString(), 'week');

      final status = responseMap['status'];
      if (status != true) {
        return {
          'general_recommendations': userLocale == 'ar'
              ? 'لا توجد توصيات متاحة'
              : 'No recommendations available',
          'optimal_times': {},
          'raw_old_data': [],
        };
      }

      final CategoryStatistic stat = CategoryStatistic.fromJson(responseMap);
      final optimalTimes = <String, List<String>>{};
      final rawOldData = <Map<String, dynamic>>[];

      final preferredTimes = stat.preferredTimes ?? [];
      for (var timePeriod in preferredTimes) {
        String representativeTime;
        if (timePeriod.toLowerCase() == 'morning') {
          representativeTime = '08:00';
        } else {
          continue;
        }

        for (int i = 1; i <= 7; i++) {
          final day = DateTime.now().subtract(Duration(days: 7 - i));
          final dayName = day.weekdayName.toLowerCase();
          optimalTimes.putIfAbsent(dayName, () => []).add(representativeTime);
        }
      }

      return {
        'general_recommendations': userLocale == 'ar'
            ? 'حاول التفاعل في الأوقات المثلى'
            : 'Try engaging during optimal times',
        'optimal_times': optimalTimes,
        'raw_old_data': rawOldData,
      };
    } catch (e) {
      print("Error in generateRecentRecommendations: $e");
      return {
        'general_recommendations': userLocale == 'ar'
            ? 'حدث خطأ أثناء إنشاء التوصيات: $e'
            : 'Error generating recommendations: $e',
        'optimal_times': {},
        'raw_old_data': [],
      };
    }
  }

  void clearCache() {
    _cachedStats = null;
    _cachedUserId = null;
    _cachedPeriod = null;
    print('Cache cleared');
  }
}

extension DateTimeExtension on DateTime {
  String get weekdayName {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }
}
