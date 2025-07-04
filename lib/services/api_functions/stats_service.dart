import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class StatsService {
  final ApiConfig _apiConfig;

  StatsService(this._apiConfig);

  Future<Map<String, dynamic>> getSavedPostStatistics() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/statistics/saved-posts');
    final token = await _apiConfig.getToken();

    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final responseData = json.decode(response.body);
      print('Saved Post Statistics: $responseData');
      if (response.statusCode == 200) {
        return {
          'statusCode': response.statusCode,
          'data': responseData,
        };
      } else {
        return {
          'statusCode': response.statusCode,
          'error': responseData['message'] ??
              'Failed to fetch saved post statistics',
        };
      }
    } catch (e) {
      return {
        'statusCode': 500,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> getOpenedStatsAnalysis() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/statistics/opened-stats');
    final token = await _apiConfig.getToken();

    try {
      final response = await http.get(
        url,
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final responseData = json.decode(response.body);
      print('Opened Stats Analysis: $responseData');
      if (response.statusCode == 200) {
        return {
          'statusCode': response.statusCode,
          'detailed_stats': responseData['detailed_stats'],
          'graph_data': responseData['graph_data'],
        };
      } else {
        return {
          'statusCode': response.statusCode,
          'error': responseData['message'] ??
              'Failed to fetch opened stats analysis',
        };
      }
    } catch (e) {
      return {
        'statusCode': 500,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<void> updateStats(String postUrl, bool opened) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/update-stats');
    final token = await _apiConfig.getToken();
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'url': postUrl,
        'opened': opened,
      }),
    );

    print('Update Stats Response: ${response.body}');

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to update stats.');
    }
  }

  Future<Map<String, dynamic>> getStats(String userId, String period) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse(
          '${ApiConfig.API_BASE_URL}/stats?user_id=$userId&period=$period'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );
    print('Get Stats Response: ${response.body}');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['data'] == null ||
          (decoded['data'] is List && decoded['data'].isEmpty)) {
        return {
          'status': 'error',
          'message': 'No category statistics found for this user.',
          'data': [],
        };
      }
      return decoded;
    }
    throw Exception(
        'Failed to fetch stats: ${response.statusCode} - ${response.body}');
  }

  Future<Map<String, dynamic>> fetchRemindersData(
      String userId, String period) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse(
          '${ApiConfig.API_BASE_URL}/remindersData?user_id=$userId&period=$period'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );
    print('Fetch Reminders Data Response: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch reminders');
  }

  Future<List<Map<String, dynamic>>> fetchCategoryStats(int userId) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.API_BASE_URL}/category-stats?user_id=$userId'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    print('Fetch Category Stats Response: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    } else {
      throw Exception('Failed to load category stats: ${response.statusCode}');
    }
  }
}
