import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/services/revenuecat_service.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/services/subscription_manager.dart';
import 'package:flex_reminder/services/navigation_service.dart';

class VerificationCodeScreen extends StatefulWidget {
  final String email;

  const VerificationCodeScreen({super.key, required this.email});

  @override
  _VerificationCodeScreenState createState() => _VerificationCodeScreenState();
}

class _VerificationCodeScreenState extends State<VerificationCodeScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  late AnimationController _timerController;
  late Animation<double> _timerAnimation;
  final int _timerDuration = 15 * 60; // 15 minutes in seconds for code validity
  DateTime? _lastResendTime; // Track the last time the code was resent
  final int _resendCooldown = 60; // 60 seconds cooldown for resending

  @override
  void initState() {
    super.initState();
    // Initialize the timer for code validity
    _timerController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _timerDuration),
    );
    _timerAnimation = Tween<double>(begin: _timerDuration.toDouble(), end: 0)
        .animate(_timerController)
      ..addListener(() {
        setState(() {});
      });
    _timerController.forward(); // Start the timer
  }

  String _formatTimer(double seconds) {
    final minutes = (seconds ~/ 60).toInt();
    final secs = (seconds % 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Check if resend is allowed (at least 60 seconds since last resend)
  bool _canResendCode() {
    if (_lastResendTime == null) return true;
    final now = DateTime.now();
    final elapsed = now.difference(_lastResendTime!).inSeconds;
    return elapsed >= _resendCooldown;
  }

  // Get remaining cooldown time for resend
  String _getResendCooldownMessage() {
    if (_lastResendTime == null) return '';
    final now = DateTime.now();
    final elapsed = now.difference(_lastResendTime!).inSeconds;
    final remaining = _resendCooldown - elapsed;
    if (remaining > 0) {
      return AppLocalizations.of(context)!.resendCooldown(remaining);
    }
    return '';
  }

  Future<void> _submitCode() async {
    if (!_formKey.currentState!.validate()) return;

    // استخدام Singleton instance
    final authProvider = AuthProvider.instance;
    final localizations = AppLocalizations.of(context)!;

    try {
      final result = await authProvider.verifyEmail(widget.email, _codeController.text);
      if (result['success']) {
        _showSuccessSnackBar(localizations.emailVerificationSuccessful);
        if (kDebugMode) {
          print('✅ Email verification successful for ${widget.email}');
        }

        // Check subscription status after verification
        final hasInternet =
            await ConnectivityHelper.checkInternetConnection(verbose: true);
        if (hasInternet) {
          final subscriptionManager = SubscriptionManager();
          final subscriptionResponse = await subscriptionManager.checkSubscription();
          if (subscriptionResponse['subscribed'] == true) {
            _showSuccessSnackBar('⭐ Premium subscription active!');
            if (kDebugMode) {
              print('⭐ User has active premium subscription');
            }
            NavigationService.navigateTo(context, '/reminders');
          } else {
            _showSuccessSnackBar('ℹ️ No premium subscription found');
            if (kDebugMode) {
              print('ℹ️ No premium subscription, showing paywall');
            }
             await RevenueCatService.instance.showPaywall();
            NavigationService.navigateTo(context, '/subscription_management');
          }
        } else {
          _showSuccessSnackBar('📴 Offline mode: Skipping subscription check');
          if (kDebugMode) {
            print('📴 Offline mode, redirecting to reminders');
          }
          NavigationService.navigateTo(context, '/reminders');
        }
      } else {
        _showErrorSnackBar(
            authProvider.errorMessage ?? 'An unexpected error occurred');
        if (kDebugMode) {
          print('❌ Verification error: ${authProvider.errorMessage ?? result['message']}');
        }
      }
    } catch (e) {
      _showErrorSnackBar(
          authProvider.errorMessage ?? 'An unexpected error occurred');
      if (kDebugMode) {
        print('❌ Verification error: ${authProvider.errorMessage ?? e}');
      }
    }
  }

  Future<void> _resendCode() async {
    // استخدام Singleton instance
    final authProvider = AuthProvider.instance;
    final localizations = AppLocalizations.of(context)!;

    if (!_canResendCode()) {
      _showErrorSnackBar(_getResendCooldownMessage());
      if (kDebugMode) {
        print('❌ Resend code blocked: Cooldown not elapsed');
      }
      return;
    }

    try {
      final result = await authProvider.resendVerificationCode(widget.email);
      if (result['success']) {
        _lastResendTime = DateTime.now(); // Update last resend time
        _showSuccessSnackBar(localizations.verificationCodeResent);
        if (kDebugMode) {
          print('✅ Verification code resent to ${widget.email}');
        }
        // Reset the timer for code validity
        _timerController.reset();
        _timerController.forward();
      } else {
        _showErrorSnackBar(authProvider.errorMessage ?? 'Failed to resend code');
        if (kDebugMode) {
          print('❌ Resend code error: ${authProvider.errorMessage ?? result['message']}');
        }
      }
    } catch (e) {
      _showErrorSnackBar(authProvider.errorMessage ?? 'Failed to resend code');
      if (kDebugMode) {
        print('❌ Resend code error: ${authProvider.errorMessage ?? e}');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    // يمكنك إزالة التعليقات لتفعيل الـ SnackBar لاحقًا
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(message, style: const TextStyle(color: Colors.white)),
    //     backgroundColor: Colors.green,
    //     duration: const Duration(seconds: 3),
    //   ),
    // );
  }

  void _showErrorSnackBar(String message) {
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(message, style: const TextStyle(color: Colors.white)),
    //     backgroundColor: Colors.red,
    //     duration: const Duration(seconds: 3),
    //   ),
    // );
  }

  // دالة موحدة للعودة الآمنة
  void _safePop() {
    final authProvider = AuthProvider.instance;
    authProvider.clearVerificationState();
    Navigator.popAndPushNamed(context, '/auth'); // 👈 الحل الأساسي لمشكلة الشاشة السوداء
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageManager = Provider.of<LanguageManager>(context);
    final authProvider = AuthProvider.instance;
    final isArabic = languageManager.locale.languageCode == 'ar';
    final textDirection = isArabic ? TextDirection.rtl : TextDirection.ltr;

    return WillPopScope(
      onWillPop: () async {
        _safePop();
        return false; // منع الإغلاق الافتراضي (لأننا نتحكم فيه يدويًا)
      },
      child: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: _safePop, // 👈 نفس السلوك عند الضغط على زر الرجوع في AppBar
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        height: 80.0,
                      ),
                      const SizedBox(height: 40.0),
                      Text(
                        localizations.verifyEmail,
                        style: const TextStyle(
                          fontSize: 24.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                        textDirection: textDirection,
                      ),
                      const SizedBox(height: 20.0),
                      Text(
                        localizations.verificationCodeInstructions
                            .replaceFirst(':email', widget.email),
                        style: const TextStyle(
                          fontSize: 16.0,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                        textDirection: textDirection,
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        controller: _codeController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: localizations.verificationCode,
                          labelStyle: const TextStyle(color: Colors.black),
                          border: const UnderlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        textDirection: textDirection,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty ||
                              value.length != 6) {
                            return localizations.invalidVerificationCode;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20.0),
                      Text(
                        localizations
                            .timeRemaining(_formatTimer(_timerAnimation.value)),
                        style: const TextStyle(color: Colors.red, fontSize: 16.0),
                        textAlign: TextAlign.center,
                        textDirection: textDirection,
                      ),
                      const SizedBox(height: 30.0),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15.0),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: authProvider.isLoading ? null : _submitCode,
                        child: authProvider.isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                localizations.verify,
                                style: const TextStyle(
                                    fontSize: 16.0, color: Colors.white),
                              ),
                      ),
                      const SizedBox(height: 20.0),
                      TextButton(
                        onPressed: authProvider.isLoading || !_canResendCode()
                            ? null
                            : _resendCode,
                        child: Text(
                          localizations.resendCode,
                          style: TextStyle(
                            color: authProvider.isLoading || !_canResendCode()
                                ? Colors.grey
                                : const Color(0xFF6200EE),
                          ),
                        ),
                      ),
                      if (!_canResendCode()) ...[
                        const SizedBox(height: 10.0),
                        Text(
                          _getResendCooldownMessage(),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14.0),
                          textAlign: TextAlign.center,
                          textDirection: textDirection,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _timerController.dispose();
    super.dispose();
  }
}