import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // إضافة هذا للاستخدام SystemNavigator.pop()
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:flex_reminder/services/revenuecat_service.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/services/fcm_service.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  bool _isLoading = true;
  bool _isPremium = false;
  String? _errorMessage;
  bool _hasCheckedSubscription = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    if (_hasCheckedSubscription) {
      if (kDebugMode) {
        debugPrint('SubscriptionManagementScreen: التحقق تم مسبقًا، تجاهل');
      }
      return;
    }
    _hasCheckedSubscription = true;

    if (!isRevenueCatInitialized) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خدمة RevenueCat غير مهيأة';
      });
      _safeShowMessage('خدمة RevenueCat غير مهيأة', color: Colors.red);
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      bool isPremium = await RevenueCatService.instance.isPremiumUser();

      setState(() {
        _isPremium = isPremium;
        _isLoading = false;
      });

      if (isPremium) {
        _navigateToReminders();
      } else {
        await _showPaywall();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ في التحقق من حالة الاشتراك: $e';
      });
      _safeShowMessage('حدث خطأ في التحقق من حالة الاشتراك', color: Colors.red);
    }
  }

  Future<void> _showPaywall() async {
    try {
      PaywallResult? result = await RevenueCatService.instance.showPaywallSafeWithMetadata(
        displayCloseButton: true,
        logMetadata: true, // لعرض metadata في الكونسول
      );

      if (result != null) {
        RevenueCatService.instance.handlePaywallResult(
          result,
          onPurchased: () async {
            // ✅ إرسال التوكن للباك إند عند الشراء
            await FcmService.instance.sendFcmTokenToBackend();
            
            setState(() {
              _isPremium = true;
              _errorMessage = null;
            });
            _navigateToReminders();
          },
          onRestored: () async {
            // ✅ إرسال التوكن للباك إند عند الاستعادة
            await FcmService.instance.sendFcmTokenToBackend();

            setState(() {
              _isPremium = true;
              _errorMessage = null;
            });
            _navigateToReminders();
          },
          onCancelled: () {
            // إغلاق التطبيق عند الإلغاء إذا لم يكن المستخدم مشترك
            _handlePaywallCancelled();
          },
          onError: (error) {
            setState(() {
              _errorMessage = error;
            });
            _safeShowMessage(error, color: Colors.red);
            // إغلاق التطبيق عند حدوث خطأ إذا لم يكن المستخدم مشترك
            _handlePaywallCancelled();
          },
        );
      } else {
        setState(() {
          _errorMessage = 'فشل في عرض خطط الاشتراك';
        });
        _safeShowMessage('فشل في عرض خطط الاشتراك', color: Colors.red);
        // إغلاق التطبيق عند فشل عرض الـ paywall
        _handlePaywallCancelled();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ في عرض الاشتراك: $e';
      });
      _safeShowMessage('حدث خطأ في عرض الاشتراك', color: Colors.red);
      // إغلاق التطبيق عند حدوث خطأ
      _handlePaywallCancelled();
    }
  }

  /// دالة للتعامل مع إلغاء أو إغلاق الـ paywall
  Future<void> _handlePaywallCancelled() async {
    try {
      // التحقق مرة أخيرة من حالة الاشتراك
      bool isPremium = await RevenueCatService.instance.isPremiumUser();
      
      if (isPremium) {
        // إذا كان المستخدم مشترك، انتقل للشاشة الرئيسية
        _navigateToReminders();
      } else {
        // إذا لم يكن المستخدم مشترك، أظهر رسالة وأغلق التطبيق
        _safeShowMessage('يتطلب التطبيق اشتراك مدفوع للاستخدام', color: Colors.orange);
        
        // انتظار قليل لعرض الرسالة
        await Future.delayed(const Duration(seconds: 2));
        
        // إغلاق التطبيق
        _closeApp();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('خطأ في التحقق من الاشتراك عند الإلغاء: $e');
      }
      // في حالة الخطأ، أغلق التطبيق
      _closeApp();
    }
  }

  /// دالة لإغلاق التطبيق
  void _closeApp() {
    try {
      // على Android
      SystemNavigator.pop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('خطأ في إغلاق التطبيق: $e');
      }
      // محاولة بديلة لإغلاق التطبيق
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    }
  }

  void _navigateToReminders() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/reminders',
      (route) => false,
    );
  }

  void _safeShowMessage(String message, {Color? color}) {
    try {
      if (mounted && navigatorKey.currentContext != null) {
        final scaffoldMessenger =
            ScaffoldMessenger.of(navigatorKey.currentContext!);
        if (scaffoldMessenger.mounted) {
          // scaffoldMessenger.showSnackBar(
          //   SnackBar(
          //     content: Text(message),
          //     backgroundColor: color ?? Colors.blue,
          //     duration: const Duration(seconds: 3),
          //     behavior: SnackBarBehavior.floating,
          //     margin: const EdgeInsets.all(10),
          //     shape: RoundedRectangleBorder(
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //   ),
         // );
        }
      }
    } catch (e) {
      debugPrint('خطأ في عرض الرسالة: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // منع المستخدم من الرجوع للخلف بالضغط على زر الرجوع
      onWillPop: () async {
        if (!_isPremium) {
          // إذا لم يكن مشترك، أغلق التطبيق عند محاولة الرجوع
          _closeApp();
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _hasCheckedSubscription = false;
                            });
                            _checkSubscriptionStatus();
                          },
                          child: const Text('إعادة المحاولة'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _closeApp,
                          child: const Text(
                            'إغلاق التطبيق',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}