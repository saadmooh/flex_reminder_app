import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityHelper {
  // فحص الاتصال بالإنترنت مع محاولة فعلية
  static Future<bool> checkInternetConnection({bool verbose = false}) async {
    try {
      // تسجيل حالة الفحص إذا كان verbose مفعلًا
      if (verbose && kDebugMode) {
        debugPrint('🔄 فحص الاتصال بالإنترنت...');
      }

      // التحقق من حالة الاتصال باستخدام connectivity_plus
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        if (verbose && kDebugMode) {
          debugPrint('⚠️ لا يوجد اتصال بالشبكة (ConnectivityResult.none)');
        }
        return false;
      }

      // فحص فعلي عبر محاولة الوصول إلى موقع معروف
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5), onTimeout: () {
        if (verbose && kDebugMode) {
          debugPrint('⏳ انتهت مهلة الاتصال بـ google.com');
        }
        return [];
      });

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        if (verbose && kDebugMode) {
          debugPrint('✅ متصل بالإنترنت');
        }
        return true;
      } else {
        if (verbose && kDebugMode) {
          debugPrint('⚠️ لا يوجد وصول فعلي للإنترنت');
        }
        return false;
      }
    } catch (e) {
      if (verbose && kDebugMode) {
        debugPrint('❌ خطأ في فحص الاتصال: $e');
      }
      return false;
    }
  }
}
