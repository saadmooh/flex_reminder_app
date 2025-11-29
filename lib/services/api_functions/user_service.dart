import 'dart:convert';
import 'dart:io' as io; // لمعالجة الملفات في Mobile/Desktop
import 'package:flutter/foundation.dart' show kIsWeb; // للتحقق إذا كان التطبيق يعمل على الويب
import 'package:http/http.dart' as http; // لطلبات HTTP
import 'package:flutter/material.dart'; // لـ TimeOfDay (إذا احتجته لاحقاً)

import '../../utils/consts.dart';
import 'api_config.dart';
import 'utils_service.dart';
import 'exceptions.dart';
class SubscriptionService {
  final UtilsService _utilsService;

  SubscriptionService(this._utilsService);

  Future<void> changeOffer(String variantId) async {
    final response = await _utilsService.request('GET', 'subscription/swap', data: {
      'subscription_id': variantId,
    });

    if (response['statusCode'] != 200) {
      throw Exception(response['data']['message'] ?? 'Failed to swap offer');
    }
  }

  Future<Map<String, dynamic>> checkSubscription() async {
    final response = await _utilsService.request('GET', 'subscription/check');

    if (response['statusCode'] == 200) {
      return response['data'];
    } else {
      throw Exception('Failed to check subscription');
    }
  }

  Future<String> getCustomerPortalUrl() async {
    final response = await _utilsService.request('GET', 'customer-portal-url');

    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data is Map<String, dynamic> &&
          data.containsKey('customer_portal_url')) {
        return data['customer_portal_url'] as String;
      } else {
        throw Exception('Invalid response format: URL not found in response');
      }
    } else {
      throw Exception('Failed to get customer portal URL');
    }
  }

  Future<void> pauseSubscription() async {
    await _handleSubscriptionAction('pause');
  }

  Future<void> cancelSubscription() async {
    await _handleSubscriptionAction('cancel');
  }

  Future<Map<String, dynamic>> resumeSubscription() async {
    return await _handleSubscriptionAction('resume');
  }

  Future<Map<String, dynamic>> _handleSubscriptionAction(String action) async {
    final response = await _utilsService.request('POST', 'subscription/$action');

    if (response['statusCode'] == 200) {
      return response['data'] as Map<String, dynamic>;
    } else {
      throw Exception('Failed to $action subscription');
    }
  }

  Future<String> buySubscription(String subscriptionId) async {
    final response = await _utilsService.request('POST', 'subscription/buy', data: {
      'user_id': (await _utilsService.apiConfig.getCurrentUserId()).toString(),
      'subscription_id': subscriptionId,
    });

    if (response['statusCode'] == 200) {
      final data = response['data'];
      if (data['status'] == 'success' && data['checkout_url'] != null) {
        return data['checkout_url'] as String;
      } else {
        throw Exception('Checkout URL not found in response');
      }
    } else {
      throw Exception('Failed to buy subscription');
    }
  }
}