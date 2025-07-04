import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class UtilsService {
  final ApiConfig _apiConfig;

  UtilsService(this._apiConfig);

  Future<Map<String, dynamic>> request(String method, String endpoint,
      {Map<String, dynamic>? data}) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final uri = Uri.parse('${ApiConfig.API_BASE_URL}/$endpoint');
    http.Response response;

    if (method == 'POST') {
      response = await http.post(
        uri,
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
    } else {
      response = await http.get(
        uri,
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
        },
      );
    }

    print('Request ($method $endpoint) Response: ${response.body}');

    return {
      'statusCode': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  Future<DateTime> getServerTime() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.API_BASE_URL}/server-time'),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Accept': 'application/json',
        },
      );

      print('Server Time Response: ${response.body}');
      print(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['server_time'] != null) {
          final serverDate = DateTime.parse(data['server_time']);
          await _apiConfig.storage.write(
              key: 'last_server_time', value: serverDate.toIso8601String());
          return serverDate;
        } else {
          throw Exception('Failed to fetch time: Invalid response');
        }
      } else {
        throw Exception('Failed to fetch server time: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching server time: $e');
      final lastServerTimeStr =
          await _apiConfig.storage.read(key: 'last_server_time');
      if (lastServerTimeStr != null) {
        print('Using last stored time: $lastServerTimeStr');
        return DateTime.parse(lastServerTimeStr);
      }
      print('No stored time, falling back to local time');
      return DateTime.now();
    }
  }

  Future<Map<String, dynamic>> getApiConfig() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.API_BASE_URL}/api-credentials'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );
    print('API Config Response: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch API config: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getApiCredentials() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.API_BASE_URL}/api-credentials'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );
    print('Get API Credentials Response: ${response.body}');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch API credentials');
  }

  // Removed getCurrentUserId as it's now in ApiConfig
}
