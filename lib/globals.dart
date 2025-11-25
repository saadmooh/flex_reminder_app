import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
// متغير لتتبع حالة تهيئة RevenueCat
bool _isRevenueCatInitialized = false;

bool get isRevenueCatInitialized => _isRevenueCatInitialized;
set isRevenueCatInitialized(bool value) => _isRevenueCatInitialized = value;
