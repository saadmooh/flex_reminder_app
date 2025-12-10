import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/services/revenuecat_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flex_reminder/globals.dart' as globals;

class SubscriptionManager {
  // ✅ إزالة context من المتغيرات
  static final SubscriptionManager _instance = SubscriptionManager._internal();
  
  factory SubscriptionManager() => _instance;
  SubscriptionManager._internal();

  // مفاتيح التخزين
  static const String _subscriptionStatusKey = 'subscription_status';
  static const String _subscriptionUserIdKey = 'subscription_user_id';
  static const String _subscriptionEventTypeKey = 'subscription_event_type';
  static const String _subscriptionTimestampKey = 'subscription_timestamp';

  // متغيرات الحالة المحلية
  bool _subscriptionStatus = false;
  String _subscriptionUserId = '';
  String _subscriptionEventType = '';
  int _subscriptionTimestamp = 0;

  // Getters للوصول إلى المتغيرات
  bool get subscriptionStatus => _subscriptionStatus;
  String get subscriptionUserId => _subscriptionUserId;
  String get subscriptionEventType => _subscriptionEventType;
  int get subscriptionTimestamp => _subscriptionTimestamp;

  Future<Map<String, dynamic>> checkSubscription({String? userId}) async {
    try {
      await loadSubscriptionData();
      
      if (_subscriptionUserId.isNotEmpty) {
        if (kDebugMode) {
          print('SubscriptionManager: Using saved subscription data');
          print('  Status: $_subscriptionStatus');
          print('  User ID: $_subscriptionUserId');
          print('  Event Type: $_subscriptionEventType');
          print('  Last update: ${DateTime.fromMillisecondsSinceEpoch(_subscriptionTimestamp)}');
        }
        
        return {
          'subscribed': _subscriptionStatus,
          'userId': _subscriptionUserId,
          'eventType': _subscriptionEventType,
          'message': _subscriptionStatus ? 'Premium active (saved data)' : 'No premium subscription (saved data)',
          'source': 'saved_data',
        };
      }
      
      if (userId != null) {
        if (kDebugMode) {
          print('SubscriptionManager: No saved data, checking RevenueCat for user: $userId');
        }
        
        bool initialized = await RevenueCatService.instance.initialize(userId: userId)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                if (kDebugMode) {
                  print('SubscriptionManager: RevenueCat init timeout');
                }
                return false;
              },
            );
        
        if (initialized) {
          bool isPremium = await RevenueCatService.instance.isPremiumUser();
          
          await updateSubscriptionVariables(
            userId: userId,
            eventType: 'REVENUECAT_CHECK',
            status: isPremium ? 'active' : 'inactive',
          );
          
          return {
            'subscribed': _subscriptionStatus,
            'userId': _subscriptionUserId,
            'eventType': _subscriptionEventType,
            'message': _subscriptionStatus ? 'Premium active (RevenueCat)' : 'No premium subscription (RevenueCat)',
            'source': 'revenuecat',
          };
        }
      }
      
      return {
        'subscribed': false,
        'userId': '',
        'eventType': '',
        'message': 'Unable to check subscription status',
        'source': 'error',
      };
      
    } catch (e) {
      if (kDebugMode) {
        print('Error checking subscription: $e');
      }
      return {
        'subscribed': false,
        'userId': '',
        'eventType': '',
        'message': 'Error checking subscription: $e',
        'source': 'error',
      };
    }
  }

  Future<void> showPaywall({String? userId}) async {
    try {
      if (userId != null) {
        if (kDebugMode) {
          print('SubscriptionManager: Ensuring RevenueCat is initialized for paywall - user: $userId');
        }
        bool initialized = await RevenueCatService.instance.initialize(userId: userId);
        if (!initialized) {
          if (kDebugMode) {
            print('SubscriptionManager: RevenueCat initialization failed - cannot show paywall');
          }
          return;
        }
      }
      
      await RevenueCatService.instance.showPaywall();
    } catch (e) {
      if (kDebugMode) {
        print('Error showing paywall: $e');
      }
    }
  }

  Future<void> logoutUser() async {
    try {
      if (kDebugMode) {
        print('SubscriptionManager: Logging out user from RevenueCat');
      }
      
      await clearSubscriptionData();
      await RevenueCatService.instance.logoutUser();
      
      if (kDebugMode) {
        print('SubscriptionManager: User logout completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in SubscriptionManager logout: $e');
      }
    }
  }

  Future<bool> restorePurchases({String? userId}) async {
    try {
      if (userId != null) {
        bool initialized = await RevenueCatService.instance.initialize(userId: userId);
        if (!initialized) {
          if (kDebugMode) {
            print('SubscriptionManager: RevenueCat initialization failed - cannot restore purchases');
          }
          return false;
        }
      }
      
      bool restored = await RevenueCatService.instance.restorePurchases();
      
      if (userId != null) {
        await updateSubscriptionVariables(
          userId: userId,
          eventType: 'RESTORE_PURCHASE',
          status: restored ? 'active' : 'inactive',
        );
      }
      
      return restored;
    } catch (e) {
      if (kDebugMode) {
        print('Error restoring purchases: $e');
      }
      return false;
    }
  }

  // ============================================================================
  // الدالة الرئيسية لتحديث متغيرات الاشتراك
  // ============================================================================
  
  Future<void> updateSubscriptionVariables({
    required String userId,
    required String eventType,
    required String status,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // تحديث المتغيرات المحلية
      _subscriptionUserId = userId;
      _subscriptionEventType = eventType;
      _subscriptionStatus = status.toLowerCase() == 'active';
      _subscriptionTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      // حفظ في التخزين المحلي
      await prefs.setString(_subscriptionUserIdKey, _subscriptionUserId);
      await prefs.setString(_subscriptionEventTypeKey, _subscriptionEventType);
      await prefs.setBool(_subscriptionStatusKey, _subscriptionStatus);
      await prefs.setInt(_subscriptionTimestampKey, _subscriptionTimestamp);
      
      // ✅ تحديث globals من خلال إعادة تحميل البيانات
      await globals.loadSubscriptionData();
      
      if (kDebugMode) {
        print('SubscriptionManager: Variables updated successfully');
        print('  User ID: $_subscriptionUserId');
        print('  Event Type: $_subscriptionEventType');
        print('  Status: ${_subscriptionStatus ? "active" : "inactive"}');
        print('  Timestamp: $_subscriptionTimestamp');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('Error updating subscription variables: $e');
      }
    }
  }

  // ============================================================================
  // معالجة إشعارات FCM
  // ============================================================================
  
  Future<void> handleSubscriptionUpdateNotification(Map<String, dynamic> data) async {
    try {
      final userId = data['title']?.toString() ?? '';
      final subscriptionStatus = data['body']?.toString() ?? '';
      final type = data['type']?.toString() ?? '';
      
      if (kDebugMode) {
        print('SubscriptionManager: Handling FCM subscription update');
        print('  User ID (from title): $userId');
        print('  Subscription Status (from body): $subscriptionStatus');
        print('  Type: $type');
      }
      
      if (userId.isEmpty) {
        if (kDebugMode) {
          print('SubscriptionManager: Empty user ID, ignoring message');
        }
        return;
      }
      
      String status = subscriptionStatus.toLowerCase() == 'true' ? 'active' : 'inactive';
      
      await updateSubscriptionVariables(
        userId: userId,
        eventType: type,
        status: status,
      );
      
      _showSubscriptionNotification(userId, status);
      
    } catch (e) {
      if (kDebugMode) {
        print('Error handling subscription update notification: $e');
      }
    }
  }
  
  void _showSubscriptionNotification(String userId, String status) {
    String message = status == 'active' 
        ? 'تم تفعيل اشتراكك بنجاح' 
        : 'تم إلغاء اشتراكك';
    
    globals.showGlobalSnackBar(
      'اشتراك المستخدم $userId: $message',
      backgroundColor: status == 'active' ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 3),
    );
  }
  
  Future<void> loadSubscriptionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _subscriptionStatus = prefs.getBool(_subscriptionStatusKey) ?? false;
      _subscriptionUserId = prefs.getString(_subscriptionUserIdKey) ?? '';
      _subscriptionEventType = prefs.getString(_subscriptionEventTypeKey) ?? '';
      _subscriptionTimestamp = prefs.getInt(_subscriptionTimestampKey) ?? 0;
      
      if (kDebugMode) {
        print('SubscriptionManager: Loaded subscription data');
        print('  User ID: $_subscriptionUserId');
        print('  Event Type: $_subscriptionEventType');
        print('  Status: ${_subscriptionStatus ? "active" : "inactive"}');
        print('  Timestamp: $_subscriptionTimestamp');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading subscription data: $e');
      }
    }
  }
  
  Future<void> clearSubscriptionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_subscriptionStatusKey);
      await prefs.remove(_subscriptionUserIdKey);
      await prefs.remove(_subscriptionEventTypeKey);
      await prefs.remove(_subscriptionTimestampKey);
      
      _subscriptionStatus = false;
      _subscriptionUserId = '';
      _subscriptionEventType = '';
      _subscriptionTimestamp = 0;
      
      // ✅ تحديث globals من خلال إعادة تحميل البيانات (ستكون فارغة)
      await globals.loadSubscriptionData();
      
      if (kDebugMode) {
        print('SubscriptionManager: Subscription data cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing subscription data: $e');
      }
    }
  }
  
  bool hasSubscriptionData() {
    return _subscriptionUserId.isNotEmpty && _subscriptionTimestamp > 0;
  }
  
  bool isSubscriptionActive() {
    return _subscriptionStatus;
  }
  
  Map<String, dynamic> getSubscriptionDataMap() {
    return {
      'userId': _subscriptionUserId,
      'eventType': _subscriptionEventType,
      'isActive': _subscriptionStatus,
      'timestamp': _subscriptionTimestamp,
    };
  }
  
  String getEventDescription(String eventType) {
    switch (eventType.toLowerCase()) {
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
  
  Future<void> reset() async {
    try {
      if (kDebugMode) {
        print('SubscriptionManager: Resetting...');
      }
      
      await clearSubscriptionData();
      
      if (kDebugMode) {
        print('SubscriptionManager: Reset completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error resetting SubscriptionManager: $e');
      }
    }
  }
}