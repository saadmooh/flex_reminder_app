import 'package:flutter/material.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';

class NoInternetScreen extends StatefulWidget {
  final VoidCallback? onRetrySuccess;
  final String? redirectRoute;
  final Map<String, dynamic>? redirectArguments;

  const NoInternetScreen({
    super.key,
    this.onRetrySuccess,
    this.redirectRoute,
    this.redirectArguments,
  });

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startPeriodicCheck();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();
  }

  void _startPeriodicCheck() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _checkConnectionSilently();
      }
    });
  }

  Future<void> _checkConnectionSilently() async {
    try {
      final hasInternet = await ConnectivityHelper.checkInternetConnection(
        verbose: false,
      );

      if (hasInternet && mounted) {
        _handleConnectionRestored();
      } else if (mounted) {
        _startPeriodicCheck();
      }
    } catch (e) {
      debugPrint('خطأ في الفحص الدوري للإنترنت: $e');
      if (mounted) {
        _startPeriodicCheck();
      }
    }
  }

  void _handleConnectionRestored() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        if (widget.onRetrySuccess != null) {
          widget.onRetrySuccess!();
        } else if (widget.redirectRoute != null) {
          Navigator.of(context).pushReplacementNamed(
            widget.redirectRoute!,
            arguments: widget.redirectArguments,
          );
        } else {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // خلفية بيضاء
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _slideAnimation,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // الشعار
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[200], // خلفية رمادية فاتحة
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Image.asset(
                          'assets/logo.png',
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.access_time,
                              size: 60,
                              color: Colors.black, // لون يتناسب مع الخلفية البيضاء
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
                      // أيقونة عدم الاتصال
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 80,
                        color: Colors.grey[600], // لون رمادي للأيقونة
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}