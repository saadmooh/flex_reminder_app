import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/globals.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';

class SplashScreen extends StatefulWidget {
  final bool? isFirebaseInitialized;
  final bool? isFcmInitialized;
  final String? initializationError;

  const SplashScreen({
    super.key,
    this.isFirebaseInitialized,
    this.isFcmInitialized,
    this.initializationError,
  });

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _hasNavigated = false;
  late AppLocalizations localizations;
  String _statusMessage = 'بدء التطبيق...';
  bool? _hasInternet;

  late AnimationController _logoAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _pulseAnimation;

  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      debugPrint('SplashScreen Message: $message');
    }
    try {
      if (navigatorKey.currentContext != null) {
        final scaffoldMessenger =
            ScaffoldMessenger.of(navigatorKey.currentContext!);
        if (scaffoldMessenger.mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: color ?? Colors.blue,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        } else {
          debugPrint('ScaffoldMessenger غير متاح، تم تجاهل SnackBar: $message');
        }
      } else {
        debugPrint('التطبيق غير نشط، تم تجاهل SnackBar: $message');
      }
    } catch (e) {
      debugPrint('خطأ في عرض الرسالة: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _safeShowMessage('🚀 SplashScreen initialized');
    _safeShowMessage(
        '📋 Firebase: ${widget.isFirebaseInitialized}, FCM: ${widget.isFcmInitialized}');
    if (widget.initializationError != null) {
      _safeShowMessage('⚠️ Init Error: ${widget.initializationError}',
          color: Colors.red);
    }

    _initializeAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppInitialization();
    });
  }

  void _initializeAnimations() {
    _logoAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoAnimationController, curve: Curves.easeIn),
    );
    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoAnimationController, curve: Curves.elasticOut),
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _pulseAnimationController, curve: Curves.easeInOut),
    );

    _logoAnimationController.forward();
    _pulseAnimationController.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    localizations = AppLocalizations.of(context)!;
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  void _updateStatus(String message) {
    if (mounted && !_hasNavigated) {
      setState(() {
        _statusMessage = message;
      });
      _safeShowMessage('📱 Status: $message');
    }
  }

  void _navigateToRoute(String routeName) {
    if (!mounted || _hasNavigated) {
      _safeShowMessage(
          '❌ Navigation blocked: mounted=$mounted, hasNavigated=$_hasNavigated',
          color: Colors.red);
      return;
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      _safeShowMessage('⚠️ Already on route: $routeName, skipping navigation',
          color: Colors.orange);
      _hasNavigated = true;
      return;
    }

    _safeShowMessage('🔄 Navigating from $currentRoute to $routeName');
    _hasNavigated = true;
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  Future<void> _startAppInitialization() async {
    try {
      _showFirebaseStatus();
      await Future.delayed(const Duration(milliseconds: 1200));
      final hasInternet =
          await ConnectivityHelper.checkInternetConnection(verbose: true);
      _hasInternet = hasInternet;
      _updateStatus(hasInternet ? '✅ متصل بالإنترنت' : '⚠️ غير متصل بالإنترنت');

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (hasInternet) {
        await _handleOnlineAuthentication(authProvider);
      } else {
        await _handleOfflineAuthentication(authProvider);
      }
    } catch (e) {
      _safeShowMessage('❌ Critical error in app initialization: $e',
          color: Colors.red);
      _handleInitializationError(e);
    }
  }

  void _showFirebaseStatus() {
    if (widget.isFirebaseInitialized == true) {
      _updateStatus('✅ تم تهيئة Firebase بنجاح');
    } else if (widget.isFirebaseInitialized == false) {
      _updateStatus(widget.initializationError?.contains('اتصال') == true
          ? '⚠️ Firebase: لا يوجد اتصال بالإنترنت'
          : '⚠️ Firebase: غير متاح - العمل بدون اتصال');
    } else {
      _updateStatus('🔄 فحص حالة الخدمات...');
    }
  }

  Future<void> _handleOnlineAuthentication(AuthProvider authProvider) async {
    try {
      _safeShowMessage('🌐 Handling online authentication...');
      _updateStatus('التحقق من حالة تسجيل الدخول...');
      await authProvider.debugStorageState();
      await authProvider.waitForInitialization();

      if (authProvider.isLoading) {
        _safeShowMessage('⚠️ AuthProvider still loading after wait',
            color: Colors.orange);
        _updateStatus('إعادة محاولة فحص البيانات...');
        await authProvider.initializeAuthentication();
      }

      _safeShowMessage(
          '📊 AuthProvider state: isAuthenticated=${authProvider.isAuthenticated}, isOfflineMode=${authProvider.isOfflineMode}, userId=${authProvider.userId}');
      final hasToken = await authProvider.hasStoredToken();

      if (authProvider.isAuthenticated || hasToken) {
        _safeShowMessage('✅ User authenticated or has stored token');
        _updateStatus(authProvider.isOfflineMode
            ? 'تم التحقق من البيانات المحفوظة'
            : 'تم التحقق من حالة المستخدم بنجاح');
        await Future.delayed(const Duration(milliseconds: 800));
        await _handleAuthenticatedUser(authProvider,
            isOffline: authProvider.isOfflineMode);
      } else {
        _safeShowMessage('❌ User not authenticated and no stored token',
            color: Colors.red);
        if (authProvider.errorMessage != null) {
          _safeShowMessage('Auth Error: ${authProvider.errorMessage}',
              color: Colors.red);
        }
        _updateStatus('لم يتم العثور على بيانات تسجيل دخول صحيحة...');
        await Future.delayed(const Duration(milliseconds: 1500));
        _updateStatus('إعادة توجيه لتسجيل الدخول...');
        await Future.delayed(const Duration(milliseconds: 800));
        _navigateToRoute('/auth');
      }
    } catch (e) {
      _safeShowMessage('❌ Error in online authentication: $e',
          color: Colors.red);
      _handleInitializationError(e);
    }
  }

  Future<void> _handleOfflineAuthentication(AuthProvider authProvider) async {
    try {
      _safeShowMessage('📱 Handling offline authentication...');
      _updateStatus('العمل بدون إنترنت - فحص البيانات المحفوظة...');
      await authProvider.debugStorageState();
      final hasToken = await authProvider.hasStoredToken();

      if (!hasToken) {
        _safeShowMessage('❌ No stored token found - cannot work offline',
            color: Colors.red);
        _updateStatus('لا توجد بيانات تسجيل دخول محفوظة');
        await Future.delayed(const Duration(milliseconds: 1000));
        _updateStatus('يجب تسجيل الدخول أولاً - بحاجة لإنترنت');
        await Future.delayed(const Duration(milliseconds: 1000));
        _navigateToRoute('/auth');
        return;
      }

      _updateStatus('تهيئة الوضع بدون إنترنت...');
      await authProvider.initializeOfflineMode();
      await Future.delayed(const Duration(milliseconds: 800));

      if (authProvider.isAuthenticated) {
        _safeShowMessage('✅ User authenticated in offline mode');
        _updateStatus('تم العثور على بيانات تسجيل الدخول المحفوظة');
        await Future.delayed(const Duration(milliseconds: 800));
        await _handleAuthenticatedUser(authProvider, isOffline: true);
      } else {
        _safeShowMessage('❌ Authentication failed in offline mode',
            color: Colors.red);
        final directToken = await authProvider.getToken();
        if (directToken != null && directToken.isNotEmpty) {
          _safeShowMessage(
              '🔧 Found token via direct method, forcing authentication',
              color: Colors.blue);
          authProvider.setAuthenticationStatus(true);
          _updateStatus('تم استرجاع بيانات التسجيل بنجاح');
          await Future.delayed(const Duration(milliseconds: 500));
          await _handleAuthenticatedUser(authProvider, isOffline: true);
        } else {
          _updateStatus('فشل في استرجاع البيانات المحفوظة');
          await Future.delayed(const Duration(milliseconds: 1000));
          _updateStatus('يجب تسجيل الدخول أولاً - بحاجة لإنترنت');
          await Future.delayed(const Duration(milliseconds: 800));
          _navigateToRoute('/auth');
        }
      }
    } catch (e) {
      _safeShowMessage('❌ Error in offline authentication: $e',
          color: Colors.red);
      _updateStatus('خطأ في الوضع بدون إنترنت');
      await Future.delayed(const Duration(milliseconds: 800));
      _navigateToRoute('/auth');
    }
  }

  Future<void> _handleAuthenticatedUser(AuthProvider authProvider,
      {required bool isOffline}) async {
    try {
      if (isOffline) {
        _safeShowMessage(
            '📱 Authenticated user in offline mode - going to reminders');
        try {
          final remindersNotifier =
              Provider.of<RemindersNotifier>(context, listen: false);
          await remindersNotifier.initializeOfflineMode();
          _updateStatus('جاري تحميل التذكيرات المحفوظة...');
        } catch (e) {
          _safeShowMessage('⚠️ RemindersNotifier offline init failed: $e',
              color: Colors.orange);
          _updateStatus('جاري تحضير التذكيرات...');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        _updateStatus('الانتقال إلى التذكيرات...');
        await Future.delayed(const Duration(milliseconds: 300));
        _navigateToRoute('/reminders');
      } else {
        _safeShowMessage(
            '🌐 Authenticated user online - checking subscription');
        _updateStatus('التحقق من حالة الاشتراك...');
        try {
          final subscriptionResponse = await authProvider.checkSubscription();
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
          _safeShowMessage('❌ Subscription check failed: $subscriptionError',
              color: Colors.red);
          if (authProvider.isOfflineMode) {
            _updateStatus('خطأ في الاتصال - استخدام البيانات المحفوظة...');
            await Future.delayed(const Duration(milliseconds: 500));
            _navigateToRoute('/reminders');
          } else {
            _updateStatus('خطأ في فحص الاشتراك - المتابعة للتذكيرات...');
            await Future.delayed(const Duration(milliseconds: 500));
            _navigateToRoute('/reminders');
          }
        }
      }
    } catch (e) {
      _safeShowMessage('❌ Error handling authenticated user: $e',
          color: Colors.red);
      _navigateToRoute('/reminders');
    }
  }

  void _handleInitializationError(dynamic error) {
    _safeShowMessage('🚨 Handling initialization error: $error',
        color: Colors.red);
    _updateStatus('حدث خطأ - جاري المحاولة مرة أخرى...');
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await authProvider.initializeOfflineMode();
        if (authProvider.isAuthenticated) {
          _safeShowMessage(
              '✅ Emergency fallback: User authenticated via AuthProvider');
          _updateStatus('استخدام البيانات المحفوظة...');
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/reminders');
        } else {
          _safeShowMessage(
              '❌ Emergency fallback: No authentication via AuthProvider',
              color: Colors.red);
          _updateStatus('إعادة توجيه لتسجيل الدخول...');
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        }
      } catch (e) {
        _safeShowMessage('❌ Emergency fallback failed: $e', color: Colors.red);
        _updateStatus('خطأ نهائي - الذهاب لتسجيل الدخول');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToRoute('/auth');
      }
    });
  }

  Widget _buildServiceStatusIndicator() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Column(
          children: [
            if (_hasInternet != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: (_hasInternet! ? Colors.green : Colors.orange)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (_hasInternet! ? Colors.green : Colors.orange)
                        .withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasInternet! ? Icons.wifi : Icons.wifi_off,
                      color: _hasInternet! ? Colors.green : Colors.orange,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasInternet! ? 'إنترنت' : 'بدون إنترنت',
                      style: TextStyle(
                        color: _hasInternet! ? Colors.green : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (authProvider.isAuthenticated || authProvider.isOfflineMode)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: (authProvider.isAuthenticated
                          ? Colors.green
                          : Colors.blue)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (authProvider.isAuthenticated
                            ? Colors.green
                            : Colors.blue)
                        .withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      authProvider.isAuthenticated
                          ? (authProvider.isOfflineMode
                              ? Icons.person_outline
                              : Icons.person)
                          : Icons.person_off,
                      color: authProvider.isAuthenticated
                          ? Colors.green
                          : Colors.blue,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      authProvider.isAuthenticated
                          ? (authProvider.isOfflineMode
                              ? 'مسجل (بدون إنترنت)'
                              : 'مسجل دخول')
                          : 'فحص المستخدم',
                      style: TextStyle(
                        color: authProvider.isAuthenticated
                            ? Colors.green
                            : Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (widget.isFirebaseInitialized != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color:
                      (widget.isFirebaseInitialized! ? Colors.blue : Colors.red)
                          .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (widget.isFirebaseInitialized!
                            ? Colors.blue
                            : Colors.red)
                        .withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isFirebaseInitialized!
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      color: widget.isFirebaseInitialized!
                          ? Colors.blue
                          : Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isFirebaseInitialized!
                          ? 'Firebase'
                          : 'Firebase غير متاح',
                      style: TextStyle(
                        color: widget.isFirebaseInitialized!
                            ? Colors.blue
                            : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
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
              AnimatedBuilder(
                animation: _logoAnimationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _logoScaleAnimation.value,
                    child: Opacity(
                      opacity: _logoFadeAnimation.value,
                      child: Image.asset(
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
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
              Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              _buildServiceStatusIndicator(),
              if (widget.initializationError != null)
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'تفاصيل الخطأ: ${widget.initializationError}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
