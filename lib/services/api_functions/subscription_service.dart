
// lib/services/api_functions/user_service.dart

import 'package:flex_reminder/models/user.dart';
import 'package:flex_reminder/models/user_free_time.dart';
import 'utils_service.dart'; // استيراد UtilsService
import 'exceptions.dart'; // للاطلاق الاستثناء
import 'dart:convert';
import 'dart:io' as io; // لمعالجة الملفات في Mobile/Desktop
import 'package:flutter/foundation.dart' show kIsWeb; // للتحقق إذا كان التطبيق يعمل على الويب
import 'package:http/http.dart' as http; // لطلبات HTTP
import 'package:flutter/material.dart'; // لـ TimeOfDay (إذا احتجته لاحقاً)
import '../../utils/consts.dart';
import 'dart:io'; // For File type

class UserService {
  final UtilsService _utilsService;

  UserService(this._utilsService);

  Future<Map<String, dynamic>> getUser() async {
    final response = await _utilsService.request('GET', 'user');

    if (response['statusCode'] == 200) {
      return response['data'];
    } else {
      throw Exception('Failed to load user data');
    }
  }

  Future<User> getCurrentUser() async {
    final response = await _utilsService.request('GET', 'user');

    if (response['statusCode'] == 200) {
      return User.fromJson(response['data']);
    } else {
      throw Exception(response['data']['error'] ?? 'Failed to fetch user.');
    }
  }

  Future<Map<String, dynamic>> updateLanguage(String language) async {
    final response = await _utilsService.request('POST', 'update-language', data: {
      'language': language,
    });

    if (response['statusCode'] == 200) {
      return {'success': true, 'message': response['data']['message']};
    } else {
      throw Exception(response['data']['message'] ?? 'Failed to update language.');
    }
  }

  Future<UserFreeTime> createFreeTime(String day, TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    final response = await _utilsService.request('POST', 'free-times/store', data: {
      'day': day,
      'start_time': formatTimeOfDay(startTime),
      'end_time': formatTimeOfDay(endTime),
      'is_off_day': isOffDay ? 1 : 0,
    });

    if (response['statusCode'] == 201) {
      return UserFreeTime.fromJson(response['data']);
    } else {
      throw Exception(response['data']['message'] ?? 'Failed to create free time');
    }
  }

  Future<Map<String, dynamic>> updateFreeTime(int id, String day, TimeOfDay startTime, TimeOfDay endTime, bool isOffDay) async {
    final response = await _utilsService.request('PUT', 'free-times/$id', data: {
      'day': day,
      'start_time': formatTimeOfDay(startTime),
      'end_time': formatTimeOfDay(endTime),
      'is_off_day': isOffDay ? 1 : 0,
    });

    if (response['statusCode'] == 200) {
      return {'success': true};
    } else {
      return {
        'success': false,
        'message': response['data']['message'] ?? 'Failed to update free time.'
      };
    }
  }

  Future<List<UserFreeTime>> fetchFreeTimes() async {
    final response = await _utilsService.request('GET', 'free-times');

    if (response['statusCode'] == 200) {
      final List<dynamic> data = response['data'];
      return data.map((item) => UserFreeTime.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load free times: ${response['statusCode']}');
    }
  }

  Future<void> deleteFreeTime(int id) async {
    final response = await _utilsService.request('DELETE', 'free-times/$id');

    if (response['statusCode'] != 204) {
      throw Exception(response['data']['message'] ?? 'Failed to delete free time');
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> data, {dynamic image}) async {
    // ملاحظة: طلبات Multipart لا يمكن التعامل معها بواسطة UtilsService.request الحالية
    // لذا سنترك هذا الجزء كما هو أو نحتاج لتعديل UtilsService لدعم Multipart
    // حاليًا، سنترك الكود الأصلي لهذه الدالة
    
    final token = await _utilsService.apiConfig.getToken();
    if (token == null) throw Exception('No authentication token found');

    var request = http.MultipartRequest('POST', Uri.parse('${AppConstants.API_BASE_URL}/user/update'));
    request.headers['X-API-Password'] = AppConstants.API_PASSWORD;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    data.forEach((key, value) {
      request.fields[key] = value.toString();
    });

    // التعامل مع رفع الصورة (إذا كانت موجودة)
    if (image != null) {
      if (image is io.File) {
        request.files.add(
          await http.MultipartFile.fromPath('profile_image', image.path),
        );
      } else if (kIsWeb && image is File) {
        // للويب، قد تحتاج لمعالجة مختلفة
        // هذا الجزء يعتمد على كيفية تعاملك مع الملفات في الويب
      }
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    final responseData = json.decode(responseBody) as Map<String, dynamic>?;
    // التحقق من خطأ انتهاء الاشتراك
    if (responseData != null &&
        responseData['success'] == false &&
        responseData['message'] == 'no_valid_subscription') {
      await _utilsService.handleNoValidSubscription();
      throw NoValidSubscriptionException('لا يوجد اشتراك صالح');
    }

    if (response.statusCode != 200) {
      throw Exception(responseData?['message'] ?? 'Failed to update profile');
    }
  }

  String formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}