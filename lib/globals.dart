import 'dart:collection';
import 'package:flutter/material.dart';

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
// نظام SnackBar المحسّن مع قائمة الانتظار
// ============================================================================

class _SnackBarQueueManager {
  // Singleton pattern
  static final _SnackBarQueueManager _instance = _SnackBarQueueManager._internal();
  factory _SnackBarQueueManager() => _instance;
  _SnackBarQueueManager._internal();

  // قائمة انتظار الرسائل
  final Queue<_SnackBarMessage> _queue = Queue<_SnackBarMessage>();
  
  // حالة المعالجة
  bool _isProcessing = false;
  
  // إضافة رسالة إلى قائمة الانتظار
  void addMessage({
    required String message,
    Color backgroundColor = Colors.blue,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    _queue.add(_SnackBarMessage(
      message: message,
      backgroundColor: backgroundColor,
      duration: duration,
      timestamp: DateTime.now(),
    ));

    // بدء المعالجة إذا لم تكن قد بدأت
    if (!_isProcessing) {
      _processQueue();
    }
  }

  // معالجة قائمة الانتظار
  Future<void> _processQueue() async {
    if (_queue.isEmpty) {
      _isProcessing = false;
      return;
    }

    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final message = _queue.removeFirst();
      
      try {
        await _displaySnackBar(message);
        
        // انتظار قصير بين الرسائل لتجنب التكدس (200ms)
        if (_queue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
        debugPrint('❌ خطأ في عرض SnackBar: $e');
        // الاستمرار في معالجة الرسائل التالية حتى لو حدث خطأ
        continue;
      }
    }

    _isProcessing = false;
  }

  // عرض SnackBar واحد
  Future<void> _displaySnackBar(_SnackBarMessage message) async {
    try {
      final messenger = scaffoldMessengerKey.currentState;
      
      if (messenger == null || !messenger.mounted) {
        debugPrint('⚠️ ScaffoldMessenger غير متاح: ${message.message}');
        return;
      }

      // إزالة أي SnackBar سابق
      messenger.clearSnackBars();

      // عرض SnackBar الجديد
      final controller = messenger.showSnackBar(
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

      // انتظار حتى يتم إخفاء SnackBar أو مدة أقصاها
      await controller.closed.timeout(
        message.duration + const Duration(milliseconds: 500),
        onTimeout: () => SnackBarClosedReason.timeout,
      );

      debugPrint('📱 تم عرض SnackBar: ${message.message}');
    } catch (e) {
      debugPrint('❌ خطأ في _displaySnackBar: $e');
      rethrow;
    }
  }

  // مسح قائمة الانتظار
  void clearQueue() {
    _queue.clear();
    _isProcessing = false;
    debugPrint('🗑️ تم مسح قائمة انتظار SnackBar');
  }

  // الحصول على عدد الرسائل في قائمة الانتظار
  int get queueLength => _queue.length;

  // التحقق من وجود رسائل في قائمة الانتظار
  bool get hasMessages => _queue.isNotEmpty;

  // التحقق من حالة المعالجة
  bool get isProcessing => _isProcessing;
}

// كلاس لتخزين بيانات الرسالة
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

  @override
  String toString() {
    return 'SnackBarMessage(message: $message, timestamp: $timestamp)';
  }
}

// ============================================================================
// دالة موحدة لعرض SnackBar من أي مكان في التطبيق
// ============================================================================

/// عرض SnackBar باستخدام نظام قائمة الانتظار المحسّن
/// 
/// هذه الدالة تضمن عرض جميع الرسائل بالتسلسل دون تكدس
/// 
/// Parameters:
/// - [message]: النص المراد عرضه
/// - [backgroundColor]: لون الخلفية (افتراضي: أزرق)
/// - [duration]: مدة العرض (افتراضي: 1.5 ثانية)
Future<void> showGlobalSnackBar(
  String message, {
  Color backgroundColor = Colors.blue,
  Duration duration = const Duration(milliseconds: 1500),
}) async {
  try {
    // إضافة الرسالة إلى قائمة الانتظار
    _SnackBarQueueManager().addMessage(
      message: message,
      backgroundColor: backgroundColor,
      duration: duration,
    );

    // انتظار قصير جداً للسماح بالمعالجة
    await Future.delayed(const Duration(milliseconds: 50));
  } catch (e) {
    debugPrint('❌ خطأ في showGlobalSnackBar: $e');
  }
}

// ============================================================================
// دوال إضافية لإدارة قائمة الانتظار
// ============================================================================

/// مسح جميع الرسائل في قائمة الانتظار
void clearSnackBarQueue() {
  _SnackBarQueueManager().clearQueue();
}

/// الحصول على عدد الرسائل في قائمة الانتظار
int getSnackBarQueueLength() {
  return _SnackBarQueueManager().queueLength;
}

/// التحقق من وجود رسائل في قائمة الانتظار
bool hasSnackBarMessages() {
  return _SnackBarQueueManager().hasMessages;
}

/// التحقق من حالة معالجة الرسائل
bool isSnackBarProcessing() {
  return _SnackBarQueueManager().isProcessing;
}

// ============================================================================
// دوال مساعدة سريعة لعرض رسائل ملونة
// ============================================================================

/// عرض رسالة نجاح (خضراء)
Future<void> showSuccessSnackBar(String message) async {
  await showGlobalSnackBar('✅ $message', backgroundColor: Colors.green);
}

/// عرض رسالة خطأ (حمراء)
Future<void> showErrorSnackBar(String message) async {
  await showGlobalSnackBar('❌ $message', backgroundColor: Colors.red);
}

/// عرض رسالة تحذير (برتقالية)
Future<void> showWarningSnackBar(String message) async {
  await showGlobalSnackBar('⚠️ $message', backgroundColor: Colors.orange);
}

/// عرض رسالة معلومات (زرقاء)
Future<void> showInfoSnackBar(String message) async {
  await showGlobalSnackBar('ℹ️ $message', backgroundColor: Colors.blue);
}

/// عرض رسالة تحميل (رمادية مزرقة)
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
  debugPrint('   📬 قائمة SnackBar: ${getSnackBarQueueLength()} رسالة');
  debugPrint('   ⚙️ معالجة SnackBar: ${isSnackBarProcessing() ? "نشط" : "متوقف"}');
  debugPrint('═══════════════════════════════════════════');
}