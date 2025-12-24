import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/services/subscription_manager.dart';
import 'package:flex_reminder/services/navigation_service.dart';
import 'package:flex_reminder/services/authentication_service.dart';
import 'package:flex_reminder/services/fcm_service.dart';
import 'package:flex_reminder/globals.dart'; 
class SplashMessage {
  final String message;
  final Color? color;
  final DateTime timestamp;
  final bool isDebug;

  SplashMessage({
    required this.message,
    this.color,
    required this.timestamp,
    required this.isDebug,
  });
}

class SplashScreen extends StatefulWidget {
  final bool? isFirebaseInitialized;
  final bool? isFcmInitialized;
  final bool? isRevenueCatInitialized;
  final String? initializationError;

  static List<SplashMessage> messages = [];
  static ValueNotifier<List<SplashMessage>> messagesNotifier =
      ValueNotifier([]);

  static void addMessage(SplashMessage message) {
    _safeShowMessage(message.message, color: message.color);
    messages.add(message);
    if (messages.length > 50) {
      messages.removeRange(0, messages.length - 50);
    }
    messagesNotifier.value = List.from(messages);
  }

  static void _safeShowMessage(String message, {Color? color}) {
    // if (kDebugMode) {
    //   debugPrint('SplashScreen Message: $message');
    // }
  }

  const SplashScreen({
    super.key,
    this.isFirebaseInitialized,
    this.isFcmInitialized,
    this.isRevenueCatInitialized,
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
  bool _showNoInternetUI = false;

  late AnimationController _logoAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _pulseAnimation;

  void _safeShowMessage(String message, {Color? color}) {
    SplashScreen._safeShowMessage(message, color: color);
  }

  @override
  void initState() {
    super.initState();
    _safeShowMessage('🚀 SplashScreen initialized');
    _safeShowMessage(
        '📋 Firebase: ${widget.isFirebaseInitialized}, FCM: ${widget.isFcmInitialized}, RevenueCat: ${widget.isRevenueCatInitialized}');
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
    _pulseAnimationController.dispose;
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
    NavigationService.navigateTo(context, routeName);
  }

  Future<void> _startAppInitialization() async {
    try {
      _showFirebaseStatus();
      //await Future.delayed(const Duration(milliseconds: 1200));

      final hasInternet =
          await ConnectivityHelper.checkInternetConnection(verbose: true);
      _hasInternet = hasInternet;

      if (!hasInternet) {
        setState(() {
          _showNoInternetUI = true;
          _statusMessage = 'لا يوجد اتصال بالإنترنت';
        });
        return;
      }

      _updateStatus('متصل بالإنترنت');

      final authProvider = AuthProvider.instance;
      await _handleOnlineAuthentication(authProvider);
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
      await authProvider.initializeAuthentication();

      if (authProvider.isLoading) {
        _safeShowMessage('⚠️ AuthProvider still loading after initialization',
            color: Colors.orange);
        _updateStatus('إعادة محاولة فحص البيانات...');
        await authProvider.initializeAuthentication();
      }

      _safeShowMessage(
          '📊 AuthProvider state: isAuthenticated=${authProvider.isAuthenticated}, isOfflineMode=${authProvider.isOfflineMode}, userId=${authProvider.userId}');

      final token = await authProvider.getToken();
      final hasToken = token != null && token.isNotEmpty;

      if (authProvider.isAuthenticated || hasToken) {
        _safeShowMessage('✅ User authenticated or has stored token');
        _updateStatus(authProvider.isOfflineMode
            ? 'تم التحقق من البيانات المحفوظة'
            : 'تم التحقق من حالة المستخدم بنجاح');
        //await Future.delayed(const Duration(milliseconds: 800));
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
        //await Future.delayed(const Duration(milliseconds: 1500));
        _updateStatus('إعادة توجيه لتسجيل الدخول...');
        //await Future.delayed(const Duration(milliseconds: 800));
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
      final token = await authProvider.getToken();
      final hasToken = token != null && token.isNotEmpty;

      if (!hasToken) {
        _safeShowMessage('❌ No stored token found - cannot work offline',
            color: Colors.red);
        _updateStatus('لا توجد بيانات تسجيل دخول محفوظة');
        //await Future.delayed(const Duration(milliseconds: 1000));
        _updateStatus('يجب تسجيل الدخول أولاً - بحاجة لإنترنت');
        //await Future.delayed(const Duration(milliseconds: 1000));
        _navigateToRoute('/auth');
        return;
      }

      _updateStatus('تهيئة الوضع بدون إنترنت...');
      await authProvider.initializeAuthentication();
      //await Future.delayed(const Duration(milliseconds: 800));

      if (authProvider.isAuthenticated) {
        _safeShowMessage('✅ User authenticated in offline mode');
        _updateStatus('تم العثور على بيانات تسجيل الدخول المحفوظة');
        //await Future.delayed(const Duration(milliseconds: 800));
        await _handleAuthenticatedUser(authProvider, isOffline: true);
      } else {
        _safeShowMessage('❌ Authentication failed in offline mode',
            color: Colors.red);
        _updateStatus('فشل في استرجاع البيانات المحفوظة');
        //await Future.delayed(const Duration(milliseconds: 1000));
        _updateStatus('يجب تسجيل الدخول أولاً - بحاجة لإنترنت');
        //await Future.delayed(const Duration(milliseconds: 800));
        _navigateToRoute('/auth');
      }
    } catch (e) {
      _safeShowMessage('❌ Error in offline authentication: $e',
          color: Colors.red);
      _updateStatus('خطأ في الوضع بدون إنترنت');
      //await Future.delayed(const Duration(milliseconds: 800));
      _navigateToRoute('/auth');
    }
  }

  // في دالة _handleAuthenticatedUser
Future<void> _handleAuthenticatedUser(AuthProvider authProvider, {required bool isOffline}) async {
  try {
    final subscriptionManager = SubscriptionManager();
    if (isOffline) {
      _safeShowMessage('📱 Authenticated user in offline mode - going to reminders');
      try {
        final remindersNotifier = RemindersNotifier.instance;
        await remindersNotifier.initializeOfflineMode();
        _updateStatus('جاري تحميل التذكيرات المحفوظة...');
      } catch (e) {
        _safeShowMessage('⚠️ RemindersNotifier offline init failed: $e', color: Colors.orange);
        _updateStatus('جاري تحضير التذكيرات...');
      }
      //await Future.delayed(const Duration(milliseconds: 500));
      _updateStatus('الانتقال إلى التذكيرات...');
      
      // إرسال FCM token قبل الانتقال إلى صفحة reminders
      try {
        await FcmService.instance.sendFcmTokenToBackend();
        _safeShowMessage('✅ تم إرسال FCM token');
      } catch (e) {
        _safeShowMessage('⚠️ فشل إرسال FCM token: $e', color: Colors.orange);
      }
      
      //await Future.delayed(const Duration(milliseconds: 300));
      _navigateToRoute('/reminders');
    } else {
      _safeShowMessage('🌐 Authenticated user online - checking subscription');
      _updateStatus('التحقق من حالة الاشتراك...');
      try {
        final userId = authProvider.userId;
        String? userIdStr;
        if (userId != null) {
          userIdStr = userId.toString();
          _safeShowMessage('📋 Using user ID for subscription check: $userIdStr');
        }

        final subscriptionResponse = await subscriptionManager.checkSubscription(userId: userIdStr);

        if (subscriptionResponse['subscribed'] == true) {
          _updateStatus('اشتراك مميز مفعل!');
          //await Future.delayed(const Duration(milliseconds: 500));
          
          // إرسال FCM token قبل الانتقال إلى صفحة reminders
          try {
            await FcmService.instance.sendFcmTokenToBackend();
            _safeShowMessage('✅ تم إرسال FCM token');
          } catch (e) {
            _safeShowMessage('⚠️ فشل إرسال FCM token: $e', color: Colors.orange);
          }
          
          _navigateToRoute('/reminders');
        } else {
          _safeShowMessage('❌ User authenticated but no premium subscription found - logging out', color: Colors.red);
          _updateStatus('لا يوجد اشتراك مميز - إلغاء تسجيل الدخول...');

          await _performLogoutViaAuthService();

          //await Future.delayed(const Duration(milliseconds: 1000));
          _updateStatus('يجب الاشتراك أولاً للوصول للتطبيق...');
          //await Future.delayed(const Duration(milliseconds: 1000));
          _updateStatus('إعادة توجيه لتسجيل الدخول...');
          //await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        }
      } catch (subscriptionError) {
        _safeShowMessage('❌ Subscription check failed: $subscriptionError', color: Colors.red);

        if (authProvider.isOfflineMode) {
          _updateStatus('خطأ في الاتصال - استخدام البيانات المحفوظة...');
          
          // إرسال FCM token قبل الانتقال إلى صفحة reminders
          try {
            await FcmService.instance.sendFcmTokenToBackend();
            _safeShowMessage('✅ تم إرسال FCM token');
          } catch (e) {
            _safeShowMessage('⚠️ فشل إرسال FCM token: $e', color: Colors.orange);
          }
          
          //await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/reminders');
        } else {
          _safeShowMessage('❌ Subscription check failed online - logging out user', color: Colors.red);
          _updateStatus('فشل فحص الاشتراك - إلغاء تسجيل الدخول...');

          await _performLogoutViaAuthService();
          //await Future.delayed(const Duration(milliseconds: 1000));
          _updateStatus('إعادة توجيه لتسجيل الدخول...');
          //await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        }
      }
    }
  } catch (e) {
    _safeShowMessage('❌ Error handling authenticated user: $e', color: Colors.red);

    _updateStatus('حدث خطأ - إلغاء تسجيل الدخول للأمان...');
    try {
      await _performLogoutViaAuthService();
      //await Future.delayed(const Duration(milliseconds: 500));
      _navigateToRoute('/auth');
    } catch (logoutError) {
      _safeShowMessage('❌ Emergency logout failed: $logoutError', color: Colors.red);
      _navigateToRoute('/reminders');
    }
  }
}

  Future<void> _performLogoutViaAuthService() async {
    try {
      _safeShowMessage('🔄 بدء عملية تسجيل خروج عبر AuthenticationService...');

      final authService = AuthenticationService(context);

      await authService.logout();

      _safeShowMessage('✅ اكتملت عملية تسجيل الخروج عبر AuthenticationService');
    } catch (e) {
      _safeShowMessage(
          '❌ خطأ في عملية تسجيل الخروج عبر AuthenticationService: $e',
          color: Colors.red);
      rethrow;
    }
  }

  void _handleInitializationError(dynamic error) {
    _safeShowMessage('🚨 Handling initialization error: $error',
        color: Colors.red);
    _updateStatus('حدث خطأ - جاري المحاولة مرة أخرى...');
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        final authProvider = AuthProvider.instance;
        await authProvider.initializeAuthentication();
        if (authProvider.isAuthenticated) {
          _safeShowMessage(
              '✅ Emergency fallback: User authenticated via AuthProvider');
          _updateStatus('استخدام البيانات المحفوظة...');
          //await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/reminders');
        } else {
          _safeShowMessage(
              '❌ Emergency fallback: No authentication via AuthProvider',
              color: Colors.red);
          _updateStatus('إعادة توجيه لتسجيل الدخول...');
          //await Future.delayed(const Duration(milliseconds: 500));

          try {
            await _performLogoutViaAuthService();
            _navigateToRoute('/auth');
          } catch (logoutError) {
            _safeShowMessage('❌ Emergency logout failed: $logoutError',
                color: Colors.red);
            _navigateToRoute('/reminders');
          }
        }
      } catch (e) {
        _safeShowMessage('❌ Error in emergency fallback: $e',
            color: Colors.red);
        _updateStatus('حدث خطأ - إلغاء تسجيل الدخول للأمان...');
        try {
          await _performLogoutViaAuthService();
          //await Future.delayed(const Duration(milliseconds: 500));
          _navigateToRoute('/auth');
        } catch (logoutError) {
          _safeShowMessage('❌ Emergency logout failed: $logoutError',
              color: Colors.red);
          _navigateToRoute('/reminders');
        }
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
            const SizedBox(height: 8),
            if (widget.isRevenueCatInitialized != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: (widget.isRevenueCatInitialized!
                          ? Colors.green
                          : Colors.red)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (widget.isRevenueCatInitialized!
                            ? Colors.green
                            : Colors.red)
                        .withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isRevenueCatInitialized!
                          ? Icons.monetization_on
                          : Icons.money_off,
                      color: widget.isRevenueCatInitialized!
                          ? Colors.green
                          : Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isRevenueCatInitialized!
                          ? 'RevenueCat'
                          : 'RevenueCat غير متاح',
                      style: TextStyle(
                        color: widget.isRevenueCatInitialized!
                            ? Colors.green
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

  Widget _buildMessagesList() {
    return ValueListenableBuilder<List<SplashMessage>>(
      valueListenable: SplashScreen.messagesNotifier,
      builder: (context, messages, child) {
        final displayMessages = messages.reversed.take(10).toList();

        if (displayMessages.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 150),
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.grey[700]!,
              width: 1,
            ),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: displayMessages.length,
            itemBuilder: (context, index) {
              final message = displayMessages[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                decoration: BoxDecoration(
                  color: message.color?.withOpacity(0.1) ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    if (message.color != null)
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: message.color,
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.message,
                        style: TextStyle(
                          color: message.color ?? Colors.white70,
                          fontSize: 11,
                          fontWeight: message.isDebug
                              ? FontWeight.normal
                              : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // خلفية بيضاء
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
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
                          color: Colors.grey[200], // خلفية رمادية فاتحة
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.access_time,
                          size: 80,
                          color: Colors.black, // لون الأيقونة يتناسب مع الخلفية البيضاء
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}