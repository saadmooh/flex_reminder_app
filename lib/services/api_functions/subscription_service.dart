import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class SubscriptionService {
  final ApiConfig _apiConfig;

  SubscriptionService(this._apiConfig);

  Future<void> changeOffer(String variantId) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.API_BASE_URL}/subscription/swap?subscription_id=$variantId'),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized');
      } else {
        print(response.body);
        throw Exception('Failed to swap offer: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error swapping offer: $e');
    }
  }

  Future<Map<String, dynamic>> checkSubscription() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.API_BASE_URL}/subscription/check'),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Check Subscription Response: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Failed to check subscription: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in checkSubscription: $e');
      rethrow;
    }
  }

  Future<String> getCustomerPortalUrl() async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.API_BASE_URL}/customer-portal-url'),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      print('Customer Portal Response: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> &&
            data.containsKey('customer_portal_url')) {
          return data['customer_portal_url'] as String;
        } else {
          throw Exception('Invalid response format: URL not found in response');
        }
      } else {
        throw Exception(
            'Failed to get customer portal URL: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in getCustomerPortalUrl: $e');
      rethrow;
    }
  }

  Future<void> pauseSubscription() async {
    await _handleSubscriptionAction(
      '${ApiConfig.API_BASE_URL}/subscription/pause',
      'Failed to pause subscription',
    );
  }

  Future<void> cancelSubscription() async {
    await _handleSubscriptionAction(
      '${ApiConfig.API_BASE_URL}/subscription/cancel',
      'Failed to cancel subscription',
    );
  }

  Future<Map<String, dynamic>> resumeSubscription() async {
    return await _handleSubscriptionAction(
      '${ApiConfig.API_BASE_URL}/subscription/resume',
      'Failed to resume subscription',
    );
  }

  Future<Map<String, dynamic>> _handleSubscriptionAction(
      String url, String errorMessage) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Subscription Action Response ($url): ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            '$errorMessage: ${errorData['message'] ?? response.body}');
      }
    } catch (e) {
      print('Error in _handleSubscriptionAction: $e');
      rethrow;
    }
  }

  Future<String> buySubscription(String subscriptionId) async {
    if (!await _apiConfig.checkTokenValidity()) {
      throw Exception('Invalid or expired token');
    }
    final token = await _apiConfig.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    try {
      final userId = await _apiConfig.getCurrentUserId();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.API_BASE_URL}/subscription/buy'),
        headers: {
          'X-API-Password': ApiConfig.API_PASSWORD,
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId.toString(),
          'subscription_id': subscriptionId,
        }),
      );

      print('Buy Subscription Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['checkout_url'] != null) {
          return data['checkout_url'] as String;
        } else {
          throw Exception('Checkout URL not found in response');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'Failed to buy subscription: ${errorData['message'] ?? response.body}');
      }
    } catch (e) {
      print('Error in buySubscription: $e');
      rethrow;
    }
  }
}
