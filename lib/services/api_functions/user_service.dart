import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flex_reminder/models/user.dart';
import 'package:flex_reminder/models/user_free_time.dart';
import 'api_config.dart';
import 'dart:io' as io show File if (dart.library.html) 'dart:html' show File;
import 'package:flutter/foundation.dart' show kIsWeb;

class UserService {
  final ApiConfig _apiConfig;

  UserService(this._apiConfig);

  Future<Map<String, dynamic>> getUser() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.API_BASE_URL}/user'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    print('Get User Response: ${response.body}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load user data');
    }
  }

  Future<User> getCurrentUser() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.API_BASE_URL}/user'),
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );
    print('Get Current User Response: ${response.body}');
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to fetch user.');
    }
  }

  Future<Map<String, dynamic>> updateLanguage(String language) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    print(language);
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/update-language');
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'language': language}),
    );

    print('Update Language Response: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return {'success': true, 'message': responseData['message']};
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to update language.');
    }
  }

  Future<UserFreeTime> createFreeTime(String day, TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/free-times/store');
    final token = await _apiConfig.getToken();
    print('Create Free Time Request: day=$day, isOffDay=$isOffDay');
    final String formattedStartTime = formatTimeOfDay(startTime);
    final String formattedEndTime = formatTimeOfDay(endTime);

    final response = await http.post(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'day': day,
        'start_time': formattedStartTime,
        'end_time': formattedEndTime,
        'is_off_day': isOffDay ? 1 : 0,
      }),
    );

    print('Create Free Time Response: ${response.body}');

    if (response.statusCode == 201) {
      return UserFreeTime.fromJson(json.decode(response.body));
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to create free time: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> updateFreeTime(int id, String day, TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/free-times/$id');
    final token = await _apiConfig.getToken();

    final String formattedStartTime = formatTimeOfDay(startTime);
    final String formattedEndTime = formatTimeOfDay(endTime);

    final response = await http.put(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'day': day,
        'start_time': formattedStartTime,
        'end_time': formattedEndTime,
        'is_off_day': isOffDay ? 1 : 0,
      }),
    );

    print('Update Free Time Response: ${response.body}');

    if (response.statusCode == 200) {
      return {'success': true};
    } else {
      final errorData = json.decode(response.body);
      return {
        'success': false,
        'message': errorData['message'] ?? 'Failed to update free time.'
      };
    }
  }

  Future<List<UserFreeTime>> fetchFreeTimes() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/free-times');
    final token = await _apiConfig.getToken();
    final response = await http.get(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    print('Fetch Free Times Response: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => UserFreeTime.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load free times: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> deleteFreeTime(int id) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = Uri.parse('${ApiConfig.API_BASE_URL}/free-times/$id');
    final token = await _apiConfig.getToken();
    final response = await http.delete(
      url,
      headers: {
        'X-API-Password': ApiConfig.API_PASSWORD,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    print('Delete Free Time Response: ${response.body}');

    if (response.statusCode != 204) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to delete free time: ${response.statusCode}');
    }
  }

  String formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> updateUserProfile(Map<String, dynamic> data, {dynamic image}) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final url = '${ApiConfig.API_BASE_URL}/user/update';
    final token = await _apiConfig.getToken();
    if (token == null) throw Exception('No authentication token found');

    var request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['X-API-Password'] = ApiConfig.API_PASSWORD;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    data.forEach((key, value) {
      request.fields[key] = value.toString();
    });

    if (!kIsWeb && image != null && image is io.File) {
      request.files.add(
        await http.MultipartFile.fromPath('profile_image', image.path),
      );
    } else if (kIsWeb && image != null) {
      throw UnimplementedError('Image upload on web is not implemented yet.');
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    print('Update User Profile Response: $responseBody');
    if (response.statusCode != 200) {
      final errorData = json.decode(responseBody) as Map<String, dynamic>?;
      throw Exception(errorData?['message'] ?? 'Failed to update profile');
    }
  }
}