import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/consts.dart';
import 'api_config.dart';

class AuthService {
  final ApiConfig _apiConfig;

  AuthService(this._apiConfig);
  static void _safeShowMessage(String message) {
    // if (kDebugMode) {
    //   debugPrint('SplashScreen Message: $message');
    // }
    // try {
    //   if (navigatorKey.currentContext != null) {
    //     ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
    //       SnackBar(
    //         content: Text(message),
    //         backgroundColor: color ?? Colors.red,
    //         duration: const Duration(seconds: 3),
    //       ),
    //     );
    //   } else {
    //     debugPrint('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    //   }
    // } catch (e) {
    //   debugPrint('خطأ في عرض الرسالة: $e');
    // }
  }

 // في AuthService
Future<Map<String, dynamic>> loginWithGoogle({
  required String firebaseToken,
  required Map<String, String> googleUser, // تغيير من dynamic إلى String
  String language = 'en',
}) async {
  try {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/auth/google');

    final requestBody = {
      'id_token': firebaseToken,
      'language': language,
      'google_user': googleUser,
    };

    print('Request URL: $url');
    print('Request Body: $requestBody');

    final response = await http
        .post(
          url,
          headers: {
            'X-API-Password': AppConstants.API_PASSWORD,
            'Content-Type': 'application/json', // تغيير إلى JSON
          },
          body: jsonEncode(requestBody), // استخدام JSON encoding
        )
        .timeout(const Duration(seconds: 30));

    print('=== Google Sign-In API Response ===');
    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    Map<String, dynamic> responseData;
    try {
      responseData = json.decode(response.body);
    } catch (e) {
      print('JSON Decode Error: $e');
      return {
        'success': false,
        'statusCode': response.statusCode,
        'error': 'Invalid JSON response from server',
        'raw_response': response.body,
      };
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      // تحسين معالجة الاستجابة بناءً على رد السيرفر
      return {
        'success': responseData['success'] ?? true,
        'status': responseData['status'] ?? 'success',
        'data': responseData['data'] ?? responseData,
        'activated': responseData['activated'] ?? responseData['data']?['activated'] ?? true,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': responseData['message'] ?? 'Google Sign-In failed',
        'error': responseData['error'] ?? 'Unknown error',
      };
    }
  } catch (e) {
    print('Google Sign-In API Exception: $e');
    return {
      'success': false,
      'error': 'Network error during Google Sign-In: ${e.toString()}',
    };
  }
}
  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String language = 'en',
    String? firebaseUid,
    String? firebaseToken,
  }) async {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/register');
    final body = {
      'name': name,
      'email': email,
      'password': password,
      'language': language,
    };

    if (firebaseUid != null) body['firebase_uid'] = firebaseUid;
    if (firebaseToken != null) body['firebase_token'] = firebaseToken;

    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    final responseData = json.decode(response.body);
    print('Register Response: $responseData');

    if (response.statusCode == 201) {
      return {
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Registration failed.',
      };
    }
  }

  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String language = 'en',
  }) async {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/login');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'email': email,
        'password': password,
        'device_name': 'mobile_app',
      },
    );

    final responseData = json.decode(response.body);
    print('Login Response: $responseData');

    if (response.statusCode == 200) {
      return {
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Login failed.',
      };
    }
  }

  Future<Map<String, dynamic>> loginWithFirebase({
    required String firebaseToken,
    String language = 'en',
  }) async {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/auth/firebase/login');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'firebase_token': firebaseToken,
        'language': language,
      },
    );

    final responseData = json.decode(response.body);
    print('Firebase Login Response: $responseData');

    if (response.statusCode == 200) {
      return {
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Firebase login failed.',
      };
    }
  }

  Future<Map<String, dynamic>> googleSignIn({
    required String idToken,
    String language = 'en',
  }) async {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/auth/google');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': language,
      },
      body: jsonEncode({'id_token': idToken}),
    );

    final responseData = json.decode(response.body);
    _safeShowMessage('Google Sign-In Response: $responseData');

    if (response.statusCode == 200) {
      return {
        'success': true,
        'statusCode': response.statusCode,
        'data': responseData,
      };
    } else {
      return {
        'success': false,
        'statusCode': response.statusCode,
        'data': responseData,
        'error': responseData['message'] ??
            responseData['errors']?.toString() ??
            'Google Sign-In failed.',
      };
    }
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final url = Uri.parse('${AppConstants.API_BASE_URL}/verify-email');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'code': code}),
    );

    final responseData = json.decode(response.body);
    print('Verify Email Response: $responseData');

    if (response.statusCode == 200) {
      return {'success': true, 'data': responseData};
    } else {
      return {
        'success': false,
        'error': responseData['message'] ?? 'Verification failed.'
      };
    }
  }

  Future<Map<String, dynamic>> resendVerificationCode(String email) async {
    final token = await _apiConfig.getToken();
    final url = Uri.parse('${AppConstants.API_BASE_URL}/resend-verification');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );

    final responseData = json.decode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': responseData};
    } else {
      return {
        'success': false,
        'error': responseData['message'] ?? 'Failed to resend code.'
      };
    }
  }

  Future<Map<String, dynamic>> logout() async {
    final token = await _apiConfig.getToken();
    final url = Uri.parse('${AppConstants.API_BASE_URL}/logout');
    final response = await http.post(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return {'success': true};
    } else {
      return {'success': false, 'error': 'Logout failed on server'};
    }
  }

  Future<bool> checkTokenValidity() async {
    final token = await _apiConfig.getToken();
    if (token == null || token.isEmpty) return false;

    final url = Uri.parse('${AppConstants.API_BASE_URL}/check-token');
    final response = await http.get(
      url,
      headers: {
        'X-API-Password': AppConstants.API_PASSWORD,
        'Authorization': 'Bearer $token',
      },
    );

    return response.statusCode == 200;
  }
}
