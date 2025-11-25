import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';
import 'package:flex_reminder/globals.dart';

class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance {
    _instance ??= ConnectivityService._internal();
    return _instance!;
  }

  ConnectivityService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicCheckTimer;
  bool _isConnected = true;
  bool _isInitialized = false;
  String? _currentRoute;
  Map<String, dynamic>? _pendingRouteArguments;

  // Stream controller للإشعار بحالة الاتصال
  final StreamController<bool> _connectivityController = 
      StreamController<bool>.broadcast();
  
  Stream<bool> get connectivityStream => _connectivityController.stream;
  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  /// تهيئة خدمة الاتصال
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔧 تهيئة خدمة مراقبة الاتصال...');
      
      // فحص الاتصال الأولي
      _isConnected = await ConnectivityHelper.checkInternetConnection(
        verbose: true,
      );
      
      debugPrint('📶 حالة الاتصال الأولية: $_isConnected');
      
      // إعداد مراقبة الاتصال
      _setupConnectivityListener();
      
      // إعداد الفحص الدوري
      _setupPeriodicCheck();
      
      _isInitialized = true;
      _connectivityController.add(_isConnected);
      
      debugPrint('✅ تم تهيئة خدمة مراقبة الاتصال');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة خدمة مراقبة الاتصال: $e');
      _isConnected = false;
      _connectivityController.add(false);
    }
  }

  /// إعداد مستمع تغييرات الاتصال
void _setupConnectivityListener() {
  _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
    (List<ConnectivityResult> results) async {
      debugPrint('📡 تغيير في حالة الاتصال: $results');
      // نأخذ أول نتيجة أو نتحقق من وجود اتصال
      ConnectivityResult result = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      await _handleConnectivityChange(result);
    },
    onError: (error) {
      debugPrint('❌ خطأ في مستمع الاتصال: $error');
    },
  );
}

  /// إعداد الفحص الدوري
  void _setupPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _performPeriodicCheck(),
    );
  }

  /// فحص دوري للاتصال
  Future<void> _performPeriodicCheck() async {
    try {
      final hasInternet = await ConnectivityHelper.checkInternetConnection(
        verbose: false,
      );
      
      if (hasInternet != _isConnected) {
        debugPrint('🔄 تغيير في حالة الاتصال (فحص دوري): $hasInternet');
        await _updateConnectionStatus(hasInternet);
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في الفحص الدوري: $e');
    }
  }

  /// معالجة تغيير الاتصال
  Future<void> _handleConnectivityChange(ConnectivityResult result) async {
    // تأخير قصير للتأكد من استقرار الاتصال
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      bool hasInternet;
      
      if (result == ConnectivityResult.none) {
        hasInternet = false;
      } else {
        // فحص إضافي للتأكد من وجود إنترنت فعلي
        hasInternet = await ConnectivityHelper.checkInternetConnection(
          verbose: true,
        );
      }
      
      await _updateConnectionStatus(hasInternet);
    } catch (e) {
      debugPrint('❌ خطأ في معالجة تغيير الاتصال: $e');
      await _updateConnectionStatus(false);
    }
  }

  /// تحديث حالة الاتصال
  Future<void> _updateConnectionStatus(bool hasInternet) async {
    final previousStatus = _isConnected;
    _isConnected = hasInternet;
    
    // إشعار المستمعين
    _connectivityController.add(_isConnected);
    
    if (previousStatus != _isConnected) {
      debugPrint('📶 تم تحديث حالة الاتصال: $_isConnected');
      
      if (_isConnected) {
        await _handleConnectionRestored();
      } else {
        await _handleConnectionLost();
      }
    }
  }

  /// معالجة استعادة الاتصال
  Future<void> _handleConnectionRestored() async {
    debugPrint('✅ تم استعادة الاتصال بالإنترنت');
    
    // إذا كان المستخدم في صفحة "لا يوجد إنترنت"، قم بإرساله للصفحة المطلوبة
    final currentContext = navigatorKey.currentContext;
    if (currentContext != null) {
      final currentRoute = ModalRoute.of(currentContext)?.settings.name;
      
      if (currentRoute == '/no-internet') {
        // العودة للصفحة المحفوظة أو الصفحة الرئيسية
        if (_currentRoute != null) {
          Navigator.of(currentContext).pushReplacementNamed(
            _currentRoute!,
            arguments: _pendingRouteArguments,
          );
        } else {
          Navigator.of(currentContext).pushReplacementNamed('/');
        }
        
        // مسح البيانات المحفوظة
        _currentRoute = null;
        _pendingRouteArguments = null;
      }
    }
    
    // إظهار رسالة تأكيد
    _showSnackBar(
      '✅ تم استعادة الاتصال بالإنترنت',
      backgroundColor: Colors.green,
    );
  }

  /// معالجة فقدان الاتصال
  Future<void> _handleConnectionLost() async {
    debugPrint('❌ تم فقدان الاتصال بالإنترنت');
    
    final currentContext = navigatorKey.currentContext;
    if (currentContext != null) {
      final currentRoute = ModalRoute.of(currentContext)?.settings.name;
      
      // تخزين الصفحة الحالية
      if (currentRoute != null && currentRoute != '/no-internet') {
        _currentRoute = currentRoute;
        _pendingRouteArguments = ModalRoute.of(currentContext)?.settings.arguments as Map<String, dynamic>?;
      }
      
      // الانتقال لصفحة "لا يوجد إنترنت" فقط إذا لم نكن فيها بالفعل
      if (currentRoute != '/no-internet') {
        Navigator.of(currentContext).pushReplacementNamed('/no-internet');
      }
    }
    
    // إظهار رسالة تحذير
    _showSnackBar(
      '❌ لا يوجد اتصال بالإنترنت',
      backgroundColor: Colors.red,
    );
  }

  /// فحص فوري للاتصال
  Future<bool> checkConnection({bool showMessages = false}) async {
    try {
      final hasInternet = await ConnectivityHelper.checkInternetConnection(
        verbose: showMessages,
      );
      
      if (hasInternet != _isConnected) {
        await _updateConnectionStatus(hasInternet);
      }
      
      return hasInternet;
    } catch (e) {
      debugPrint('❌ خطأ في فحص الاتصال: $e');
      return false;
    }
  }

  /// التنقل مع فحص الاتصال
  Future<bool> navigateWithConnectionCheck(
    BuildContext context,
    String route, {
    Map<String, dynamic>? arguments,
    bool requiresInternet = true,
  }) async {
    if (!requiresInternet) {
      Navigator.of(context).pushNamed(route, arguments: arguments);
      return true;
    }

    // فحص الاتصال
    final hasConnection = await checkConnection(showMessages: true);
    
    if (hasConnection) {
      Navigator.of(context).pushNamed(route, arguments: arguments);
      return true;
    } else {
      // حفظ الصفحة المطلوبة والانتقال لصفحة "لا يوجد إنترنت"
      _currentRoute = route;
      _pendingRouteArguments = arguments;
      
      Navigator.of(context).pushReplacementNamed('/no-internet');
      return false;
    }
  }

  /// إظهار رسالة
  void _showSnackBar(String message, {Color? backgroundColor}) {
    // final context = scaffoldMessengerKey.currentContext;
    // if (context != null) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text(message),
    //       backgroundColor: backgroundColor,
    //       duration: const Duration(seconds: 3),
    //     ),
    //   );
    // }
  }

  /// إنهاء الخدمة
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicCheckTimer?.cancel();
    _connectivityController.close();
    _isInitialized = false;
    debugPrint('🔌 تم إنهاء خدمة مراقبة الاتصال');
  }

  /// إعادة تشغيل الخدمة
  Future<void> restart() async {
    dispose();
    await initialize();
  }
}