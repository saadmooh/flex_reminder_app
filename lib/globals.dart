import 'dart:collection';
import 'dart:async';  // ✅ إضافة هذا السطر
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Global keys for navigation and scaffold messenger
// ============================================================================
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
// متغير وضع Debug لتفعيل/تعطيل رسائل SnackBar
// ============================================================================
bool _isDebugMode = true;

// ============================================================================
// متغيرات حالة الاشتراك المحفوظة (للقراءة فقط)
// ============================================================================
String _subscriptionUserId = '';
String _subscriptionEventType = '';
String _subscriptionStatus = '';
int _subscriptionUpdateTimestamp = 0;

// Stream controller لإعلام المستمعين بتغييرات الاشتراك
final StreamController<Map<String, dynamic>> _subscriptionStatusController = 
    StreamController<Map<String, dynamic>>.broadcast();

// ============================================================================
// Getters and Setters for Debug Mode
// ============================================================================
bool get isDebugMode => _isDebugMode;
set isDebugMode(bool value) {
  _isDebugMode = value;
  if (!value) {
    clearSnackBarQueue();
  }
}

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
}

// ============================================================================
// Getters and Setters for Initialization Error
// ============================================================================
String? get initializationError => _initializationError;
set initializationError(String? value) => _initializationError = value;

// ============================================================================
// Getters for Subscription Data (Read Only)
// ============================================================================
String get subscriptionUserId => _subscriptionUserId;
String get subscriptionEventType => _subscriptionEventType;
String get subscriptionStatus => _subscriptionStatus;
int get subscriptionUpdateTimestamp => _subscriptionUpdateTimestamp;

// Stream getter for subscription status changes
Stream<Map<String, dynamic>> get subscriptionStatusStream => 
    _subscriptionStatusController.stream;

// ============================================================================
// دوال بيانات الاشتراك (للقراءة فقط من SharedPreferences)
// ============================================================================

/// تحميل بيانات الاشتراك من التخزين المحلي فقط
Future<void> loadSubscriptionData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    _subscriptionUserId = prefs.getString('subscription_user_id') ?? '';
    _subscriptionEventType = prefs.getString('subscription_event_type') ?? '';
    
    // قراءة الحالة من bool المحفوظ
    bool isActive = prefs.getBool('subscription_status') ?? false;
    _subscriptionStatus = isActive ? 'active' : 'inactive';
    
    _subscriptionUpdateTimestamp = prefs.getInt('subscription_timestamp') ?? 0;
    
    // إعلام المستمعين بالبيانات المحملة
    if (!_subscriptionStatusController.isClosed) {
      _subscriptionStatusController.add(getSubscriptionDataMap());
    }
  } catch (e) {
    // تجاهل الأخطاء
  }
}

/// الحصول على بيانات الاشتراك كخريطة
Map<String, dynamic> getSubscriptionDataMap() {
  return {
    'userId': _subscriptionUserId,
    'eventType': _subscriptionEventType,
    'status': _subscriptionStatus,
    'updateTimestamp': _subscriptionUpdateTimestamp,
  };
}

/// التحقق مما إذا كان الاشتراك نشطاً
bool isSubscriptionActive() {
  return _subscriptionStatus.toLowerCase() == 'active';
}

/// التحقق مما إذا كانت بيانات الاشتراك متاحة
bool hasSubscriptionData() {
  return _subscriptionUserId.isNotEmpty && _subscriptionUpdateTimestamp > 0;
}

/// الحصول على وصف الحدث
String getSubscriptionEventDescription() {
  switch (_subscriptionEventType.toLowerCase()) {
    case 'initial_purchase':
      return 'تم تفعيل اشتراك جديد';
    case 'renewal':
      return 'تم تجديد الاشتراك';
    case 'cancellation':
      return 'تم إلغاء الاشتراك';
    case 'uncancellation':
      return 'تم استعادة الاشتراك';
    case 'expiration':
      return 'انتهت صلاحية الاشتراك';
    case 'billing_issue':
      return 'مشكلة في الدفع';
    case 'product_change':
      return 'تم تغيير خطة الاشتراك';
    case 'revenuecat_check':
      return 'فحص من RevenueCat';
    case 'restore_purchase':
      return 'استعادة المشتريات';
    default:
      return 'تحديث في الاشتراك';
  }
}

// ============================================================================
// نظام SnackBar المحسّن مع قائمة الانتظار
// ============================================================================

class _SnackBarQueueManager {
  static final _SnackBarQueueManager _instance = _SnackBarQueueManager._internal();
  factory _SnackBarQueueManager() => _instance;
  _SnackBarQueueManager._internal();

  final Queue<_SnackBarMessage> _queue = Queue<_SnackBarMessage>();
  bool _isProcessing = false;
  
  void addMessage({
    required String message,
    Color backgroundColor = Colors.blue,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    if (!_isDebugMode) {
      return;
    }

    _queue.add(_SnackBarMessage(
      message: message,
      backgroundColor: backgroundColor,
      duration: duration,
      timestamp: DateTime.now(),
    ));

    if (!_isProcessing) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;

    while (_queue.isNotEmpty) {
      if (!_isDebugMode) {
        _queue.clear();
        _isProcessing = false;
        return;
      }

      final message = _queue.removeFirst();
      
      try {
        await _displaySnackBar(message);
        
        if (_queue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
        continue;
      }
    }

    _isProcessing = false;
  }

  Future<void> _displaySnackBar(_SnackBarMessage message) async {
    try {
      final messenger = scaffoldMessengerKey.currentState;
      
      if (messenger == null || !messenger.mounted) {
        return;
      }

      messenger.clearSnackBars();

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            message.message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: message.backgroundColor,
          duration: message.duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          dismissDirection: DismissDirection.horizontal,
        ),
      );
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  void clearQueue() {
    _queue.clear();
    _isProcessing = false;
  }

  int get queueLength => _queue.length;
  bool get hasMessages => _queue.isNotEmpty;
  bool get isProcessing => _isProcessing;
}

class _SnackBarMessage {
  final String message;
  final Color backgroundColor;
  final Duration duration;
  final DateTime timestamp;

  _SnackBarMessage({
    required this.message,
    required this.backgroundColor,
    required this.duration,
    required this.timestamp,
  });
}

// ============================================================================
// دالة موحدة لعرض SnackBar
// ============================================================================

Future<void> showGlobalSnackBar(
  String message, {
  Color backgroundColor = Colors.blue,
  Duration duration = const Duration(milliseconds: 1500),
}) async {
  try {
    if (!_isDebugMode) {
      return;
    }

    _SnackBarQueueManager().addMessage(
      message: message,
      backgroundColor: backgroundColor,
      duration: duration,
    );

    await Future.delayed(const Duration(milliseconds: 50));
  } catch (e) {
    // تجاهل الأخطاء
  }
}

// ============================================================================
// دوال إضافية لإدارة قائمة الانتظار
// ============================================================================

void clearSnackBarQueue() {
  _SnackBarQueueManager().clearQueue();
}

int getSnackBarQueueLength() {
  return _SnackBarQueueManager().queueLength;
}

bool hasSnackBarMessages() {
  return _SnackBarQueueManager().hasMessages;
}

bool isSnackBarProcessing() {
  return _SnackBarQueueManager().isProcessing;
}

// ============================================================================
// دوال مساعدة سريعة لعرض رسائل ملونة
// ============================================================================

Future<void> showSuccessSnackBar(String message) async {
  await showGlobalSnackBar('✅ $message', backgroundColor: Colors.green);
}

Future<void> showErrorSnackBar(String message) async {
  await showGlobalSnackBar('❌ $message', backgroundColor: Colors.red);
}

Future<void> showWarningSnackBar(String message) async {
  await showGlobalSnackBar('⚠️ $message', backgroundColor: Colors.orange);
}

Future<void> showInfoSnackBar(String message) async {
  await showGlobalSnackBar('ℹ️ $message', backgroundColor: Colors.blue);
}

Future<void> showLoadingSnackBar(String message) async {
  await showGlobalSnackBar('🔄 $message', backgroundColor: Colors.blueGrey);
}

// ============================================================================
// دالة للتحقق من جاهزية جميع الخدمات
// ============================================================================
bool get areAllServicesInitialized =>
    _isFirebaseInitialized &&
    _isFcmInitialized &&
    _isRemindersNotifierInitialized;

void printServicesStatus() {
  // تم إزالة جميع رسائل الطباعة
}