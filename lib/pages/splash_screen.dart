import 'package:flutter/material.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'dart:math' as Math;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;
  late AppLocalizations localizations;
  String _statusMessage = 'بدء التطبيق...';
  bool? _hasInternet;

  @override
  void initState() {
    super.initState();
    print('🚀 SplashScreen initialized');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppInitialization();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    localizations = AppLocalizations.of(context)!;
  }

  void _updateStatus(String message) {
    if (mounted && !_hasNavigated) {
      setState(() {
        _statusMessage = message;
      });
      print('📱 Status: $message');
    }
  }

  void _navigateToRoute(String routeName) {
    if (!mounted || _hasNavigated) {
      print(
          '❌ Navigation blocked: mounted=$mounted, hasNavigated=$_hasNavigated');
      return;
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      print('⚠️ Already on route: $routeName, skipping navigation');
      _hasNavigated = true;
      return;
    }

    print('🔄 Navigating from $currentRoute to $routeName');
    _hasNavigated = true;

    Navigator.of(context).pushReplacementNamed(routeName);
  }

  Future<bool> _checkInternetConnection() async {
    try {
      if (_hasInternet != null) {
        return _hasInternet!;
      }

      _updateStatus('فحص الاتصال بالإنترنت...');

      final connectivityResult = await Connectivity().checkConnectivity();
      _hasInternet = connectivityResult != ConnectivityResult.none;

      if (_hasInternet!) {
        _updateStatus('✅ متصل بالإنترنت');
      } else {
        _updateStatus('❌ غير متصل بالإنترنت');
      }

      return _hasInternet!;
    } catch (e) {
      print('❌ Error checking internet connection: $e');
      _hasInternet = false;
      _updateStatus('❌ خطأ في فحص الاتصال');
      return false;
    }
  }

  Future<void> _startAppInitialization() async {
    try {
      // تأخير بسيط لعرض الشعار
      await Future.delayed(const Duration(milliseconds: 800));

      // فحص الاتصال بالإنترنت
      final hasInternet = await _checkInternetConnection();

      // الحصول على AuthProvider
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!hasInternet) {
        // وضع عدم الاتصال
        await _handleOfflineMode(authProvider);
      } else {
        // وضع الاتصال العادي
        await _handleOnlineMode(authProvider);
      }
    } catch (e) {
      print('❌ Critical error in app initialization: $e');
      _handleInitializationError(e);
    }
  }

  Future<void> _handleOfflineMode(AuthProvider authProvider) async {
    try {
      print('📱 Handling offline mode...');
      _updateStatus('العمل بدون إنترنت - فحص البيانات المحفوظة...');

      await Future.delayed(const Duration(milliseconds: 500));

      final token = await authProvider.getToken();

      if (token != null && token.isNotEmpty) {
        print('✅ Token found in offline mode');
        _updateStatus('تم العثور على بيانات تسجيل الدخول');

        await Future.delayed(const Duration(milliseconds: 500));

        // تهيئة وضع عدم الاتصال
        try {
          await authProvider.initializeOfflineMode();
          _updateStatus('تحضير البيانات للعمل بدون إنترنت...');

          await Future.delayed(const Duration(milliseconds: 500));

          // تهيئة RemindersNotifier إذا كان متاحاً
          try {
            final remindersNotifier =
                Provider.of<RemindersNotifier>(context, listen: false);
            await remindersNotifier.initializeOfflineMode();
          } catch (e) {
            print('⚠️ RemindersNotifier offline init failed: $e');
            // المتابعة حتى لو فشل
          }
        } catch (e) {
          print('⚠️ AuthProvider offline init failed: $e');
          // المتابعة حتى لو فشل
        }

        _updateStatus('الانتقال إلى التذكيرات...');
        await Future.delayed(const Duration(milliseconds: 300));
        _navigateToRoute('/reminders');
      } else {
        print('❌ No token found in offline mode');
        _updateStatus('لا توجد بيانات تسجيل دخول محفوظة');
        await Future.delayed(const Duration(milliseconds: 800));
        _navigateToRoute('/auth');
      }
    } catch (e) {
      print('❌ Error in offline mode: $e');
      _updateStatus('خطأ في الوضع بدون إنترنت');
      await Future.delayed(const Duration(milliseconds: 500));
      _navigateToRoute('/auth');
    }
  }

  Future<void> _handleOnlineMode(AuthProvider authProvider) async {
    try {
      print('🌐 Handling online mode...');
      _updateStatus('التحقق من حالة تسجيل الدخول...');

      // انتظار تهيئة AuthProvider
      int waitCount = 0;
      while (authProvider.isLoading && waitCount < 30) {
        await Future.delayed(const Duration(milliseconds: 200));
        waitCount++;
      }

      if (authProvider.isLoading) {
        print(
            '⚠️ AuthProvider still loading after 6 seconds, proceeding anyway');
      }

      if (!authProvider.isAuthenticated) {
        print('❌ User not authenticated');
        _updateStatus('إعادة توجيه لتسجيل الدخول...');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToRoute('/auth');
        return;
      }

      // فحص الاشتراك
      _updateStatus('التحقق من حالة الاشتراك...');

      try {
        final subscriptionResponse = await authProvider.checkSubscription();

        // حفظ حالة الاشتراك محلياً للاستخدام في وضع عدم الاتصال
        if (subscriptionResponse['subscribed'] == true) {
          await authProvider.saveSubscriptionStatusLocally(true);
        }

        if (subscriptionResponse['subscribed'] == true) {
          if (subscriptionResponse['redirect_to_subscription'] == true) {
            _updateStatus('إعادة توجيه لإدارة الاشتراك...');
            await Future.delayed(const Duration(milliseconds: 500));
            _navigateToRoute('/subscription_management');
          } else {
            _updateStatus('الانتقال إلى التذكيرات...');
            await Future.delayed(const Duration(milliseconds: 500));
            _navigateToRoute('/reminders');
          }
        } else {
          _updateStatus('انتهت صلاحية الاشتراك - إعادة توجيه...');
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        }
      } catch (subscriptionError) {
        print('❌ Subscription check failed: $subscriptionError');
        _updateStatus('خطأ في فحص الاشتراك - المتابعة للتذكيرات...');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToRoute('/reminders');
      }
    } catch (e) {
      print('❌ Error in online mode: $e');
      _handleInitializationError(e);
    }
  }

  void _handleInitializationError(dynamic error) {
    print('🚨 Handling initialization error: $error');
    _updateStatus('حدث خطأ - جاري المحاولة مرة أخرى...');

    // محاولة الرجوع للوضع بدون اتصال
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final token = await authProvider.getToken();

        if (token != null && token.isNotEmpty) {
          _updateStatus('استخدام البيانات المحفوظة...');
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/reminders');
        } else {
          _updateStatus('إعادة توجيه لتسجيل الدخول...');
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        }
      } catch (e) {
        print('❌ Final fallback failed: $e');
        _navigateToRoute('/auth');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // شعار التطبيق
              Image.asset(
                'assets/logo.png',
                width: 150,
                height: 150,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.access_time,
                      size: 80,
                      color: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),

              // مؤشر التحميل
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              const SizedBox(height: 30),

              // رسالة الحالة
              Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 30),

              // مؤشر حالة الاتصال
              if (_hasInternet != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (_hasInternet! ? Colors.green : Colors.orange)
                        .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_hasInternet! ? Colors.green : Colors.orange)
                          .withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasInternet! ? Icons.wifi : Icons.wifi_off,
                        color: _hasInternet! ? Colors.green : Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _hasInternet! ? 'متصل بالإنترنت' : 'العمل بدون إنترنت',
                        style: TextStyle(
                          color: _hasInternet! ? Colors.green : Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
