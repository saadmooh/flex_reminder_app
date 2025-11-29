// lib/services/api_functions/stats_service.dart

import 'utils_service.dart'; // استيراد UtilsService
import 'exceptions.dart'; // للاطلاق الاستثناء

class StatsService {
  final UtilsService _utilsService;

  StatsService(this._utilsService);

  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    final response = await _utilsService.request('GET', 'statistics/saved-posts');

    if (response['statusCode'] == 200) {
      return {
        'statusCode': response['statusCode'],
        'data': response['data'],
      };
    } else {
      return {
        'statusCode': response['statusCode'],
        'error': response['data']['message'] ??
            'Failed to fetch saved post statistics',
      };
    }
  }

  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    final response = await _utilsService.request('GET', 'statistics/opened-stats');

    if (response['statusCode'] == 200) {
      return {
        'statusCode': response['statusCode'],
        'detailed_stats': response['data']['detailed_stats'],
        'graph_data': response['data']['graph_data'],
      };
    } else {
      return {
        'statusCode': response['statusCode'],
        'error': response['data']['message'] ??
            'Failed to fetch opened stats analysis',
      };
    }
  }

  Future<void> updateStats(String postUrl, bool opened) async {
    final response = await _utilsService.request('POST', 'update-stats', data: {
      'url': postUrl,
      'opened': opened,
    });

    // الطلب ناجح إذا كان الكود 200
    if (response['statusCode'] != 200) {
      throw Exception(response['data']['message'] ?? 'Failed to update stats.');
    }
    // لا حاجة لإرجاع قيمة في حالة النجاح
  }

  Future<Map<String, dynamic>> getStats(String userId, String period) async {
    final response = await _utilsService.request('GET', 'stats', data: {
      'user_id': userId,
      'period': period,
    });

    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data['data'] == null ||
          (data['data'] is List && data['data'].isEmpty)) {
        return {
          'status': 'error',
          'message': 'No category statistics found for this user.',
          'data': [],
        };
      }
      return data;
    } else {
      throw Exception(
          'Failed to fetch stats: ${response['statusCode']}');
    }
  }

  Future<Map<String, dynamic>> fetchRemindersData(
      String userId, String period) async {
    final response = await _utilsService.request('GET', 'remindersData', data: {
      'user_id': userId,
      'period': period,
    });
    
    if (response['statusCode'] == 200) {
      return response['data'];
    } else {
      throw Exception('Failed to fetch reminders');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCategoryStats(int userId) async {
    final response = await _utilsService.request('GET', 'category-stats', data: {
      'user_id': userId.toString(),
    });

    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Invalid response format for category stats');
      }
    } else if (response['statusCode'] == 401) {
      throw Exception('Unauthorized');
    } else {
      throw Exception('Failed to load category stats: ${response['statusCode']}');
    }
  }
}