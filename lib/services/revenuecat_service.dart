import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:flex_reminder/utils/consts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flex_reminder/globals.dart';
import 'dart:convert'; // لاستخدام jsonEncode

class RevenueCatService {
  // Singleton instance
  static final RevenueCatService _instance = RevenueCatService._internal();

  // Factory constructor to return the singleton instance
  factory RevenueCatService() {
    return _instance;
  }

  // Private constructor
  RevenueCatService._internal();

  // Instance variables
  bool _isInitialized = false;
  bool _initializationInProgress = false;
  String? _lastError;
  int _initializationAttempts = 0;
  String? _currentUserId; // إضافة متغير لتتبع المستخدم الحالي

  // Getter for the singleton instance
  static RevenueCatService get instance => _instance;

  // دالة محسنة مع logs مفصلة
  static void _safeShowMessage(String message,
      {Color? color}) {
    // print('🟨 RevenueCatService: $message');

    // if (kDebugMode) {
    //   debugPrint('RevenueCatService Debug: $message');
    // }

    // if (debugOnly && !kDebugMode) return;

    // try {
    //   if (navigatorKey.currentContext != null) {
    //     final scaffoldMessenger =
    //         ScaffoldMessenger.of(navigatorKey.currentContext!);
    //     if (scaffoldMessenger.mounted) {
    //       scaffoldMessenger.showSnackBar(
    //         SnackBar(
    //           content: Text(message),
    //           backgroundColor: color ?? Colors.blue,
    //           duration: Duration(seconds: color == Colors.red ? 4 : 2),
    //           behavior: SnackBarBehavior.floating,
    //           margin: const EdgeInsets.all(10),
    //           shape: RoundedRectangleBorder(
    //             borderRadius: BorderRadius.circular(8),
    //           ),
    //         ),
    //       );
    //     } else {
    //       print('🚫 ScaffoldMessenger غير متاح');
    //     }
    //   } else {
    //     print('🚫 NavigatorKey.currentContext هو null');
    //   }
    // } catch (e) {
    //   print('❌ خطأ في _safeShowMessage: $e');
    // }
  }

  // فحص مفصل لـ API Key
  static bool _isValidApiKey() {
    print('🔍 فحص صحة API Key...');

    try {
      const apiKey = AppConstants.REVENUECAT_API_KEY;
      print('🔑 API Key موجود: ${apiKey.isNotEmpty}');
      print('🔑 API Key length: ${apiKey.length}');

      if (apiKey.isEmpty) {
        _instance._lastError = 'RevenueCat API Key فارغ';
        print('❌ ${_instance._lastError}');
        return false;
      }

      print(
          '🔑 API Key preview: ${apiKey.length > 10 ? '${apiKey.substring(0, 10)}...' : apiKey}');

      if (!apiKey.startsWith('appl_') && !apiKey.startsWith('goog_')) {
        _instance._lastError =
            'صيغة RevenueCat API Key غير صحيحة (يجب أن يبدأ بـ appl_ أو goog_)';
        print('❌ ${_instance._lastError}');
        return false;
      }

      print('✅ API Key صحيح');
      return true;
    } catch (e) {
      _instance._lastError = 'خطأ في فحص API Key: $e';
      print('❌ ${_instance._lastError}');
      return false;
    }
  }

  // دالة لعرض Customer Info في الكونسول بشكل منظم
  Future<void> _logCustomerMetadata() async {
    // try {
    //   Map<String, dynamic> metadata = await _getCustomerMetadata();

    //   _safeShowMessage('📊 === CUSTOMER METADATA ===');
    //   _safeShowMessage('👤 User ID: ${metadata['original_app_user_id']}');
    //   _safeShowMessage('🆔 Current User ID: ${metadata['current_user_id']}');
    //   _safeShowMessage('📅 First Seen: ${metadata['first_seen']}');
    //   _safeShowMessage('💳 Is Premium: ${metadata['is_premium']}');
    //   _safeShowMessage(
    //       '🔄 Active Subscriptions: ${metadata['active_subscriptions']}');
    //   _safeShowMessage(
    //       '📱 All Products: ${metadata['all_purchased_product_ids']}');
    //   _safeShowMessage(
    //       '🎫 Active Entitlements: ${metadata['entitlements_active'].keys.toList()}');
    //   _safeShowMessage('🔗 Management URL: ${metadata['management_url']}');
    //   _safeShowMessage('⚠️ Last Error: ${metadata['last_error']}');
    //   _safeShowMessage(
    //       '🔢 Init Attempts: ${metadata['initialization_attempts']}');
    //   _safeShowMessage('📊 === END METADATA ===');

    //   // طباعة تفصيلية في debug mode
    //   if (kDebugMode) {
    //     print('🔍 DETAILED CUSTOMER METADATA:');
    //     metadata.forEach((key, value) {
    //       print('   $key: $value');
    //     });
    //   }
    // } catch (e) {
    //   _safeShowMessage('❌ Error logging customer metadata: $e');
    // }
  }

  // إضافة دالة لإعادة تعيين الخدمة بالكامل
  Future<void> reset() async {
    _safeShowMessage('🔄 إعادة تعيين RevenueCat Service...');

    try {
      // تسجيل خروج المستخدم الحالي إذا كان موجوداً
      if (_isInitialized && _currentUserId != null) {
        await logoutUser();
      }

      // إعادة تعيين جميع المتغيرات
      _isInitialized = false;
      _initializationInProgress = false;
      _lastError = null;
      _initializationAttempts = 0;
      _currentUserId = null;
      isRevenueCatInitialized = false;

      _safeShowMessage('✅ تم إعادة تعيين RevenueCat Service');
    } catch (e) {
      _safeShowMessage('❌ خطأ في إعادة تعيين RevenueCat Service: $e');
    }
  }

  // تحديث دالة التهيئة لتتعامل مع تغيير المستخدم
  Future<bool> initialize({String? userId}) async {
    _initializationAttempts++;
    _safeShowMessage(
        '🚀 === بدء RevenueCat.initialize() - المحاولة #$_initializationAttempts ===');
    _safeShowMessage('👤 User ID: $userId, Current User: $_currentUserId');

    try {
      // منع التهيئة المتعددة المتزامنة
      if (_initializationInProgress) {
        _safeShowMessage('⏳ تهيئة RevenueCat جارية بالفعل...');
        int attempts = 0;
        while (_initializationInProgress && attempts < 100) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
        _safeShowMessage('⏰ انتهى الانتظار - الحالة النهائية: $_isInitialized');
        return _isInitialized;
      }

      // إذا كان مهيأ بالفعل، ارجع true
      if (_isInitialized) {
        _safeShowMessage('✅ RevenueCat مهيأ مسبقاً');
        return true;
      }

      _initializationInProgress = true;
      _safeShowMessage('🔄 بدء عملية التهيئة...');

      // فحص صحة API Key
      if (!RevenueCatService._isValidApiKey()) {
        print('❌ فشل فحص API Key');
        RevenueCatService._safeShowMessage(
            '❌ خطأ في مفتاح RevenueCat: $_lastError',
            color: Colors.red);
        isRevenueCatInitialized = false;
        return false;
      }

      _safeShowMessage('✅ API Key صحيح');
      RevenueCatService._safeShowMessage('🔄 تهيئة RevenueCat...',
          color: Colors.blue);

      // التهيئة مع timeout
      _safeShowMessage('⚡ استدعاء Purchases.configure...');
      final configurationFuture = Purchases.configure(
        PurchasesConfiguration(AppConstants.REVENUECAT_API_KEY),
      );

      await configurationFuture.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('⏰ انتهت مهلة Purchases.configure');
          throw Exception('انتهت مهلة تهيئة RevenueCat (20 ثانية)');
        },
      );

      _safeShowMessage('✅ تم Purchases.configure بنجاح');

      // إذا كان لدينا userId، سجل دخول المستخدم
      if (userId != null) {
        _safeShowMessage('🔑 تسجيل دخول المستخدم: $userId');
        await Purchases.logIn(userId);
        _currentUserId = userId;
        _safeShowMessage('✅ تم تسجيل دخول المستخدم: $userId');
      }

      // فحص CustomerInfo للتأكد من عمل التهيئة
      _safeShowMessage('🔍 فحص CustomerInfo للتأكد من التهيئة...');
      try {
        final customerInfo = await Purchases.getCustomerInfo().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('انتهت مهلة فحص CustomerInfo');
          },
        );

        _safeShowMessage('✅ CustomerInfo جُلب بنجاح:');
        _safeShowMessage(
            '   - Original App User ID: ${customerInfo.originalAppUserId}');
        print('   - First Seen: ${customerInfo.firstSeen}');
        _safeShowMessage(
            '   - Active Subscriptions: ${customerInfo.activeSubscriptions.length}');
        print(
            '   - All Entitlements: ${customerInfo.entitlements.all.keys.join(', ')}');
      } catch (customerInfoError) {
        _safeShowMessage('❌ خطأ في جلب CustomerInfo: $customerInfoError');
        throw Exception('فشل في التحقق من RevenueCat: $customerInfoError');
      }

      // التهيئة ناجحة
      _isInitialized = true;
      isRevenueCatInitialized = true;
      _lastError = null;

      _safeShowMessage('🎉 تم تهيئة RevenueCat بنجاح!');
      RevenueCatService._safeShowMessage('✅ تم تهيئة RevenueCat بنجاح',
          color: Colors.green);

      return true;
    } catch (e, stackTrace) {
      _lastError = e.toString();
      _safeShowMessage('❌ فشل تهيئة RevenueCat:');
      _safeShowMessage('   Error: $e');
      _safeShowMessage('   Type: ${e.runtimeType}');
      if (kDebugMode) {
        _safeShowMessage('   StackTrace: $stackTrace');
      }

      RevenueCatService._safeShowMessage('❌ فشل تهيئة RevenueCat: $e',
          color: Colors.red);
      _isInitialized = false;
      isRevenueCatInitialized = false;

      return false;
    } finally {
      _initializationInProgress = false;
      _safeShowMessage(
          '🏁 انتهاء RevenueCat.initialize() - النتيجة: $_isInitialized');
    }
  }

  // تحديث دالة تسجيل الدخول لعمل initialize كامل دائمًا
  Future<void> loginUser(String userId) async {
    try {
      _safeShowMessage('🔄 إعادة تهيئة RevenueCat لتسجيل دخول المستخدم: $userId');
      await reset(); // إعادة تعيين الخدمة دائمًا
      await initialize(userId: userId); // تهيئة كاملة مع المستخدم الجديد
      _safeShowMessage('✅ User logged in successfully: $userId', color: Colors.green);
    } catch (e) {
      _safeShowMessage('❌ Error logging in user: $e', color: Colors.red);
    }
  }

  Future<void> logoutUser() async {
    try {
      if (!_isInitialized) return;
      RevenueCatService._safeShowMessage('🔓 Logging out user...',
          color: Colors.blue);
      await Purchases.logOut();
      _currentUserId = null; // مسح المستخدم الحالي
      RevenueCatService._safeShowMessage('✅ User logged out successfully',
          color: Colors.green);
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error logging out user: $e',
          color: Colors.red);
    }
  }

  Future<bool> isPremiumUser() async {
    try {
      if (!_isInitialized) await initialize();
      RevenueCatService._safeShowMessage('🔍 Checking premium status...',
          color: Colors.blue);
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      RevenueCatService._safeShowMessage('customerInfo: $customerInfo');
      bool isPremium = customerInfo.entitlements.active.isNotEmpty;
      RevenueCatService._safeShowMessage('✅ Premium status: $isPremium',
          color: Colors.green);
      return isPremium;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error checking premium status: $e',
          color: Colors.red);
      return false;
    }
  }

  Future<PaywallResult?> showPaywallSafeWithMetadata({
    bool displayCloseButton = true,
    bool logMetadata = true,
  }) async {
    try {
      if (!_isInitialized) {
        bool initialized = await initialize();
        if (!initialized) {
          RevenueCatService._safeShowMessage(
              '❌ Failed to initialize RevenueCat for paywall',
              color: Colors.red);
          return null;
        }
      }

      // عرض metadata قبل إظهار الـ Paywall
      if (logMetadata) {
 //       await _logCustomerMetadata();
      }

      RevenueCatService._safeShowMessage('🎨 Presenting default paywall...',
          color: Colors.blue);

      final result = await RevenueCatUI.presentPaywall(
        displayCloseButton: displayCloseButton,
      );

      // عرض metadata بعد إظهار الـ Paywall
      if (logMetadata) {
        _safeShowMessage('📊 POST-PAYWALL METADATA:');
        await _logCustomerMetadata();
      }

      RevenueCatService._safeShowMessage('✅ Paywall result: $result',
          color: Colors.green);
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PAYWALLS_MISSING_WRONG_ACTIVITY') {
        RevenueCatService._safeShowMessage(
            '❌ خطأ في إعداد Android: MainActivity يجب أن ترث من FlutterFragmentActivity',
            color: Colors.red);
        _showActivityErrorDialog();
      } else {
        RevenueCatService._safeShowMessage('❌ Platform error: ${e.message}',
            color: Colors.red);
      }
      return null;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error presenting paywall: $e',
          color: Colors.red);
      return null;
    }
  }

  Future<PaywallResult?> showPaywallSafe({
    bool displayCloseButton = true,
  }) async {
    try {
      if (!_isInitialized) {
        bool initialized = await initialize();
        if (!initialized) {
          RevenueCatService._safeShowMessage(
              '❌ Failed to initialize RevenueCat for paywall',
              color: Colors.red);
          return null;
        }
      }

      RevenueCatService._safeShowMessage('🎨 Presenting default paywall...',
          color: Colors.blue);

      final result = await RevenueCatUI.presentPaywall(
        displayCloseButton: displayCloseButton,
      );

      RevenueCatService._safeShowMessage('✅ Paywall result: $result',
          color: Colors.green);
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PAYWALLS_MISSING_WRONG_ACTIVITY') {
        RevenueCatService._safeShowMessage(
            '❌ خطأ في إعداد Android: MainActivity يجب أن ترث من FlutterFragmentActivity',
            color: Colors.red);
        _showActivityErrorDialog();
      } else {
        RevenueCatService._safeShowMessage('❌ Platform error: ${e.message}',
            color: Colors.red);
      }
      return null;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error presenting paywall: $e',
          color: Colors.red);
      return null;
    }
  }

  void _showActivityErrorDialog() {
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('خطأ في الإعداد'),
          content: const Text(
              'يوجد مشكلة في إعداد التطبيق. يرجى التواصل مع الدعم الفني.\n\n'
              'رمز الخطأ: PAYWALLS_MISSING_WRONG_ACTIVITY'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    }
  }

  Future<PaywallResult?> showPaywall({
    bool displayCloseButton = true,
  }) async {
    try {
      if (!_isInitialized) {
        bool initialized = await initialize();
        if (!initialized) {
          RevenueCatService._safeShowMessage(
              '❌ Failed to initialize RevenueCat for paywall',
              color: Colors.red);
          return null;
        }
      }
      RevenueCatService._safeShowMessage('🎨 Presenting default paywall...',
          color: Colors.blue);
      final result = await RevenueCatUI.presentPaywall(
        displayCloseButton: displayCloseButton,
      );
      RevenueCatService._safeShowMessage('✅ Paywall result: $result',
          color: Colors.green);
      return result;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error presenting paywall: $e',
          color: Colors.red);
      return null;
    }
  }

  Future<PaywallResult?> showPaywallForOffering(
    String offeringIdentifier, {
    bool displayCloseButton = true,
  }) async {
    try {
      if (!_isInitialized) {
        bool initialized = await initialize();
        if (!initialized) {
          RevenueCatService._safeShowMessage(
              '❌ Failed to initialize RevenueCat for offering paywall',
              color: Colors.red);
          return null;
        }
      }
      RevenueCatService._safeShowMessage(
          '🎨 Presenting paywall for offering: $offeringIdentifier',
          color: Colors.blue);
      Offerings offerings = await Purchases.getOfferings();
      Offering? offering = offerings.getOffering(offeringIdentifier);
      if (offering == null) {
        RevenueCatService._safeShowMessage(
            '❌ Offering not found: $offeringIdentifier',
            color: Colors.red);
        return null;
      }
      final result = await RevenueCatUI.presentPaywall(
        offering: offering,
        displayCloseButton: displayCloseButton,
      );
      RevenueCatService._safeShowMessage(
          '✅ Paywall result for offering: $result',
          color: Colors.green);
      return result;
    } catch (e) {
      RevenueCatService._safeShowMessage(
          '❌ Error presenting paywall for offering: $e',
          color: Colors.red);
      return null;
    }
  }

  Future<bool> openManagementPortal() async {
    try {
      if (!_isInitialized) await initialize();
      RevenueCatService._safeShowMessage(
          '🔗 Attempting to open management portal...',
          color: Colors.blue);
      String? url = await getManagementURL();
      if (url == null) {
        RevenueCatService._safeShowMessage('❌ Management URL is null',
            color: Colors.red);
        return false;
      }
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        RevenueCatService._safeShowMessage('✅ Management portal opened: $url',
            color: Colors.green);
        return true;
      } else {
        RevenueCatService._safeShowMessage('❌ Cannot launch management URL',
            color: Colors.red);
        return false;
      }
    } catch (e) {
      RevenueCatService._safeShowMessage(
          '❌ Error opening management portal: $e',
          color: Colors.red);
      return false;
    }
  }

  Future<String?> getManagementURL() async {
    try {
      if (!_isInitialized) await initialize();
      RevenueCatService._safeShowMessage('🔗 Fetching management URL...',
          color: Colors.blue);
      CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      String? url = customerInfo.managementURL;
      RevenueCatService._safeShowMessage('✅ Management URL fetched: $url',
          color: Colors.green);
      return url;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error fetching management URL: $e',
          color: Colors.red);
      return null;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      if (!_isInitialized) await initialize();
      RevenueCatService._safeShowMessage('🔄 Restoring purchases...',
          color: Colors.blue);
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      bool isPremium = customerInfo.entitlements
              .all[AppConstants.PREMIUM_ENTITLEMENT_ID]?.isActive ==
          true;
      RevenueCatService._safeShowMessage(
          '✅ Restore purchases completed - Premium: $isPremium',
          color: Colors.green);
      return isPremium;
    } catch (e) {
      RevenueCatService._safeShowMessage('❌ Error restoring purchases: $e',
          color: Colors.red);
      return false;
    }
  }

  Future<CustomerInfo?> getCustomerInfo() async {
    return null;
  
    // try {
    //   if (!_isInitialized) await initialize();
    //   RevenueCatService._safeShowMessage('🔍 Fetching customer info...',
    //       color: Colors.blue);
    //   CustomerInfo customerInfo = await Purchases.getCustomerInfo();
    //   RevenueCatService._safeShowMessage('✅ Customer info fetched successfully',
    //       color: Colors.green);
    //   return customerInfo;
    // } catch (e) {
    //   RevenueCatService._safeShowMessage('❌ Error fetching customer info: $e',
    //       color: Colors.red);
    //   return null;
    // }
  }

  Future<Map<String, dynamic>> _getCustomerMetadata() async {
    try {
      if (!_isInitialized) await initialize();

      CustomerInfo customerInfo = await Purchases.getCustomerInfo();

      return {
        'original_app_user_id': customerInfo.originalAppUserId,
        'first_seen': customerInfo.firstSeen,
        'original_purchase_date': customerInfo.originalPurchaseDate?.toString(),
        'latest_expiration_date': customerInfo.latestExpirationDate?.toString(),
        'request_date': customerInfo.requestDate,
        'active_subscriptions': customerInfo.activeSubscriptions.toList(),
        'non_subscription_transactions':
            customerInfo.nonSubscriptionTransactions
                .map((t) => {
                      'product_id': t.productIdentifier,
                      'purchase_date': t.purchaseDate.toString(),
                    })
                .toList(),
        'entitlements_active': customerInfo.entitlements.active
            .map((key, entitlement) => MapEntry(key, {
                  'identifier': entitlement.identifier,
                  'is_active': entitlement.isActive,
                  'will_renew': entitlement.willRenew,
                  'period_type': entitlement.periodType.toString(),
                  'latest_purchase_date':
                      entitlement.latestPurchaseDate.toString(),
                  'expiration_date': entitlement.expirationDate?.toString(),
                  'store': entitlement.store.toString(),
                  'product_identifier': entitlement.productIdentifier,
                })),
        'entitlements_all': customerInfo.entitlements.all
            .map((key, entitlement) => MapEntry(key, {
                  'identifier': entitlement.identifier,
                  'is_active': entitlement.isActive,
                  'will_renew': entitlement.willRenew,
                  'period_type': entitlement.periodType.toString(),
                  'latest_purchase_date':
                      entitlement.latestPurchaseDate.toString(),
                  'expiration_date': entitlement.expirationDate?.toString(),
                  'store': entitlement.store.toString(),
                  'product_identifier': entitlement.productIdentifier,
                })),
        'management_url': customerInfo.managementURL,
        'is_premium': customerInfo.entitlements.active.isNotEmpty,
        'current_user_id': _currentUserId,
        'initialization_attempts': _initializationAttempts,
        'last_error': _lastError,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'current_user_id': _currentUserId,
        'is_initialized': _isInitialized,
        'last_error': _lastError,
      };
    }
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value ?? 'غير متوفر',
              style: TextStyle(
                color: value != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void handlePaywallResult(
    PaywallResult result, {
    VoidCallback? onPurchased,
    VoidCallback? onRestored,
    VoidCallback? onCancelled,
    Function(String)? onError,
  }) {
    switch (result) {
      case PaywallResult.purchased:
        RevenueCatService._safeShowMessage('✅ Purchase completed successfully',
            color: Colors.green);
        onPurchased?.call();
        break;
      case PaywallResult.restored:
        RevenueCatService._safeShowMessage('✅ Purchases restored successfully',
            color: Colors.green);
        onRestored?.call();
        break;
      case PaywallResult.cancelled:
        RevenueCatService._safeShowMessage('🚫 Purchase cancelled by user',
            color: Colors.yellow);
        onCancelled?.call();
        break;
      case PaywallResult.error:
        RevenueCatService._safeShowMessage('❌ Error in purchase process',
            color: Colors.red);
        onError?.call('حدث خطأ في عملية الشراء');
        break;
      case PaywallResult.notPresented:
        RevenueCatService._safeShowMessage('ℹ️ Paywall not presented',
            color: Colors.blue);
        break;
    }
  }
}