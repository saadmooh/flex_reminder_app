import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  int? _userId;
  bool _isOfflineMode = false;
  bool _isInitializing = false;
  bool _isInitialized = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get userId => _userId;
  bool get isOfflineMode => _isOfflineMode;
  bool get isInitializing => _isInitializing;
  bool get isInitialized => _isInitialized;

  AuthProvider() {
    initializeAuthentication();
  }

  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      debugPrint('FCM Message: $message');
    }
    try {
      if (navigatorKey.currentContext != null) {
        final scaffoldMessenger = ScaffoldMessenger.of(navigatorKey.currentContext!);
        if (scaffoldMessenger.mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: color ?? Colors.blue,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        } else {
          debugPrint('ScaffoldMessenger غير متاح، تم تجاهل SnackBar: $message');
        }
      } else {
        debugPrint('التطبيق غير نشط، تم تجاهل SnackBar: $message');
      }
    } catch (e) {
      debugPrint('خطأ في عرض الرسالة: $e');
    }
  }

  Future<void> initializeAuthentication() async {
    if (_isInitializing) {
      _safeShowMessage('⏳ Authentication already initializing, waiting...');
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;
    _isInitialized = false;
    notifyListeners();

    try {
      _safeShowMessage('🔄 Starting authentication initialization...');

      final token = await getToken();
      _safeShowMessage('🔍 Token found: ${token != null && token.isNotEmpty}');

      if (token != null && token.isNotEmpty) {
        _safeShowMessage('📡 Checking token validity...');
        final hasInternet = await ConnectivityHelper.checkInternetConnection(verbose: true);
        if (hasInternet) {
          try {
            final isValid = await _apiService.checkTokenValidity();
            _isAuthenticated = isValid;
            _isOfflineMode = false;
            if (isValid) {
              _safeShowMessage('✅ Token is valid online');
              _userId = await getUserId();
            } else {
              _safeShowMessage('❌ Token invalid, logging out...');
              await logout();
            }
          } catch (e) {
            _safeShowMessage('🌐 Network error, falling back to offline mode: $e');
            await _handleOfflineAuthentication(token);
          }
        } else {
          _safeShowMessage('📴 No internet, proceeding in offline mode');
          await _handleOfflineAuthentication(token);
        }
      } else {
        _safeShowMessage('❌ No token found');
        _isAuthenticated = false;
        _isOfflineMode = false;
      }
    } catch (e) {
      _safeShowMessage('❌ Critical error in initializeAuthentication: $e');
      _isAuthenticated = false;
      _isOfflineMode = false;
    } finally {
      _isInitializing = false;
      _isInitialized = true;
      notifyListeners();
      _safeShowMessage('✅ Authentication initialization completed');
    }
  }

  Future<void> initializeOfflineMode() async {
    if (_isInitializing) {
      _safeShowMessage('⏳ Already initializing, waiting for completion...');
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;
    try {
      _safeShowMessage('🔄 Initializing offline mode...');
      final token = await getToken();
      _safeShowMessage('🔍 Token retrieved: ${token != null ? 'Found (${token.length} chars)' : 'NULL'}');
      if (token != null && token.isNotEmpty) {
        await _handleOfflineAuthentication(token);
        _safeShowMessage('✅ Offline mode initialized with authentication');
      }
    } catch (e) {
      _safeShowMessage('❌ Error in initializeOfflineMode: $e');
      _isAuthenticated = false;
      _isOfflineMode = true;
    } finally {
      _isLoading = false;
      _isInitializing = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> waitForInitialization() async {
    if (!_isInitialized && !_isInitializing) {
      await initializeAuthentication();
    }
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _handleOfflineAuthentication(String token) async {
    if (token.isNotEmpty) {
      _isAuthenticated = true;
      _isOfflineMode = true;
      _userId = await getUserId();
      _safeShowMessage('✅ Offline authentication accepted with token');
    } else {
      _isAuthenticated = false;
      _isOfflineMode = true;
      _safeShowMessage('❌ No token found for offline authentication');
    }
  }

  Future<void> setToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backup_auth_token', token);
  }

  Future<void> setUserId(int userId) async {
    await _storage.write(key: 'user_id', value: userId.toString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
    await prefs.setString('user_id_string', userId.toString());
    _userId = userId;
  }

  Future<String?> getToken() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        _safeShowMessage('✅ Token retrieved from SecureStorage');
        return token;
      }
      _safeShowMessage('⚠️ Token not found in SecureStorage, trying backup...');
    } catch (e) {
      _safeShowMessage('❌ SecureStorage read error: $e, trying backup...');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final backupToken = prefs.getString('backup_auth_token');
      if (backupToken != null && backupToken.isNotEmpty) {
        _safeShowMessage('✅ Token retrieved from SharedPreferences backup');
        return backupToken;
      }
      _safeShowMessage('❌ No backup token found in SharedPreferences');
    } catch (e) {
      _safeShowMessage('❌ SharedPreferences backup read error: $e');
    }

    _safeShowMessage('❌ Token not found in any storage method');
    return null;
  }

  Future<int?> getUserId() async {
    try {
      final idStr = await _storage.read(key: 'user_id');
      if (idStr != null) {
        final id = int.tryParse(idStr);
        if (id != null) {
          _safeShowMessage('✅ User ID retrieved from SecureStorage: $id');
          return id;
        }
      }
      _safeShowMessage('⚠️ User ID not found in SecureStorage, trying backup...');
    } catch (e) {
      _safeShowMessage('❌ SecureStorage read error for user_id: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId != null) {
        _safeShowMessage('✅ User ID retrieved from SharedPreferences: $userId');
        return userId;
      }
      _safeShowMessage('❌ No backup user ID found in SharedPreferences');
    } catch (e) {
      _safeShowMessage('❌ SharedPreferences read error for user_id: $e');
    }

    _safeShowMessage('❌ User ID not found in any storage method');
    return null;
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backup_auth_token');
    await prefs.remove('user_id');
    await prefs.remove('user_id_string');
    await prefs.remove('last_login_email');
    await prefs.remove('last_login_date');
    await prefs.remove('last_subscription_status');
  }

  Future<bool> hasStoredToken() async {
    try {
      final token = await getToken();
      final hasToken = token != null && token.isNotEmpty;
      _safeShowMessage('🎯 hasStoredToken result: $hasToken');
      return hasToken;
    } catch (e) {
      _safeShowMessage('❌ Error in hasStoredToken: $e');
      return false;
    }
  }

  Future<String?> getTokenWithDebug() async {
    _safeShowMessage('🔍 === TOKEN RETRIEVAL DEBUG ===');
    try {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        _safeShowMessage('✅ Token retrieved successfully');
        _safeShowMessage('📏 Token length: ${token.length}');
        _safeShowMessage('🔤 Token type: ${token.runtimeType}');
        _safeShowMessage('🎯 Token preview: ${token.length > 20 ? token.substring(0, 20) + '...' : token}');
      } else {
        _safeShowMessage('❌ No valid token found');
        await debugStorageState();
      }
      return token;
    } catch (e) {
      _safeShowMessage('❌ getTokenWithDebug error: $e');
      return null;
    } finally {
      _safeShowMessage('🔍 === TOKEN RETRIEVAL DEBUG END ===');
    }
  }

  void setAuthenticationStatus(bool isAuthenticated) {
    _isAuthenticated = isAuthenticated;
    _isLoading = false;
    notifyListeners();
    _safeShowMessage('Authentication status set to: $isAuthenticated');
  }

  Future<void> retryOnlineAuthentication() async {
    if (!_isOfflineMode) return;
    _safeShowMessage('🔄 Retrying online authentication...');
    await initializeAuthentication();
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

      final result = await _apiService.register(name, email, password, language: language);
      if (result['success']) {
        final userData = result['data']['user'];
        await setToken(userData['access_token']);
        await setUserId(userData['id']);
        _isAuthenticated = false;
        _isOfflineMode = false;
      } else {
        _errorMessage = result['data']['message'] ??
            result['data']['errors']?.join('\n') ??
            'Registration failed';
        throw Exception(_errorMessage);
      }
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
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

      final result = await _apiService.login(email, password, language: language);
      if (result['success']) {
        final userData = result['data'];
        await setToken(userData['access_token']);
        await setUserId(userData['user']['id']);
        _isAuthenticated = true;
        _isOfflineMode = false;
        await FcmService().sendFcmTokenToBackend();
      } else {
        _errorMessage = result['error'];
        throw Exception(_errorMessage);
      }
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      try {
        await _apiService.logout();
      } catch (e) {
        _safeShowMessage("Server logout failed (offline): $e");
      }
      await clearToken();
      _isAuthenticated = false;
      _isOfflineMode = false;
      _userId = null;
      _errorMessage = null;
      _safeShowMessage('تم تسجيل الخروج بنجاح');
    } catch (e) {
      _errorMessage = 'فشل في تسجيل الخروج: $e';
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
      _isOfflineMode = false;
    } catch (e) {
      _errorMessage = 'Failed to verify email: $e';
      rethrow;
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
      _isOfflineMode = false;
    } catch (e) {
      _errorMessage = 'Failed to resend verification code: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> debugStorageState() async {
    try {
      _safeShowMessage('🔧 ========== STORAGE DEBUG START ==========');
      _safeShowMessage('🔐 === FLUTTER SECURE STORAGE ===');
      try {
        final token = await getToken();
        if (token != null) {
          _safeShowMessage('✅ Auth Token: EXISTS');
          _safeShowMessage('📏 Token Length: ${token.length} characters');
          _safeShowMessage('🎯 Token Preview: ${token.length > 20 ? token.substring(0, 20) + '...' : token}');
          _safeShowMessage('🔤 Token Type: ${token.runtimeType}');
          _safeShowMessage('📝 Token isEmpty: ${token.isEmpty}');
        } else {
          _safeShowMessage('❌ Auth Token: NULL');
        }

        final lastCheckResult = await _storage.read(key: 'last_check_result');
        _safeShowMessage('🔍 Last Check Result: ${lastCheckResult ?? 'NULL'}');

        final userId = await getUserId();
        _safeShowMessage('👤 User ID: ${userId ?? 'NULL'}');
      } catch (secureError) {
        _safeShowMessage('❌ SecureStorage Error: $secureError');
      }

      _safeShowMessage('🗂️ === ALL SECURE STORAGE KEYS ===');
      try {
        final allSecureData = await _storage.readAll();
        if (allSecureData.isEmpty) {
          _safeShowMessage('📭 SecureStorage is EMPTY');
        } else {
          _safeShowMessage('📊 Total Keys: ${allSecureData.length}');
          allSecureData.forEach((key, value) {
            final preview = value.length > 30 ? value.substring(0, 30) + '...' : value;
            _safeShowMessage('🔑 $key: $preview (${value.length} chars)');
          });
        }
      } catch (allKeysError) {
        _safeShowMessage('❌ Cannot read all secure keys: $allKeysError');
      }

      _safeShowMessage('💾 === SHARED PREFERENCES ===');
      try {
        final prefs = await SharedPreferences.getInstance();
        final prefsUserId = prefs.getInt('user_id');
        _safeShowMessage('👤 Prefs User ID (int): ${prefsUserId ?? 'NULL'}');
        final prefsUserIdString = prefs.getString('user_id_string');
        _safeShowMessage('👤 Prefs User ID (string): ${prefsUserIdString ?? 'NULL'}');
        final backupToken = prefs.getString('backup_auth_token');
        if (backupToken != null) {
          _safeShowMessage('🔄 Backup Token: EXISTS (${backupToken.length} chars)');
          _safeShowMessage('🎯 Backup Preview: ${backupToken.length > 20 ? backupToken.substring(0, 20) + '...' : backupToken}');
        } else {
          _safeShowMessage('🔄 Backup Token: NULL');
        }
        final lastSubscriptionStatus = prefs.getBool('last_subscription_status');
        _safeShowMessage('📱 Last Subscription: ${lastSubscriptionStatus ?? 'NULL'}');
      } catch (prefsError) {
        _safeShowMessage('❌ SharedPreferences Error: $prefsError');
      }

      _safeShowMessage('📋 === ALL SHARED PREFERENCES KEYS ===');
      try {
        final prefs = await SharedPreferences.getInstance();
        final allPrefsKeys = prefs.getKeys();
        if (allPrefsKeys.isEmpty) {
          _safeShowMessage('📭 SharedPreferences is EMPTY');
        } else {
          _safeShowMessage('📊 Total Prefs Keys: ${allPrefsKeys.length}');
          for (String key in allPrefsKeys) {
            final value = prefs.get(key);
            _safeShowMessage('🔑 $key: $value (${value.runtimeType})');
          }
        }
      } catch (allPrefsError) {
        _safeShowMessage('❌ Cannot read all prefs keys: $allPrefsError');
      }

      _safeShowMessage('📊 === CURRENT STATE VARIABLES ===');
      _safeShowMessage('🔐 _isAuthenticated: $_isAuthenticated');
      _safeShowMessage('📴 _isOfflineMode: $_isOfflineMode');
      _safeShowMessage('⏳ _isLoading: $_isLoading');
      _safeShowMessage('👤 _userId: $_userId');
      _safeShowMessage('❌ _errorMessage: ${_errorMessage ?? 'NULL'}');

      _safeShowMessage('🧪 === STORAGE TEST ===');
      try {
        final testKey = 'debug_test_${DateTime.now().millisecondsSinceEpoch}';
        final testValue = 'test_value_${DateTime.now().millisecondsSinceEpoch}';
        await _storage.write(key: testKey, value: testValue);
        _safeShowMessage('✅ Test Write: SUCCESS');
        final readValue = await _storage.read(key: testKey);
        if (readValue == testValue) {
          _safeShowMessage('✅ Test Read: SUCCESS');
        } else {
          _safeShowMessage('❌ Test Read: FAILED - Expected: $testValue, Got: $readValue');
        }
        await _storage.delete(key: testKey);
        _safeShowMessage('✅ Test Cleanup: SUCCESS');
      } catch (testError) {
        _safeShowMessage('❌ Storage Test FAILED: $testError');
      }

      _safeShowMessage('📱 === SYSTEM INFO ===');
      _safeShowMessage('🤖 Platform: ${Theme.of(navigatorKey.currentContext!).platform}');
      _safeShowMessage('🔧 Debug Mode: $kDebugMode');
      _safeShowMessage('🔧 ========== STORAGE DEBUG END ==========');
    } catch (e) {
      _safeShowMessage('💥 CRITICAL ERROR in debugStorageState: $e');
      _safeShowMessage('📍 Error Type: ${e.runtimeType}');
      _safeShowMessage('📄 Stack Trace: ${e.toString()}');
    }
  }

  Future<void> clearAllStorageForDebug() async {
    try {
      _safeShowMessage('🗑️ === CLEARING ALL STORAGE ===');
      await _storage.deleteAll();
      _safeShowMessage('✅ SecureStorage cleared');
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _safeShowMessage('✅ SharedPreferences cleared');
      _isAuthenticated = false;
      _isOfflineMode = false;
      _isLoading = false;
      _userId = null;
      _errorMessage = null;
      notifyListeners();
      _safeShowMessage('✅ All variables reset');
    } catch (e) {
      _safeShowMessage('❌ Clear storage error: $e');
    }
  }

  Future<bool> checkTokenValidity() async {
    try {
      final isValid = await _apiService.checkTokenValidity();
      _isOfflineMode = false;
      return isValid;
    } catch (e) {
      _errorMessage = 'Failed to check token validity: $e';
      _safeShowMessage('🌐 Network error during token validation, using offline mode');
      final token = await getToken();
      final userId = await getUserId();
      if (token != null && token.isNotEmpty && userId != null) {
        _isAuthenticated = true;
        _isOfflineMode = true;
        _userId = userId;
        notifyListeners();
        return true;
      } else {
        _isAuthenticated = false;
        _isOfflineMode = true;
        notifyListeners();
        return false;
      }
    }
  }

  Future<Map<String, dynamic>> checkSubscription() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      final response = await _apiService.checkSubscription();
      _isOfflineMode = false;
      if (response['subscribed'] != null) {
        await saveSubscriptionStatusLocally(response['subscribed']);
      }
      return response;
    } catch (e) {
      _errorMessage = 'Failed to check subscription: $e';
      _safeShowMessage('🌐 Network error, falling back to offline subscription check');
      return await checkSubscriptionOffline();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> checkSubscriptionOffline() async {
    try {
      _safeShowMessage('🔄 Checking subscription in offline mode...');
      _isOfflineMode = true;
      final prefs = await SharedPreferences.getInstance();
      final lastSubscriptionStatus = prefs.getBool('last_subscription_status') ?? true;
      return {
        'subscribed': lastSubscriptionStatus,
        'redirect_to_subscription': false,
        'message': 'Offline mode - using cached subscription status',
        'offline_mode': true,
      };
    } catch (e) {
      _safeShowMessage('❌ Error checking offline subscription: $e');
      return {
        'subscribed': true,
        'redirect_to_subscription': false,
        'message': 'Error in offline mode, assuming valid subscription',
        'offline_mode': true,
      };
    }
  }

  Future<void> saveSubscriptionStatusLocally(bool isSubscribed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('last_subscription_status', isSubscribed);
      _safeShowMessage('✅ Subscription status saved locally: $isSubscribed');
    } catch (e) {
      _safeShowMessage('❌ Error saving subscription status locally: $e');
    }
  }
}