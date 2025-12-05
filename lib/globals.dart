import 'package:flutter/material.dart';

// Global keys for navigation and scaffold messenger
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// ============================================================================
// متغيرات حالة تهيئة الخدمات
// ============================================================================
bool _isFirebaseInitialized = false;
bool _isFcmInitialized = false;
bool _isRevenueCatInitialized = false;
bool _isRemindersNotifierInitialized = false;
String? _initializationError;

// ============================================================================
// Getters and Setters for Firebase
// ============================================================================
bool get isFirebaseInitialized => _isFirebaseInitialized;
set isFirebaseInitialized(bool value) => _isFirebaseInitialized = value;

// ============================================================================
// Getters and Setters for FCM
// ============================================================================
bool get isFcmInitialized => _isFcmInitialized;
set isFcmInitialized(bool value) => _isFcmInitialized = value;

// ============================================================================
// Getters and Setters for RevenueCat
// ============================================================================
bool get isRevenueCatInitialized => _isRevenueCatInitialized;
set isRevenueCatInitialized(bool value) => _isRevenueCatInitialized = value;

// ============================================================================
// Getters and Setters for RemindersNotifier
// ============================================================================
bool get isRemindersNotifierInitialized => _isRemindersNotifierInitialized;
set isRemindersNotifierInitialized(bool value) {
  _isRemindersNotifierInitialized = value;
  debugPrint('🔔 RemindersNotifier initialized state: $value');
}

// ============================================================================
// Getters and Setters for Initialization Error
// ============================================================================
String? get initializationError => _initializationError;
set initializationError(String? value) => _initializationError = value;

// ============================================================================
// دالة موحدة لعرض SnackBar من أي مكان في التطبيق
// ============================================================================
void showGlobalSnackBar(
  String message, {
  Color backgroundColor = Colors.blue,
  Duration duration = const Duration(seconds: 3),
  bool clearPrevious = true,
}) {
  // استخدام addPostFrameCallback لضمان عرض SnackBar بعد اكتمال بناء الـ UI
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null || !messenger.mounted) {
        debugPrint('⚠️ ScaffoldMessenger not available: $message');
        return;
      }

      if (clearPrevious) {
        messenger.clearSnackBars();
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ SnackBar error: $e');
    }
  });
}

// ============================================================================
// دالة للتحقق من جاهزية جميع الخدمات
// ============================================================================
bool get areAllServicesInitialized =>
    _isFirebaseInitialized &&
    _isFcmInitialized &&
    _isRemindersNotifierInitialized;

/// طباعة حالة جميع الخدمات
void printServicesStatus() {
  debugPrint('═══════════════════════════════════════════');
  debugPrint('📊 حالة الخدمات:');
  debugPrint('   Firebase: ${_isFirebaseInitialized ? "✅" : "❌"}');
  debugPrint('   FCM: ${_isFcmInitialized ? "✅" : "❌"}');
  debugPrint('   RevenueCat: ${_isRevenueCatInitialized ? "✅" : "❌"}');
  debugPrint('   RemindersNotifier: ${_isRemindersNotifierInitialized ? "✅" : "❌"}');
  if (_initializationError != null) {
    debugPrint('   ⚠️ خطأ: $_initializationError');
  }
  debugPrint('═══════════════════════════════════════════');
}