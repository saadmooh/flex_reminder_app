import 'dart:convert';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flex_reminder/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/services/reminders_service.dart';
import 'package:flex_reminder/services/subscription_manager.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flex_reminder/utils/consts.dart';
import 'package:http/http.dart' as http;


// ============================================================================
// دالة تأكيد عامة للـ dispatcher (مستقلة)
// ============================================================================
Future<void> _sendDispatcherConfirmation(
  String taskType,
  String status,
  Map<String, dynamic>? data,
  String? error,
) async {
  try {
    final uri = Uri.parse('${AppConstants.API_BASE_URL}/test-fcm-background');
    
    final requestBody = {
      'triggered_at': DateTime.now().toIso8601String(),
      'source': 'workmanager_dispatcher',
      'task_type': taskType,
      'status': status,
      'data': data,
      'error': error,
    };
    
    await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Password': AppConstants.API_PASSWORD,
        'X-FCM-Background-Test': 'true',
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 5));
    
    debugPrint('📤 Dispatcher confirmation: $taskType = $status');
  } catch (e) {
    debugPrint('⚠️ Failed to send dispatcher confirmation: $e');
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // التهيئة الأساسية فقط
            await _sendDispatcherConfirmation(task ?? 'unknown', 'started', inputData, null);

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      debugPrint('🎯 Background task started: $task');

      switch (task) {
        case 'processFcmPayload':
          await _handleFcmPayload();
          break;
          
        case 'followUpNotification':
          await _handleFollowUpNotification(inputData);
          break;
          
        case 'markReminderAsRead':
          await _handleMarkReminderAsRead(inputData);
          break;
          
        default:
          debugPrint('⚠️ Unknown task: $task');
          return false;
      }
       // 2. تأكيد النجاح
      await _sendDispatcherConfirmation(task ?? 'unknown', 'completed', inputData, null);
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Background task error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });
}

// معالج FCM من main.dart
Future<void> _handleFcmPayload() async {
  try {
    await _sendDispatcherConfirmation('processFcmPayload', 'fetching_data', null, null);
    
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pending_fcm_payload');
    
    if (raw == null) {
      await _sendDispatcherConfirmation('processFcmPayload', 'no_data', null, null);
      return;
    }

    final data = jsonDecode(raw);
    final type = data['type'];
    
    await _sendDispatcherConfirmation('processFcmPayload', 'processing_type_$type', data, null);

    switch (type) {
      case 'reminder_update':
        await RemindersService.instance.handleReminderUpdateInBackground(data);
        break;
        
      case 'subscription_update':
        await SubscriptionManager().handleSubscriptionUpdateNotification(data);
        break;
    }

    await prefs.remove('pending_fcm_payload');
    await _sendDispatcherConfirmation('processFcmPayload', 'completed', data, null);
  } catch (e) {
    await _sendDispatcherConfirmation('processFcmPayload', 'error', null, e.toString());
    rethrow;
  }
}



// معالج المتابعة من notification_service.dart
Future<void> _handleFollowUpNotification(Map<String, dynamic>? inputData) async {
  try {
    await _sendDispatcherConfirmation('followUpNotification', 'started', inputData, null);
    
    if (inputData == null) {
      await _sendDispatcherConfirmation('followUpNotification', 'null_input', null, null);
      return;
    }
    
    final String title = inputData['title'] ?? 'تذكير متابعة';
    final String body = inputData['body'] ?? 'هذا تذكير متابعة!';
    final String reminderId = inputData['reminderId']?.toString() ?? '';
    final String url = inputData['url'] ?? '';
    final String importance = inputData['importance'] ?? '';

    try {
      await _sendDispatcherConfirmation('followUpNotification', 'calling_api', inputData, null);
      
      final rescheduleResult = await RemindersService.instance.reschedulePost(url, importance);
      
      await _sendDispatcherConfirmation('followUpNotification', 'api_success', rescheduleResult, null);

      if (rescheduleResult.containsKey('post') &&
          rescheduleResult['post'].containsKey('next_reminder_time')) {
        final String newTime = rescheduleResult['post']['next_reminder_time'];
        
        await _sendDispatcherConfirmation('followUpNotification', 'scheduling_notification', {
          'newTime': newTime,
          ...inputData
        }, null);

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            channelKey: 'scheduled_channel',
            title: '🔄 $title - تم إعادة الجدولة',
            body: 'تم إعادة جدولة التذكير للوقت: $newTime',
            payload: {
              'id': reminderId,
              'url': url,
              'importance': importance,
              'rescheduled': 'true',
            }.cast<String, String>(),
          ),
        );
        
        await _sendDispatcherConfirmation('followUpNotification', 'notification_created', inputData, null);
      }
    } catch (e) {
      await _sendDispatcherConfirmation('followUpNotification', 'api_error', inputData, e.toString());
      
      // جدولة إعادة المحاولة
      await Workmanager().registerOneOffTask(
        'retry_followUp_$reminderId',
        'followUpNotification',
        initialDelay: const Duration(minutes: 30),
        inputData: inputData,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: 'scheduled_channel',
          title: '⚠️ $title - خطأ',
          body: 'سيتم المحاولة مجدداً بعد 30 دقيقة.',
          payload: inputData != null ? Map<String, String>.from(inputData.cast<String, String?>()) : null,
        ),
      );
    }
  } catch (e) {
    await _sendDispatcherConfirmation('followUpNotification', 'error', inputData, e.toString());
  }
}


// معالج التحديث من notification_service.dart
Future<void> _handleMarkReminderAsRead(Map<String, dynamic>? inputData) async {
  try {
    await _sendDispatcherConfirmation('markReminderAsRead', 'started', inputData, null);
    
    if (inputData == null) {
      await _sendDispatcherConfirmation('markReminderAsRead', 'null_input', null, null);
      return;
    }
    
    final String url = inputData['url'] ?? '';
    final int reminderId = inputData['reminderId'] ?? 0;
    final bool wasOpened = inputData['wasOpened'] ?? true;

    try {
      await _sendDispatcherConfirmation('markReminderAsRead', 'calling_api', inputData, null);
      
      await RemindersService.instance.updateStats(url, wasOpened);
      
      await _sendDispatcherConfirmation('markReminderAsRead', 'completed', inputData, null);
    } catch (e) {
      await _sendDispatcherConfirmation('markReminderAsRead', 'api_error', inputData, e.toString());
      
      // جدولة إعادة المحاولة
      await Workmanager().registerOneOffTask(
        'retry_markRead_$reminderId',
        'markReminderAsRead',
        initialDelay: const Duration(seconds: 30),
        inputData: inputData,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
  } catch (e) {
    await _sendDispatcherConfirmation('markReminderAsRead', 'error', inputData, e.toString());
  }
}