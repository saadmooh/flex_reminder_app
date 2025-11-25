// consts.dart
import 'package:flutter/material.dart';

class AppConstants {
  // API Constants
  static const String API_BASE_URL = 'https://flexreminder.com/api';
  static const String API_PASSWORD = 'api_password_app';
  static const String LAST_SERVER_TIME_KEY = 'last_server_time';

  // Storage Keys
  static const String AUTH_TOKEN_KEY = 'auth_token';
  static const String FCM_TOKEN_KEY = 'fcmToken';
  static const String USER_ID_KEY = 'user_id';

  // Notification Channels
  static const String SCHEDULED_CHANNEL_KEY = 'scheduled_channel';
  static const String FCM_BACKGROUND_CHANNEL = 'fcm_background_channel';
  static const String FCM_BACKGROUND_CHANNEL_NAME =
      'FCM Background Notifications';
  static const String FCM_BACKGROUND_CHANNEL_DESCRIPTION =
      'Notifications received when app is in background';

  // Notification Settings
  static const int MAX_PROCESSED_MESSAGES = 100;
  static const Duration PROCESS_DELAY = Duration(seconds: 2);
  static const Duration LAST_PROCESSED_CLEANUP_DURATION = Duration(minutes: 5);

  // Assets
  static const String SERVICE_ACCOUNT_PATH =
      'assets/flex-reminders-app-7e58d9767343.json';
  static const String ANDROID_NOTIFICATION_ICON = '@mipmap/ic_launcher';

  // Firebase Scopes
  static const String FIREBASE_MESSAGING_SCOPE =
      'https://www.googleapis.com/auth/firebase.messaging';

  // RevenueCat
  static const String REVENUECAT_API_KEY = 'goog_WnLgVtBcHCJndRicBHtliPtJENT';
  static const String PREMIUM_ENTITLEMENT_ID = 'exp';

  // Color Constants (aligned with main.dart theme)
  static const Color PRIMARY_COLOR = Color(0xFF6200EA); // Deep Purple
  static const Color SECONDARY_COLOR = Color(0xFF03DAC6); // Teal
  static const Color ELEVATED_BUTTON_COLOR =
      Color(0xFF727475); // From main.dart
  static const Color TEXT_BUTTON_COLOR = Color(0xFFCBCED0); // From main.dart
  static const Color SCAFFOLD_BACKGROUND_COLOR = Colors.black; // From main.dart
  static const Color CARD_COLOR = Color(0xFF212121); // Grey[900]
  static const Color TEXT_COLOR = Colors.white; // From main.dart textTheme
  static const Color TEXT_SECONDARY_COLOR =
      Color(0xFFB0BEC5); // White70 approximation
}
