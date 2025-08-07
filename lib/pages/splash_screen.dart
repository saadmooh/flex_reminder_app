import 'package:flutter/material.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/providers/auth_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;
  late AppLocalizations localizations;

  void _navigateToRoute(String routeName) {
    if (!mounted || _hasNavigated) {
      print(
          'Navigation blocked: mounted=$mounted, hasNavigated=$_hasNavigated');
      return;
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      print('Already on route: $routeName, skipping navigation');
      _hasNavigated = true;
      return;
    }

    print('Navigating from $currentRoute to $routeName');
    _hasNavigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(routeName);
      }
    });
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      print('Error checking internet connection: $e');
      return false;
    }
  }

  Future<void> _navigateBasedOnAuth() async {
    try {
      await Future.delayed(
          const Duration(seconds: 2)); // تأخير لعرض شاشة Splash
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // فحص الاتصال بالإنترنت
      bool hasInternet = await _checkInternetConnection();
      
      if (!hasInternet) {
        // عند عدم وجود إنترنت، فحص الـ token المخزن محلياً فقط
        print('No internet connection, checking local token...');
        
        // التحقق من وجود token محفوظ محلياً
        bool hasLocalToken = await authProvider.hasStoredToken();
        
        if (hasLocalToken) {
          print('Local token found, navigating to reminders...');
          // إذا كان هناك token محفوظ، انتقل إلى reminders مباشرة
          _navigateToRoute('/reminders');
          return;
        } else {
          print('No local token found, navigating to auth...');
          // إذا لم يكن هناك token، انتقل إلى صفحة المصادقة
          _navigateToRoute('/auth');
          return;
        }
      }

      // إذا كان هناك إنترنت، تنفيذ المنطق العادي
      print('Internet connection available, proceeding with normal flow...');
      
      // الانتظار حتى اكتمال عملية المصادقة
      while (authProvider.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('authProvider.isAuthenticated: ${authProvider.isAuthenticated}');
      if (!authProvider.isAuthenticated) {
        _navigateToRoute('/auth');
        return;
      }

      final subscriptionResponse = await authProvider.checkSubscription();
      print('Subscription Response: $subscriptionResponse');
      if (subscriptionResponse['subscribed'] == true) {
        if (subscriptionResponse['redirect_to_subscription'] == true) {
          _navigateToRoute('/subscription_management');
        } else {
          _navigateToRoute('/reminders');
        }
      } else {
        _navigateToRoute('/auth');
      }
    } catch (e) {
      print('Error in _navigateBasedOnAuth: $e');
      
      // في حالة حدوث خطأ، تحقق من وجود token محلي كخطة احتياطية
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      bool hasLocalToken = await authProvider.hasStoredToken();
      
      if (hasLocalToken) {
        print('Error occurred but local token found, navigating to reminders...');
        _navigateToRoute('/reminders');
      } else {
        print('Error occurred and no local token, navigating to auth...');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.error(e.toString())),
              backgroundColor: Colors.red,
            ),
          );
        }
        _navigateToRoute('/auth');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateBasedOnAuth();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    localizations = AppLocalizations.of(context)!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}