import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/services/subscription_manager.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/services/navigation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/services/revenuecat_service.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/services/fcm_service.dart'; // Import FcmService

class AuthenticationService {
  final BuildContext context;

  AuthenticationService(this.context);

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('AuthService: $message');
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String language,
  }) async {
    final authProvider = AuthProvider.instance;
    final localizations = AppLocalizations.of(context)!;

    _debugLog('Starting registration for: $email');

    final result = await authProvider.register(
      name: name,
      email: email,
      password: password,
      language: language,
    );

    if (result['success']) {
      if (result['requiresVerification']) {
        _showSuccessSnackBar(localizations.registrationSuccessful);
        _debugLog('Registration successful, navigating to verification');
        NavigationService.navigateTo(context, '/verify-email',
            arguments: email);
      }
    } else {
      _debugLog('Registration failed: ${result['message']}');
      _showErrorSnackBar(result['message'] ?? 'Google Sign-In failed');
    }
  }

  Future<void> logout() async {
    _debugLog('Starting logout process');

    final remindersNotifier = RemindersNotifier.instance;
    final authProvider = AuthProvider.instance;

    // 1. تسجيل الخروج من RevenueCat
    try {
      await RevenueCatService.instance.logoutUser();
      _debugLog('RevenueCat user logged out successfully');
    } catch (e) {
      _debugLog('RevenueCat logout failed (continuing): $e');
    }

    // 2. إلغاء جميع الإشعارات
    try {
      await remindersNotifier.cancelAllNotifications();
      _debugLog('All notifications cancelled');
    } catch (e) {
      _debugLog('Error cancelling notifications (continuing): $e');
    }

    // 3. مسح جميع التذكيرات والتخزين المؤقت
    try {
      await remindersNotifier.clearSessionCache();
      _debugLog('All reminders and cache cleared');
    } catch (e) {
      _debugLog('Error clearing session cache (continuing): $e');
    }

    // 4. إعادة تعيين RemindersNotifier instance
    try {
      await remindersNotifier.resetInstance();
      _debugLog('RemindersNotifier instance reset');
    } catch (e) {
      _debugLog('Error resetting RemindersNotifier (continuing): $e');
    }

    // 5. مسح بيانات الاشتراك (مهم جداً لمنع الدخول التلقائي)
    try {
      await SubscriptionManager().reset();
      _debugLog('SubscriptionManager data reset');
    } catch (e) {
      _debugLog('Error resetting SubscriptionManager (continuing): $e');
    }

    // 6. تسجيل الخروج من Google Sign-In
    try {
      await authProvider.signOutFromGoogle();
      _debugLog('Signed out from Google successfully');
    } catch (e) {
      _debugLog('Google sign-out failed (continuing with logout): $e');
    }

    // 7. مسح أي بيانات إضافية متعلقة بالجلسة
    try {
      await _clearAdditionalSessionData();
      _debugLog('Additional session data cleared');
    } catch (e) {
      _debugLog('Error clearing additional session data: $e');
    }

    // 8. استدعاء تسجيل الخروج من AuthProvider (الخطوة الأهم)
    try {
      await authProvider.logout();
      _debugLog('AuthProvider logout completed');
    } catch (e) {
      _debugLog('AuthProvider logout failed (CRITICAL): $e');
      // نحاول فرض مسح البيانات محلياً حتى لو فشل الاتصال
      try {
        await authProvider.clearToken();
      } catch (_) {}
    }

    // 9. مسح جميع بيانات المستخدم من AuthProvider
    try {
      await authProvider.clearAllUserData();
      _debugLog('All user data cleared from AuthProvider');
    } catch (e) {
      _debugLog('Error clearing AuthProvider data: $e');
    }

    _showSuccessSnackBar('Logged out successfully');
    _debugLog('Logout process finished');

    // 10. الانتقال إلى صفحة تسجيل الدخول
    NavigationService.navigateTo(context, '/auth');
  }

  Future<void> _clearAdditionalSessionData() async {
    try {
      // مسح أي تفضيلات مؤقتة أو cache إضافي
      final prefs = await SharedPreferences.getInstance();

      // قائمة بالمفاتيح التي يجب مسحها عند تسجيل الخروج
      const keysToRemove = [
        'last_sync_timestamp',
        'cached_user_preferences',
        'temp_session_data',
        'notification_permissions',
        'last_notification_check',
        'last_subscription_status', // إضافة مسح حالة الاشتراك
      ];

      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      _debugLog('Additional session data cleared');
    } catch (e) {
      _debugLog('Error clearing additional session data: $e');
    }
  }

  Future<void> _handlePostAuthFlow(int userId) async {
    _debugLog('Starting post-auth flow for user: $userId');

    try {
      // Send FCM Token to backend after successful login
      _debugLog('Attempting to send FCM token to backend.');
      try {
     //   await FcmService.instance.sendFcmTokenToBackend();
        _debugLog('FCM token send process initiated.');
      } catch (e) {
        _debugLog('Sending FCM token failed (non-critical): $e');
        // Do not rethrow, as this should not block the user flow.
      }

      // تسجيل الدخول في RevenueCat (التهيئة الأولية تمت في main.dart)
      await RevenueCatService.instance.loginUser(userId.toString());

      final hasInternet = await ConnectivityHelper.checkInternetConnection(verbose: false);

      if (!hasInternet) {
        _debugLog('No internet → going to reminders (offline mode)');
        NavigationService.navigateTo(context, '/reminders');
        return;
      }

      // فحص حالة الاشتراك
      final subscriptionManager = SubscriptionManager();
     // final subscriptionResponse = await subscriptionManager.checkSubscription();
       
   
    final  isPremium = await RevenueCatService.instance.isPremiumUser();
  
      if (isPremium == true) {
        _debugLog('User is subscribed → going to reminders');
        NavigationService.navigateTo(context, '/reminders');
      } else {
        _debugLog('User NOT subscribed → showing paywall');
        NavigationService.navigateTo(context, '/subscription_management');
      }
    } catch (e) {
      _debugLog('Error in post-auth flow: $e');
      NavigationService.navigateTo(context, '/reminders'); // fallback
    }
  }

  void _showSuccessSnackBar(String message) {
    //_debugLog('Showing success message: $message');
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(message, style: const TextStyle(color: Colors.white)),
    //     backgroundColor: Colors.green,
    //     duration: const Duration(seconds: 3),
    //     behavior: SnackBarBehavior.floating,
    //   ),
    // );
  }

  void _showErrorSnackBar(String message) {
    // _debugLog('Showing error message: $message');
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(message, style: const TextStyle(color: Colors.white)),
    //     backgroundColor: Colors.red,
    //     duration: const Duration(seconds: 4),
    //     behavior: SnackBarBehavior.floating,
    //   ),
    // );
  }

  Future<void> signInWithGoogle({required String language}) async {
    final authProvider = AuthProvider.instance;
    final localizations = AppLocalizations.of(context)!;

    _debugLog('Starting Google Sign-In');

    final result = await authProvider.signInWithGoogle(language: language);

    _debugLog('Google Sign-In result: ${result.toString()}');

    if (result['success']) {
      if (result['activated']) {
        _showSuccessSnackBar(localizations.loginSuccessful);
        _debugLog('Google Sign-In successful and activated');

        final userData = result['userData'];
        int? userId;

        if (userData != null) {
          if (userData['user'] != null && userData['user']['id'] != null) {
            userId = userData['user']['id'];
          } else if (userData['data'] != null &&
              userData['data']['user'] != null) {
            userId = userData['data']['user']['id'];
          } else if (userData['id'] != null) {
            userId = userData['id'];
          }
        }

        _debugLog('Extracted user ID: $userId');

        if (userId != null) {
          await _handlePostAuthFlow(userId);
        } else {
          _debugLog('Error: No user ID found in Google Sign-In response');
          _debugLog('Full response structure: ${result.toString()}');
          _showErrorSnackBar(
              'Authentication error: Unable to extract user information');
        }
      } else if (result['requiresVerification']) {
        _showSuccessSnackBar('Please verify your email to continue');
        _debugLog('Google Sign-In successful but requires verification');
        NavigationService.navigateTo(context, '/verify-email',
            arguments: authProvider.pendingVerificationEmail);
      }
    } else {
      _debugLog('Google Sign-In failed: ${result['message']}');
      _showErrorSnackBar(result['message'] ?? 'Google Sign-In failed');
    }
  }

  Future<void> login({
    required String email,
    required String password,
    required String language,
  }) async {
    final authProvider = AuthProvider.instance;
    final localizations = AppLocalizations.of(context)!;

    _debugLog('Starting login for: $email');

    final result = await authProvider.login(
      email: email,
      password: password,
      language: language,
    );

    if (result['success']) {
      if (result['activated']) {
        _showSuccessSnackBar(localizations.loginSuccessful);
        _debugLog('Login successful and activated');
        final userId = result['userData']?['user']?['id'];
        if (userId != null) {
          await _handlePostAuthFlow(userId);
        } else {
          _debugLog('Error: No user ID found in login response');
          _showErrorSnackBar('Authentication error: No user ID');
        }
      } else if (result['requiresVerification']) {
        _showSuccessSnackBar('Please verify your email to continue');
        _debugLog('Login successful but requires verification');
        NavigationService.navigateTo(context, '/verify-email',
            arguments: email);
      }
    } else {
      _debugLog('Login failed: ${result['message']}');
      _showErrorSnackBar(result['message']);
    }
  }
}