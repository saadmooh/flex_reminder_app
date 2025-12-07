import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/services/revenuecat_service.dart';
import 'package:flutter/foundation.dart';

class SubscriptionManager {
  final BuildContext context;

  SubscriptionManager(this.context);

  Future<Map<String, dynamic>> checkSubscription({String? userId}) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    if (userId != null) {
      if (kDebugMode) {
        print('SubscriptionManager: Checking subscription for user: $userId');
      }
      
      // ✅ محاولة التهيئة بدون انتظار طويل
      bool initialized = await RevenueCatService.instance.initialize(userId: userId)
          .timeout(
            const Duration(seconds: 8), // ✅ timeout قصير
            onTimeout: () {
              if (kDebugMode) {
                print('SubscriptionManager: RevenueCat init timeout, using offline data');
              }
              return false;
            },
          );
      
      if (!initialized) {
        return await _checkSubscriptionOffline();
      }

      bool isPremium = await RevenueCatService.instance.isPremiumUser();
      await _saveSubscriptionStatusLocally(isPremium, userId);
      
      return {
        'subscribed': isPremium,
        'message': isPremium ? 'Premium active' : 'No premium subscription',
      };
    } else {
      return await _checkSubscriptionOffline();
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error checking subscription: $e');
    }
    return await _checkSubscriptionOffline();
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
      
      await _clearLocalSubscriptionStatus();
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
      await _saveSubscriptionStatusLocally(restored, userId);
      return restored;
    } catch (e) {
      if (kDebugMode) {
        print('Error restoring purchases: $e');
      }
      return false;
    }
  }

  Future<void> _saveSubscriptionStatusLocally(bool isPremium, String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (userId != null) {
        await prefs.setBool('last_subscription_status_$userId', isPremium);
        await prefs.setString('last_user_id', userId);
        await prefs.setInt('subscription_check_timestamp', DateTime.now().millisecondsSinceEpoch);
      }
      
      if (kDebugMode) {
        print('SubscriptionManager: Subscription status saved locally for user $userId: $isPremium');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving subscription status: $e');
      }
    }
  }

  Future<void> _clearLocalSubscriptionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('last_user_id');
      if (userId != null) {
        await prefs.remove('last_subscription_status_$userId');
        await prefs.remove('last_user_id');
        await prefs.remove('subscription_check_timestamp');
      }
      
      if (kDebugMode) {
        print('SubscriptionManager: Local subscription status cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing subscription status: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _checkSubscriptionOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('last_user_id');
      bool isPremium = false;
      if (userId != null) {
        isPremium = prefs.getBool('last_subscription_status_$userId') ?? false;
      }
      
      if (kDebugMode) {
        print('SubscriptionManager: Offline subscription check for user $userId - Premium: $isPremium');
      }
      
      return {
        'subscribed': isPremium,
        'message': isPremium ? 'Premium active (offline)' : 'No premium subscription (offline)',
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error checking subscription offline: $e');
      }
      return {
        'subscribed': false,
        'message': 'Failed to check subscription offline: $e',
      };
    }
  }

  Future<bool> validateSubscriptionStatus() async {
    try {
      final result = await checkSubscription();
      return result['subscribed'] == true;
    } catch (e) {
      if (kDebugMode) {
        print('Error validating subscription status: $e');
      }
      return false;
    }
  }

  Future<void> reset() async {
    try {
      if (kDebugMode) {
        print('SubscriptionManager: Resetting...');
      }
      
      await _clearLocalSubscriptionStatus();
      
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