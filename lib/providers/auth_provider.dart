import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flex_reminder/services/subscription_manager.dart';


class AuthProvider with ChangeNotifier {
  static AuthProvider? _instance;
  static AuthProvider get instance {
    _instance ??= AuthProvider._internal();
    return _instance!;
  }

  factory AuthProvider() => instance;

  AuthProvider._internal() {
    _initializeGoogleSignIn();
  }

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventSubscription;
  bool _isAuthenticated = false;
  bool _previousIsAuthenticated = false; // متغير لتتبع الحالة السابقة
  bool _isLoading = false;
  String? _errorMessage;
  int? _userId;
  bool _hasActiveSubscription = false;
bool get hasActiveSubscription => _hasActiveSubscription;
  String? _firebaseUid;
  bool _isOfflineMode = false;
  bool _isInitializing = false;
  bool _isInitialized = false;
  String? _pendingVerificationEmail;
  bool _requiresVerification = false;
  bool _isActivated = false;
  bool _isGoogleSignInLoading = false;
  GoogleSignInAccount? _googleUser;
  bool _isGoogleAuthorized = false;
  SubscriptionManager? _subscriptionManager;
  bool _previousSubscriptionStatus = false; // متغير لتتبع حالة الاشتراك السابقة

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get userId => _userId;
  String? get firebaseUid => _firebaseUid;
  bool get isOfflineMode => _isOfflineMode;
  bool get isInitializing => _isInitializing;
  bool get isInitialized => _isInitialized;
  String? get pendingVerificationEmail => _pendingVerificationEmail;
  bool get requiresVerification => _requiresVerification;
  bool get isActivated => _isActivated;
  bool get isGoogleSignInLoading => _isGoogleSignInLoading;
  GoogleSignInAccount? get googleUser => _googleUser;
  bool get isGoogleAuthorized => _isGoogleAuthorized;

  @override
 @override
void notifyListeners() {
  // التحقق مما إذا كانت قيمة _isAuthenticated قد تغيرت إلى true
  if (_isAuthenticated && _previousIsAuthenticated != _isAuthenticated) {
    // إرسال FCM token إلى الخادم
    _sendFcmTokenToBackend();
  }
  
  // ✅ تحقق إضافي: لا ترسل FCM token إذا كان المستخدم غير مصدق
  if (!_isAuthenticated) {
    _safeShowMessage('⚠️ User not authenticated, skipping FCM token send');
    super.notifyListeners();
    return;
  }
  
  // تحديث الحالة السابقة
  _previousIsAuthenticated = _isAuthenticated;
  
  // استدعاء notifyListeners() الأصلي
  super.notifyListeners();
}
  
  // دالة مساعدة لإرسال FCM token
  Future<void> _sendFcmTokenToBackend() async {
    try {
      _safeShowMessage('🔄 إرسال FCM token إلى الخادم...');
      await FcmService.instance.sendFcmTokenToBackend();
      _safeShowMessage('✅ تم إرسال FCM token بنجاح');
    } catch (e) {
      _safeShowMessage('⚠️ فشل إرسال FCM token: $e');
    }
  }

  @override
  void dispose() {
    _authEventSubscription?.cancel();
    super.dispose();
  }

  // New method to get current user ID
  int? getCurrentUserId() {
    if (_userId != null) {
      _safeShowMessage('✅ Retrieved current user ID: $_userId');
      return _userId;
    } else {
      _safeShowMessage('❌ No user ID found');
      return null;
    }
  }

  void _safeShowMessage(String message) {
    if (kDebugMode) {
      debugPrint('AuthProvider: $message');
    }
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      _googleSignIn = GoogleSignIn.instance;
      await _googleSignIn.initialize(
        serverClientId:
            "1038373651011-aajl0k8goi5hknl4l0sqsnb78m7lnrfj.apps.googleusercontent.com",
      );
      _authEventSubscription = _googleSignIn.authenticationEvents
          .listen(_handleGoogleAuthenticationEvent)
        ..onError(_handleGoogleAuthenticationError);

      await initializeAuthentication();
    } catch (e) {
      _errorMessage = 'Error initializing Google Sign-In: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> _handleGoogleAuthenticationEvent(
      GoogleSignInAuthenticationEvent event) async {
    final GoogleSignInAccount? user = switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };

    const scopes = [
      'https://www.googleapis.com/auth/userinfo.email  ',
      'https://www.googleapis.com/auth/userinfo.profile  ',
    ];

    final authorization =
        await user?.authorizationClient.authorizationForScopes(scopes);

    setState(() {
      _googleUser = user;
      _isGoogleAuthorized = authorization != null;
      _errorMessage = null;
    });
  }

  Future<void> _handleGoogleAuthenticationError(Object e) async {
    setState(() {
      _googleUser = null;
      _isGoogleAuthorized = false;
      _errorMessage = e is GoogleSignInException
          ? _getGoogleSignInErrorMessage(e)
          : 'Unknown error during Google Sign-In';
    });
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
    final hasInternet = await ConnectivityHelper.checkInternetConnection(verbose: true);
    
    if (hasInternet) {
      try {
        final isValid = await _apiService.checkTokenValidity();
        if (isValid) {
          _userId = await getUserId();
          _firebaseUid = await getFirebaseUid();
          _isActivated = await getActivationStatus();
          
          if (_userId != null && _isActivated) {
            // ✅ المستخدم مصدق إذا كان الـ token صالحاً ومفعلاً
            _isAuthenticated = true;
            
            // فحص الاشتراك كنشاط ثانوي (لا يؤثر على المصادقة)
            await _checkSubscriptionAndSetAuthStatus();
          } else {
            await clearAllUserData();
            _isAuthenticated = false;
          }
        } else {
          await logout();
        }
      } catch (e) {
        _safeShowMessage('🌐 Network error, using offline mode: $e');
        // ✅ إذا فشل الاتصال، لا تزال مصدقاً إذا كان لديك token
        await _handleOfflineAuthentication(token);
      }
    } else {
      // لا إنترنت - استخدم البيانات المحفوظة
      await _handleOfflineAuthentication(token);
    }
  } else {
    _isAuthenticated = false; // لا يوجد token
  }
  } catch (e) {
    _safeShowMessage('❌ Critical error in initializeAuthentication: $e');
    _isAuthenticated = false;
    _isOfflineMode = false;
    _isActivated = false;
  } finally {
    _isInitializing = false;
    _isInitialized = true;
    notifyListeners();
    _safeShowMessage('✅ Authentication initialization completed');
  }
}
  // New method to check subscription and set authentication status
 Future<void> _checkSubscriptionAndSetAuthStatus() async {
  try {
    final userIdStr = _userId?.toString();
    if (userIdStr != null) {
      _subscriptionManager = SubscriptionManager();
      final subscriptionResponse = await _subscriptionManager!.checkSubscription(userId: userIdStr);
      
      final currentSubscriptionStatus = subscriptionResponse['subscribed'] == true;
      
      // ✅ لا تربط المصادقة بالاشتراك مباشرة
      // _isAuthenticated = currentSubscriptionStatus; // أزل هذا السطر
      
      // ✅ بدلاً من ذلك، احفظ حالة الاشتراك في متغير منفصل
      _hasActiveSubscription = currentSubscriptionStatus;
      
      if (currentSubscriptionStatus && !_previousSubscriptionStatus) {
        _showSubscriptionActiveNotification();
      }
      
      _previousSubscriptionStatus = currentSubscriptionStatus;
      _safeShowMessage('🔍 Subscription status: $currentSubscriptionStatus');
    } else {
      _safeShowMessage('❌ User ID is null, cannot check subscription');
      _hasActiveSubscription = false;
    }
  } catch (e) {
    _safeShowMessage('⚠️ Error checking subscription (non-critical): $e');
    // ✅ في حال فشل فحص الاشتراك، لا تغير حالة المصادقة
    // وضع قيمة افتراضية
    _hasActiveSubscription = false;
  }
}

 // Method to show notification when subscription is active
void _showSubscriptionActiveNotification() {
  showGlobalSnackBar(
    'تم تفعيل اشتراكك بنجاح! يمكنك الآن استخدام جميع الميزات المميزة.',
    backgroundColor: Colors.green,
    duration: const Duration(seconds: 5),
  );
}
// دالة خاصة لتهيئة FCM وإرسال التوكن بعد نجاح تسجيل الدخول
  Future<void> _finalizeAuthenticationFlow() async {
    try {
      _safeShowMessage('🔗 Finalizing authentication flow...');
      
      // 1. التأكد من أن FCM Service مهيأة
      if (!FcmService.instance.isInitialized) {
         _safeShowMessage('🔄 Initializing FCM Service explicitly...');
         await FcmService.instance.init();
      }
      
      // 2. إرسال التوكن (النسخة المحسنة ستجلب التوكن إذا كان مفقوداً)
      await FcmService.instance.sendFcmTokenToBackend();
      
    } catch (e) {
      _safeShowMessage('⚠️ Error during auth finalization: $e');
    }
  }
  Future<void> _handleOfflineAuthentication(String token) async {
    if (token.isNotEmpty) {
      _userId = await getUserId();
      _firebaseUid = await getFirebaseUid();
      _isActivated = await getActivationStatus();
      if (!_isActivated || _userId == null) {
        _safeShowMessage(
            '❌ Account not activated or incomplete data in offline mode, clearing all data...');
        await clearAllUserData();
        _isAuthenticated = false;
        _isOfflineMode = false;
        return;
      }
      
      // In offline mode, we can't check subscription, so set isAuthenticated to false
      _isAuthenticated = false;
      _isOfflineMode = true;
      _safeShowMessage(
          '✅ Offline authentication accepted but subscription cannot be verified');
    } else {
      _isAuthenticated = false;
      _isOfflineMode = true;
      _isActivated = false;
      _safeShowMessage('❌ No token found for offline authentication');
    }
  }

  Future<void> clearAllUserData() async {
    try {
      await _storage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _userId = null;
      _firebaseUid = null;
      _isActivated = false;
      _isAuthenticated = false;
      _isOfflineMode = false;
      _requiresVerification = false;
      _pendingVerificationEmail = null;
      _previousSubscriptionStatus = false; // Reset previous subscription status
      _safeShowMessage('✅ All user data cleared');
    } catch (e) {
      _errorMessage = 'Error clearing all user data: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String language = 'en',
    }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _requiresVerification = false;
      _pendingVerificationEmail = null;
      notifyListeners();

      final result = await _apiService.register(
        name,
        email,
        password,
        language: language,
      );

      if (result['success']) {
        final userData = result['data']['user'];
        _pendingVerificationEmail = email;
        _requiresVerification = true;
        _isAuthenticated = false;
        _isOfflineMode = false;
        _isActivated = false;
        _safeShowMessage(
            '✅ Registration successful, verification required for $email');
        return {
          'success': true,
          'requiresVerification': true,
          'userId': userData['id']
        };
      } else {
        _errorMessage = result['data']['message'] ??
            result['data']['errors']?.join('\n') ??
            'Registration failed';
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _errorMessage = 'Error during registration: ${e.toString()}';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String language = 'en',
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _requiresVerification = false;
      _pendingVerificationEmail = null;
      notifyListeners();

      final result = await _apiService.login(
        email,
        password,
        language: language,
      );

      if (result['success'] == true || result['status'] == 'success') {
        final userData = result['data'] ?? result;
        _isActivated = userData['activated'] ?? false;
        await setActivationStatus(_isActivated);

        if (_isActivated) {
          await setToken(userData['access_token']);
          await setUserId(userData['user']['id']);
          _isOfflineMode = false;
          
          // Check subscription status to determine authentication
          await _checkSubscriptionAndSetAuthStatus();
          _finalizeAuthenticationFlow(); 
          _safeShowMessage('✅ Login successful, Activated: $_isActivated');
          return {'success': true, 'activated': true, 'userData': userData};
        } else {
          _pendingVerificationEmail = email;
          _requiresVerification = true;
          _isAuthenticated = false;
          _safeShowMessage(
              '⚠️ Account not activated, verification required for $email');
          return {
            'success': true,
            'activated': false,
            'requiresVerification': true
          };
        }
      } else {
        _errorMessage = result['error'] ?? result['message'] ?? 'Login failed';
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _errorMessage = 'Error during login: ${e.toString()}';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // استبدال دالة signInWithGoogle بالكامل - الإصدار المصحح
  Future<Map<String, dynamic>> signInWithGoogle(
      {String language = 'en'}) async {
    try {
      _isGoogleSignInLoading = true;
      _errorMessage = null;
      _requiresVerification = false;
      _pendingVerificationEmail = null;
      notifyListeners();

      // التأكد من وجود اتصال بالإنترنت
      final hasInternet =
          await ConnectivityHelper.checkInternetConnection(verbose: true);
      if (!hasInternet) {
        _errorMessage = 'No internet connection available';
        return {'success': false, 'message': _errorMessage};
      }

      _safeShowMessage('🔄 Starting Google Sign-In process...');

      // تنظيف الجلسة السابقة
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        _safeShowMessage('Previous session cleanup: $e');
      }

      // محاولة تسجيل الدخول مع معالجة أفضل للأخطاء
      GoogleSignInAccount? googleUser;

      try {
        // استخدام الطريقة الصحيحة للتسجيل
        if (_googleSignIn.supportsAuthenticate()) {
          googleUser = await _googleSignIn.authenticate();
        } else {
          // fallback للأجهزة القديمة
          //   googleUser = await _googleSignIn.signIn();
        }
      } catch (e) {
        _safeShowMessage('Google Sign-In Exception: $e');

        // معالجة الأخطاء بدون استخدام enum غير موجود
        if (e.toString().contains('canceled') ||
            e.toString().contains('cancelled')) {
          _errorMessage = 'تم إلغاء تسجيل الدخول بواسطة المستخدم';
        } else if (e.toString().contains('network')) {
          _errorMessage = 'خطأ في الشبكة، يرجى التحقق من الاتصال بالإنترنت';
        } else if (e.toString().contains('sign_in_failed')) {
          _errorMessage = 'فشل في تسجيل الدخول، يرجى المحاولة مرة أخرى';
        } else if (e.toString().contains('sign_in_required')) {
          _errorMessage = 'يرجى اختيار حساب Google للمتابعة';
        } else {
          _errorMessage = 'خطأ في Google Sign-In: $e';
        }
        return {'success': false, 'message': _errorMessage};
      }

      // التحقق من أن المستخدم لم يلغي العملية
      if (googleUser == null) {
        _errorMessage = 'تم إلغاء تسجيل الدخول';
        return {'success': false, 'message': _errorMessage, 'cancelled': true};
      }

      _safeShowMessage('✅ Google user selected: ${googleUser.email}');

      // التحقق من صحة بيانات المستخدم
      if (googleUser.email.isEmpty) {
        _errorMessage = 'بيانات المستخدم غير صحيحة من Google';
        return {'success': false, 'message': _errorMessage};
      }

      // الحصول على التفويضات مع معالجة الأخطاء
      GoogleSignInAuthentication? googleAuth;
      try {
        googleAuth = googleUser.authentication;
      } catch (e) {
        _safeShowMessage('Authentication error: $e');
        _errorMessage = 'فشل في الحصول على تفويضات Google';
        return {'success': false, 'message': _errorMessage};
      }

      // التحقق من وجود الـ tokens - استخدام الأسماء الصحيحة
      if (googleAuth.idToken == null) {
        _errorMessage = 'فشل في الحصول على الرموز المميزة من Google';
        return {'success': false, 'message': _errorMessage};
      }

      _safeShowMessage('✅ Google authentication tokens obtained');

      // إنشاء كريدنشيال Firebase - استخدام idToken فقط
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // تسجيل الدخول في Firebase مع معالجة الأخطاء
      UserCredential? userCredential;
      try {
        userCredential = await _firebaseAuth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        _safeShowMessage('Firebase Auth Exception: ${e.code} - ${e.message}');
        switch (e.code) {
          case 'account-exists-with-different-credential':
            _errorMessage = 'الحساب موجود بطريقة تسجيل دخول أخرى';
            break;
          case 'invalid-credential':
            _errorMessage = 'بيانات الاعتماد غير صحيحة';
            break;
          case 'user-disabled':
            _errorMessage = 'الحساب معطل';
            break;
          default:
            _errorMessage = 'خطأ في Firebase: ${e.message}';
        }
        return {'success': false, 'message': _errorMessage};
      } catch (e) {
        _errorMessage = 'خطأ في تسجيل الدخول في Firebase: $e';
        return {'success': false, 'message': _errorMessage};
      }

      final User? firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        _errorMessage = 'فشل في التحقق من هوية Firebase';
        return {'success': false, 'message': _errorMessage};
      }

      _safeShowMessage('✅ Firebase authentication successful');

      // الحصول على Firebase ID Token
      String idToken;
      try {
        final token = await firebaseUser.getIdToken(true); // force refresh
        if (token == null) {
          _errorMessage = 'فشل في الحصول على رمز Firebase';
          return {'success': false, 'message': _errorMessage};
        }
        idToken = token;
      } catch (e) {
        _safeShowMessage('Token error: $e');
        _errorMessage = 'فشل في الحصول على رمز Firebase';
        return {'success': false, 'message': _errorMessage};
      }

      // إعداد بيانات المستخدم
      final googleUserData = <String, String>{
        'name': googleUser.displayName ?? '',
        'email': googleUser.email,
        'photo': googleUser.photoUrl ?? '',
        'google_id': firebaseUser.uid,
      };

      _safeShowMessage('🔄 Sending request to backend...');

      // إرسال البيانات للخادم
      Map<String, dynamic> result;
      try {
        result = await _apiService.loginWithGoogle(
          firebaseToken: idToken,
          googleUser: googleUserData,
          language: language,
        );
      } catch (e) {
        _safeShowMessage('API request failed: $e');
        _errorMessage = 'فشل في الاتصال بالخادم: $e';
        return {'success': false, 'message': _errorMessage};
      }

      _safeShowMessage('API Result: $result');

      if (result['success'] == true) {
        final userData = result['data'];
        final bool isActivated = result['activated'] ??
            userData?['activated'] ??
            (userData?['user']?['activated'] == 1) ??
            true;

        _isActivated = isActivated;
        await setActivationStatus(_isActivated);

        if (_isActivated) {
          final accessToken = userData?['access_token'];
          if (accessToken == null) {
            _errorMessage = 'رمز الوصول غير موجود في استجابة الخادم';
            return {'success': false, 'message': _errorMessage};
          }

          await setToken(accessToken);

          final userId = userData?['user']?['id'];
          if (userId == null) {
            _errorMessage = 'معرف المستخدم غير موجود في استجابة الخادم';
            return {'success': false, 'message': _errorMessage};
          }

          await setUserId(userId);
          _firebaseUid = firebaseUser.uid;
          await setFirebaseUid(_firebaseUid!);
          _isOfflineMode = false;
          
          // Check subscription status to determine authentication
          await _checkSubscriptionAndSetAuthStatus();
          await  _finalizeAuthenticationFlow(); 
          _safeShowMessage('✅ Successfully signed in with Google');
          return {'success': true, 'activated': true, 'userData': userData};
        } else {
          _pendingVerificationEmail = googleUser.email;
          _requiresVerification = true;
          _isAuthenticated = false;
          _safeShowMessage(
              '⚠️ Account not activated, verification required for ${googleUser.email}');
          return {
            'success': true,
            'activated': false,
            'requiresVerification': true
          };
        }
      } else {
        _errorMessage =
            result['message'] ?? result['error'] ?? 'فشل في Google Sign-In';
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _safeShowMessage('SignInWithGoogle Exception: $e');
      _errorMessage = 'خطأ أثناء تسجيل الدخول بـ Google: $e';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isGoogleSignInLoading = false;
      notifyListeners();
    }
  }

  String _getGoogleSignInErrorMessage(GoogleSignInException e) {
    final errorString = e.toString().toLowerCase();

    if (errorString.contains('canceled') || errorString.contains('cancelled')) {
      return 'تم إلغاء تسجيل الدخول';
    } else if (errorString.contains('network')) {
      return 'خطأ في الشبكة، تحقق من الاتصال بالإنترنت';
    } else if (errorString.contains('sign_in_required')) {
      return 'يرجى اختيار حساب Google';
    } else if (errorString.contains('sign_in_failed')) {
      return 'فشل تسجيل الدخول، حاول مرة أخرى';
    } else if (errorString.contains('account_already_exists')) {
      return 'الحساب موجود بالفعل، جرب طريقة أخرى';
    } else {
      return 'خطأ في Google Sign-In: ${e.toString()}';
    }
  }

  Future<void> signOutFromGoogle() async {
    try {
      await _googleSignIn.disconnect();
      _googleUser = null;
      _isGoogleAuthorized = false;
      notifyListeners();
      _safeShowMessage('✅ Signed out from Google');
    } catch (e) {
      _errorMessage = 'Error signing out from Google: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      try {
        await _apiService.logout();
      } catch (e) {
        _safeShowMessage('Server logout failed (offline): $e');
      }

      await clearToken();
      _isAuthenticated = false;
      _isOfflineMode = false;
      _userId = null;
      _errorMessage = null;
      _requiresVerification = false;
      _pendingVerificationEmail = null;
      _isActivated = false;
      _previousSubscriptionStatus = false; // Reset previous subscription status
      _safeShowMessage('✅ Logged out successfully');
    } catch (e) {
      _errorMessage = 'Failed to logout: $e';
      _safeShowMessage(_errorMessage!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setToken(String token) async {
    try {
      await _storage.write(key: 'auth_token', value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backup_auth_token', token);
    } catch (e) {
      _errorMessage = 'Error saving token: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> setUserId(int userId) async {
    try {
      await _storage.write(key: 'user_id', value: userId.toString());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', userId);
      await prefs.setString('user_id_string', userId.toString());
      _userId = userId;
      _safeShowMessage('_userId set to: $userId');
    } catch (e) {
      _errorMessage = 'Error saving user ID: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> setActivationStatus(bool isActivated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_activated', isActivated);
      _isActivated = isActivated;
      _safeShowMessage('✅ Activation status set to: $isActivated');
    } catch (e) {
      _errorMessage = 'Error setting activation status: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> setFirebaseUid(String firebaseUid) async {
    try {
      await _storage.write(key: 'firebase_uid', value: firebaseUid);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firebase_uid', firebaseUid);
    } catch (e) {
      _errorMessage = 'Error saving Firebase UID: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<void> clearToken() async {
    try {
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_id');
      await _storage.delete(key: 'firebase_uid');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('backup_auth_token');
      await prefs.remove('user_id');
      await prefs.remove('user_id_string');
      await prefs.remove('last_login_email');
      await prefs.remove('last_login_date');
      await prefs.remove('is_activated');
      _isActivated = false;
    } catch (e) {
      _errorMessage = 'Error clearing tokens: $e';
      _safeShowMessage(_errorMessage!);
    }
  }

  Future<bool> getActivationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActivated = prefs.getBool('is_activated') ?? false;
      _safeShowMessage('✅ Activation status retrieved: $isActivated');
      return isActivated;
    } catch (e) {
      _errorMessage = 'Error retrieving activation status: $e';
      _safeShowMessage(_errorMessage!);
      return false;
    }
  }

  Future<String?> getToken() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      _safeShowMessage('❌ SecureStorage read error: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final backupToken = prefs.getString('backup_auth_token');
      if (backupToken != null && backupToken.isNotEmpty) {
        return backupToken;
      }
    } catch (e) {
      _safeShowMessage('❌ SharedPreferences backup read error: $e');
    }
    return null;
  }

  Future<int?> getUserId() async {
    try {
      final idStr = await _storage.read(key: 'user_id');
      _safeShowMessage('idStr set to: $idStr');
      if (idStr != null) {
        final id = int.tryParse(idStr);
        if (id != null) {
          return id;
        }
      }
    } catch (e) {
      _safeShowMessage('❌ SecureStorage read error for user_id: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId != null) {
        return userId;
      }
    } catch (e) {
      _safeShowMessage('❌ SharedPreferences read error for user_id: $e');
    }
    return null;
  }

  Future<String?> getFirebaseUid() async {
    try {
      final uid = await _storage.read(key: 'firebase_uid');
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
    } catch (e) {
      _safeShowMessage('❌ SecureStorage read error for firebase_uid: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('firebase_uid');
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
    } catch (e) {
      _safeShowMessage('❌ SharedPreferences read error for firebase_uid: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      final result = await _apiService.verifyEmail(email, code);
      if (result['success']) {
        final userData = result['data'];
        await setToken(userData['token']);
        await setUserId(userData['user']['id']);
        await setActivationStatus(true);
        _isOfflineMode = false;
        _requiresVerification = false;
        _pendingVerificationEmail = null;
        _isActivated = true;
        
        // Check subscription status to determine authentication
        await _checkSubscriptionAndSetAuthStatus();
        await  _finalizeAuthenticationFlow(); 
        _safeShowMessage('✅ Email verified successfully for $email');
        return {'success': true};
      } else {
        _errorMessage = result['error'] ?? 'Verification failed';
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _errorMessage = 'Error verifying email: ${e.toString()}';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // ✅ دالة لإعادة محاولة إرسال FCM token
  Future<void> retryFcmTokenSend({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        _safeShowMessage('🔄 Retry FCM token send attempt ${i + 1}/$maxRetries');
        await FcmService.instance.sendFcmTokenToBackend();
        _safeShowMessage('✅ FCM token sent successfully on retry');
        return;
      } catch (e) {
        _safeShowMessage('❌ Retry $i failed: $e');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (i + 1) * 2));
        }
      }
    }
    _safeShowMessage('❌ All FCM token retry attempts failed');
  }
  
  Future<Map<String, dynamic>> resendVerificationCode(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      await _apiService.resendVerificationCode(email);
      _isOfflineMode = false;
      _safeShowMessage('✅ Verification code resent to $email');
      return {'success': true};
    } catch (e) {
      _errorMessage = 'Error resending verification code: ${e.toString()}';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> updatePassword(
      String email, String password, String passwordConfirmation) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final hasInternet =
          await ConnectivityHelper.checkInternetConnection(verbose: true);
      if (!hasInternet) {
        _errorMessage = 'No internet connection, cannot update password';
        return {'success': false, 'message': _errorMessage};
      }

      final response = await _apiService.request(
        'POST',
        'password/update',
        data: {
          'email': email,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );

      if (response['statusCode'] == 200) {
        _safeShowMessage('✅ Password updated successfully');
        return {'success': true};
      } else {
        _errorMessage =
            response['data']['message'] ?? 'Failed to update password';
        return {'success': false, 'message': _errorMessage};
      }
    } catch (e) {
      _errorMessage = 'Error updating password: ${e.toString()}';
      return {'success': false, 'message': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearVerificationState() {
    _requiresVerification = false;
    _pendingVerificationEmail = null;
    notifyListeners();
  }

  // دالة لتحديد حالة التحميل العادي
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // دالة لتحديد حالة تحميل Google Sign-In
  void setGoogleSignInLoading(bool loading) {
    _isGoogleSignInLoading = loading;
    notifyListeners();
  }

  // دالة لإعادة تعيين جميع حالات التحميل
  void resetLoadingState() {
    _isLoading = false;
    _isGoogleSignInLoading = false;
    notifyListeners();
  }

  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }
  
  // Method to refresh subscription status
  Future<void> refreshSubscriptionStatus() async {
    if (_userId != null) {
      await _checkSubscriptionAndSetAuthStatus();
      await  _finalizeAuthenticationFlow(); 
    }
  }
}