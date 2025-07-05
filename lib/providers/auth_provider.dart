import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  int? _userId;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get userId => _userId;

  AuthProvider() {
    initializeAuthentication();
  }

  Future<void> initializeAuthentication() async {
    print('_isAuthenticated:$_isAuthenticated');
    try {
      _isLoading = true;
      notifyListeners();

      final token = await _storage.read(key: 'auth_token');
      print(token);
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt('user_id');
      //print(_userId);

      if (token != null && token.isNotEmpty) {
        final isValid = await _apiService.checkTokenValidity();
        print(isValid);
        _isAuthenticated = isValid;
        print('_isAuthenticated:$_isAuthenticated');
        if (!isValid) {
          await logout();
        }
      } else {
        _isAuthenticated = false;
      }
    } catch (e) {
      _errorMessage = 'Failed to initialize authentication: $e';
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String language = 'en',
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response =
          await _apiService.register(name, email, password, language: language);
      if (response['statusCode'] == 201) {
        _userId = response['data']['user_id'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', _userId!);
        _isAuthenticated = false; // يتطلب تفعيل البريد الإلكتروني
      } else {
        _errorMessage = response['data']['message'] ??
            response['data']['errors']?.join('\n') ??
            'Registration failed';
        throw Exception(_errorMessage);
      }
    } catch (e) {
      _errorMessage = e.toString();
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    String language = 'en',
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response =
          await _apiService.login(email, password, language: language);
      if (response['statusCode'] == 200 &&
          response['data']['access_token'] != null) {
        final token = response['data']['access_token'];
        _userId = response['data']['user_id'];
        await setToken(token);
        _isAuthenticated = true;
        await FcmService().sendFcmTokenToBackend();
      } else {
        _errorMessage = response['data']['message'] ??
            response['data']['errors']?.join('\n') ??
            'Login failed';
        throw Exception(_errorMessage);
      }
    } catch (e) {
      _errorMessage = e.toString();
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _apiService.logout();
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'last_check_result');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      _isAuthenticated = false;
      _userId = null;
    } catch (e) {
      _errorMessage = 'Failed to logout: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> verifyEmail(String email, String code) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _apiService.verifyEmail(email, code);
    } catch (e) {
      _errorMessage = 'Failed to verify email: $e';
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resendVerificationCode(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _apiService.resendVerificationCode(email);
    } catch (e) {
      _errorMessage = 'Failed to resend verification code: $e';
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setToken(String token) async {
    try {
      await _storage.write(key: 'auth_token', value: token);
      await _storage.write(key: 'last_check_result', value: '/reminders');
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to store token: $e';
      throw e;
    }
    print(await _storage.read(key: 'auth_token'));
  }

  Future<bool> checkTokenValidity() async {
    try {
      return await _apiService.checkTokenValidity();
    } catch (e) {
      _errorMessage = 'Failed to check token validity: $e';
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> checkSubscription() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final response = await _apiService.checkSubscription();
      return response;
    } catch (e) {
      _errorMessage = 'Failed to check subscription: $e';
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
