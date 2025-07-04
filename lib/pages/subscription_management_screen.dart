import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'dart:ui' as ui;
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'dart:io';
import 'dart:async';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _subscriptionData;
  String? _customerPortalUrl;
  bool _isLoading = true;
  String? _error;
  String _language = 'en';
  String? _billingProvider;
  late AppLocalizations localizations;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    localizations = AppLocalizations.of(context)!;
    _setLanguage();
  }

  void _setLanguage() {
    setState(() {
      _language = Localizations.localeOf(context).languageCode;
    });
  }

  Future<void> _loadInitialData() async {
    print('Loading initial data...');
    try {
      await Future.wait([
        _loadSubscriptionData(),
        _loadCustomerPortalUrl(),
      ]);
      print('Subscription data: $_subscriptionData');
    } catch (e) {
      _handleError(e, localizations.errorLoadingInitialData);
    }
  }

  Future<void> _loadSubscriptionData() async {
    try {
      setState(() => _isLoading = true);
      final data = await _apiService.checkSubscription();
      setState(() {
        _subscriptionData = data;
        _billingProvider = data['billing_provider'] ?? 'lemon_squeezy';
        _isLoading = false;
      });
    } catch (e) {
      _handleError(e, localizations.errorLoadingSubscriptionData);
    }
  }

  Future<void> _loadCustomerPortalUrl() async {
    try {
      final url = await _apiService.getCustomerPortalUrl();
      setState(() => _customerPortalUrl = url);
    } catch (e) {
      _handleError(e, localizations.errorLoadingCustomerPortal);
    }
  }

  void _handleError(dynamic e, String message) {
    print('$message: $e');
    setState(() {
      _error = e.toString();
      _isLoading = false;
    });
    if (e.toString().contains('401')) {
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  bool isSubscribed() {
    return _subscriptionData != null &&
        _subscriptionData!['subscribed'] == true &&
        _subscriptionData!['subscription'] != null;
  }

  bool isPaused() {
    return _subscriptionData != null &&
        _subscriptionData!['subscription'] != null &&
        (_billingProvider == 'lemon_squeezy'
            ? _subscriptionData!['subscription']['status'] == 'paused' ||
                (_subscriptionData!['subscription']['status'] == 'active' &&
                    _subscriptionData!['subscription']['plan']['ends_at'] !=
                        null)
            : (_subscriptionData!['subscription']['status'] == 'cancelled' &&
                _subscriptionData!['subscription']['is_on_grace_period'] ==
                    true));
  }

  bool isSubscriptionInactive() {
    return _subscriptionData != null &&
        _subscriptionData!['subscription'] != null &&
        (_billingProvider == 'lemon_squeezy'
            ? (_subscriptionData!['subscription']['status'] == 'paused' ||
                _subscriptionData!['subscription']['status'] == 'cancelled' ||
                (_subscriptionData!['subscription']['plan']['ends_at'] !=
                        null &&
                    DateTime.parse(_subscriptionData!['subscription']['plan']
                            ['ends_at'])
                        .isBefore(DateTime.now())))
            : (_subscriptionData!['subscription']['status'] == 'cancelled' &&
                _subscriptionData!['subscription']['is_on_grace_period'] !=
                    true));
  }

  Future<void> _cancelSubscription() async {
    try {
      setState(() => _isLoading = true);
      await _apiService.cancelSubscription();
      await Future.wait([
        _loadSubscriptionData(),
        _loadCustomerPortalUrl(),
      ]);
      String message = localizations.subscriptionCancelledSuccessfully;
      if (_billingProvider == 'polar' &&
          _subscriptionData!['subscription']['current_period_end'] != null) {
        final gracePeriodEnd = DateFormat('yyyy-MM-dd').format(DateTime.parse(
            _subscriptionData!['subscription']['current_period_end']));
        message += '\n${localizations.restoreBy(gracePeriodEnd)}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: _billingProvider == 'polar' && isPaused()
              ? SnackBarAction(
                  label: localizations.resumePlan,
                  onPressed: () => _resumeSubscription(),
                )
              : null,
        ),
      );
      // Refresh the page by reloading initial data
      await _loadInitialData();
    } catch (e) {
      _handleError(e, localizations.errorCancellingSubscription);
      _showSnackBar('${localizations.errorCancellingSubscription}: $e');
    }
  }

  Future<void> _resumeSubscription() async {
    try {
      setState(() => _isLoading = true);
      final Map<String, dynamic> response =
          await _apiService.resumeSubscription();
      await Future.wait([
        _loadSubscriptionData(),
        _loadCustomerPortalUrl(),
      ]);
      if (response['status'] == 'success') {
        String message = response['message'] ??
            localizations.subscriptionResumedSuccessfully;
        if (response['subscription'] != null &&
            response['subscription']['renews_at'] != null) {
          final renewsAt = DateFormat('yyyy-MM-dd')
              .format(DateTime.parse(response['subscription']['renews_at']));
          message += '\n${localizations.renewsAt(renewsAt)}';
        }
        _showSnackBar(message);
      } else {
        _showSnackBar(
            response['message'] ?? localizations.errorResumingSubscription);
      }
    } catch (e) {
      _handleError(e, localizations.errorResumingSubscription);
      _showSnackBar(e.toString());
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  ui.TextDirection _getTextDirection() {
    return _language == 'ar' ? ui.TextDirection.rtl : ui.TextDirection.ltr;
  }

  void _showPlanModal(BuildContext context, Map<String, dynamic> planData) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
      ),
      builder: (context) {
        return Directionality(
            textDirection: _getTextDirection(),
            child: _buildPlanModalContent(planData));
      },
    );
  }

  Widget _buildPlanModalContent(Map<String, dynamic> planData) {
    final isUserSubscribed = isSubscribed();
    final isPausedSubscription = isPaused();
    final isCurrentSubscription = planData.containsKey('status');
    final planName = isCurrentSubscription
        ? planData['plan']['name'] ?? localizations.unnamedPlan
        : planData['name'] ?? localizations.unnamedPlan;
    final planDescription = isCurrentSubscription
        ? planData['plan']['description']
        : planData['description'];
    final hasAdvancedFeatures = isCurrentSubscription
        ? planData['plan']['has_advanced_features'] == true
        : planData['has_advanced_features'] == true;
    final variants = planData['variants'] as List<dynamic>?;
    final discount = planData['discount'] ?? 0;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: _language == 'ar'
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                planName,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (isCurrentSubscription)
                Text(
                  localizations.status(planData['status'].toUpperCase()),
                  style: TextStyle(
                    color: planData['status'] == 'active'
                        ? Colors.green[700]
                        : Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 16),
              planDescription != null
                  ? Html(
                      data: planDescription,
                      style: {
                        "body": Style(
                            fontSize: FontSize(14), color: Colors.black54),
                        "li": Style(margin: Margins.only(bottom: 4)),
                      },
                    )
                  : Text(
                      localizations.noDescriptionAvailable,
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 14),
                    ),
              const SizedBox(height: 16),
              Text(
                localizations.advancedFeatures(
                    hasAdvancedFeatures ? localizations.yes : localizations.no),
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (variants != null)
                ...variants.map((variant) {
                  final price = variant['price']?.toStringAsFixed(2);
                  final duration = variant['duration'];
                  final subscriptionId =
                      variant['checkout_data']['subscription_id']?.toString();
                  final isCurrentVariant = isUserSubscribed &&
                      planData['plan']['id'] ==
                          _subscriptionData!['subscription']['plan']['id'] &&
                      variant['id'] ==
                          _subscriptionData!['subscription']['variant_id'];
                  final isCurrentOffer =
                      isUserSubscribed && variant['variant_status'] == true;
                  final hasCheckoutUrl = variant['checkout_url'] != null &&
                      variant['checkout_url'].toString().isNotEmpty;

                  return Column(
                    crossAxisAlignment: _language == 'ar'
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: _language == 'ar'
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (isCurrentOffer) ...[
                            Text(
                              '(${localizations.currentOffer}) ',
                              style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                          Text(
                            variant['name'] ?? localizations.unnamedPlan,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (price != null)
                        Text(
                          localizations.price('\$$price'),
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 14),
                        ),
                      if (duration != null)
                        Text(
                          localizations.duration(duration),
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 14),
                        ),
                      const SizedBox(height: 8),
                      if (hasCheckoutUrl && !isCurrentOffer)
                        _buildActionButton(
                          localizations.swapOffer,
                          Colors.black,
                          () async {
                            try {
                              setState(() => _isLoading = true);
                              await _apiService.changeOffer(
                                  variant['variant_id'].toString());
                              await Future.wait([
                                _loadSubscriptionData(),
                                _loadCustomerPortalUrl(),
                              ]);
                              _showSnackBar(
                                  localizations.offerSwappedSuccessfully);
                              Navigator.pop(context);
                            } catch (e) {
                              setState(() => _isLoading = false);
                              _showSnackBar(
                                  '${localizations.errorSwappingOffer}: $e');
                            }
                          },
                          variant,
                        ),
                      if (subscriptionId != null)
                        _buildActionButton(
                          isCurrentVariant
                              ? localizations.currentPlan
                              : (isUserSubscribed && !isSubscriptionInactive()
                                  ? localizations.changePlan
                                  : localizations.subscribe),
                          isCurrentVariant ? Colors.grey : Colors.black,
                          isCurrentVariant
                              ? null
                              : () async {
                                  try {
                                    setState(() => _isLoading = true);
                                    if (isUserSubscribed &&
                                        !isSubscriptionInactive()) {
                                      await _apiService
                                          .changeOffer(subscriptionId);
                                      _showSnackBar(localizations
                                          .planChangedSuccessfully);
                                    } else {
                                      final checkoutUrl = await _apiService
                                          .buySubscription(subscriptionId);
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => WebViewScreen(
                                            url: checkoutUrl,
                                            onPaymentComplete: () async {
                                              await Future.wait([
                                                _loadSubscriptionData(),
                                                _loadCustomerPortalUrl(),
                                              ]);
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                    await Future.wait([
                                      _loadSubscriptionData(),
                                      _loadCustomerPortalUrl(),
                                    ]);
                                    Navigator.pop(context);
                                  } catch (e) {
                                    setState(() => _isLoading = false);
                                    _showSnackBar(
                                        '${localizations.errorPerformingAction}: $e');
                                  }
                                },
                          variant,
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                })
              else ...[
                if (planData['price'] != null)
                  Text(
                    localizations
                        .price('\$${planData['price'].toStringAsFixed(2)}'),
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                if (discount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    localizations.savePercent(discount),
                    style: TextStyle(color: Colors.green[700], fontSize: 14),
                  ),
                ],
                if (planData['duration'] != null)
                  Text(
                    localizations.duration(planData['duration']),
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                const SizedBox(height: 16),
                if (planData['checkout_data']?['subscription_id'] != null)
                  _buildActionButton(
                    isUserSubscribed && !isSubscriptionInactive()
                        ? localizations.changePlan
                        : localizations.subscribe,
                    Colors.black,
                    () async {
                      final subscriptionId = planData['checkout_data']
                              ['subscription_id']
                          .toString();
                      try {
                        setState(() => _isLoading = true);
                        if (isUserSubscribed && !isSubscriptionInactive()) {
                          await _apiService.changeOffer(subscriptionId);
                          _showSnackBar(localizations.planChangedSuccessfully);
                        } else {
                          final checkoutUrl =
                              await _apiService.buySubscription(subscriptionId);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WebViewScreen(
                                url: checkoutUrl,
                                onPaymentComplete: () async {
                                  await Future.wait([
                                    _loadSubscriptionData(),
                                    _loadCustomerPortalUrl(),
                                  ]);
                                },
                              ),
                            ),
                          );
                        }
                        await Future.wait([
                          _loadSubscriptionData(),
                          _loadCustomerPortalUrl(),
                        ]);
                        Navigator.pop(context);
                      } catch (e) {
                        setState(() => _isLoading = false);
                        _showSnackBar(
                            '${localizations.errorPerformingAction}: $e');
                      }
                    },
                    planData,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, Color? color, VoidCallback? onPressed,
      Map<String, dynamic> planData) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed == null
            ? null
            : () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(localizations.confirmAction),
                    content: Text(localizations.confirmSubscription(
                        planData['name'] ?? localizations.unnamedPlan)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onPressed();
                        },
                        child: Text(localizations.confirm),
                      ),
                    ],
                  ),
                );
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (isSubscriptionInactive()) {
          exit(0);
          return false;
        }
        return true;
      },
      child: Directionality(
        textDirection: _getTextDirection(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(localizations.manageSubscription),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0.8,
          ),
          backgroundColor: Colors.white,
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        localizations.error(_error!),
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: _language == 'ar'
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            _buildSubscriptionStatus(),
                            if (_subscriptionData != null &&
                                _subscriptionData!['subscription'] != null)
                              _buildCurrentSubscription(),
                            _buildAvailablePlans(),
                            if (_customerPortalUrl != null)
                              _buildManageSubscriptionButton(),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionStatus() {
    String message;
    Color statusColor;

    if (_subscriptionData != null && _subscriptionData!['subscribed'] == true) {
      message = localizations.youAreSubscribed;
      statusColor = Colors.green[700]!;
      if (_subscriptionData!['subscription']['renews_at'] != null) {
        final renewsAt = DateFormat('yyyy-MM-dd').format(
            DateTime.parse(_subscriptionData!['subscription']['renews_at']));
        message += '\n${localizations.renewsAt(renewsAt)}';
      }
    } else if (isPaused()) {
      message = localizations.subscriptionPaused;
      statusColor = Colors.orange[700]!;
      if (_billingProvider == 'polar' &&
          _subscriptionData!['subscription']['current_period_end'] != null) {
        final gracePeriodEnd = DateFormat('yyyy-MM-dd').format(DateTime.parse(
            _subscriptionData!['subscription']['current_period_end']));
        message += '\n${localizations.restoreBy(gracePeriodEnd)}';
      }
    } else {
      message = localizations.notSubscribed;
      statusColor = Colors.red[700]!;
    }

    return Column(
      crossAxisAlignment:
          _language == 'ar' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          localizations.subscriptionStatus,
          style: const TextStyle(
              color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: _language == 'ar'
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: statusColor, fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCurrentSubscription() {
    final renewsAt = _subscriptionData!['subscription']['renews_at'] != null
        ? DateFormat('yyyy-MM-dd').format(
            DateTime.parse(_subscriptionData!['subscription']['renews_at']))
        : (_subscriptionData!['subscription']['current_period_end'] != null
            ? DateFormat('yyyy-MM-dd').format(DateTime.parse(
                _subscriptionData!['subscription']['current_period_end']))
            : null);

    Widget? gracePeriodTimer;
    if (_billingProvider == 'polar' && isPaused()) {
      final endDate = DateTime.parse(
          _subscriptionData!['subscription']['current_period_end']);
      gracePeriodTimer = CountdownTimer(endDate: endDate);
    }

    return Column(
      crossAxisAlignment:
          _language == 'ar' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          localizations.currentSubscription,
          style: const TextStyle(
              color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            print('Tapped on current subscription');
            if (_subscriptionData != null &&
                _subscriptionData!['subscription'] != null) {
              _showPlanModal(context, _subscriptionData!['subscription']);
            } else {
              _showSnackBar(localizations.noCurrentSubscription);
            }
          },
          child: SizedBox(
            width: double.infinity,
            child: Card(
              color: Colors.white,
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: _language == 'ar'
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: _language == 'ar'
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              _subscriptionData!['subscription']['plan']
                                      ['name'] ??
                                  localizations.unnamedPlan,
                              style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              localizations.status(
                                  _subscriptionData!['subscription']['status']
                                          ?.toUpperCase() ??
                                      localizations.unknown),
                              style: TextStyle(
                                color: _subscriptionData!['subscription']
                                            ['status'] ==
                                        'active'
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (renewsAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                localizations.renewsAt(renewsAt),
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 14),
                              ),
                            ],
                          ],
                        ),
                        _buildSubscriptionMenu(),
                      ],
                    ),
                    if (gracePeriodTimer != null) ...[
                      const SizedBox(height: 8),
                      gracePeriodTimer,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSubscriptionMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings, color: Colors.black),
      color: Colors.white,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      onSelected: (value) async {
        if (value == 'cancel') {
          await _cancelSubscription();
        } else if (value == 'resume') {
          await _resumeSubscription();
        }
      },
      itemBuilder: (BuildContext context) {
        if (_billingProvider == 'polar' && isPaused()) {
          return [
            PopupMenuItem(
              value: 'resume',
              child: Text(
                localizations.resumePlan,
                style: const TextStyle(color: Colors.black),
                textDirection: _getTextDirection(),
              ),
            ),
            PopupMenuItem(
              value: 'cancel',
              child: Text(
                localizations.cancelPlan,
                style: const TextStyle(color: Colors.black),
                textDirection: _getTextDirection(),
              ),
            ),
          ];
        } else if (_billingProvider == 'lemon_squeezy' && isPaused()) {
          return [
            PopupMenuItem(
              value: 'resume',
              child: Text(
                localizations.resumePlan,
                style: const TextStyle(color: Colors.black),
                textDirection: _getTextDirection(),
              ),
            ),
          ];
        } else {
          return [
            PopupMenuItem(
              value: 'cancel',
              child: Text(
                localizations.cancelPlan,
                style: const TextStyle(color: Colors.black),
                textDirection: _getTextDirection(),
              ),
            ),
          ];
        }
      },
    );
  }

  Widget _buildAvailablePlans() {
    return Column(
      crossAxisAlignment:
          _language == 'ar' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          localizations.availablePlans,
          style: const TextStyle(
              color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_subscriptionData != null && _subscriptionData!['plans'] != null)
          ...(_subscriptionData!['plans'] as List<dynamic>).map<Widget>((plan) {
            final discount = plan['discount'] ?? 0;
            return SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  print('Tapped on plan: ${plan['name']}');
                  _showPlanModal(context, plan);
                },
                child: Card(
                  color: Colors.white,
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: _language == 'ar'
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan['name'] ?? localizations.unnamedPlan,
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        plan['description'] != null
                            ? Html(
                                data: plan['description'],
                                style: {
                                  "body": Style(
                                      fontSize: FontSize(14),
                                      color: Colors.black54),
                                  "li": Style(margin: Margins.only(top: 4)),
                                },
                              )
                            : Text(
                                localizations.noDescriptionAvailable,
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 14),
                              ),
                        if (discount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            localizations.savePercent(discount),
                            style: TextStyle(
                                color: Colors.green[700], fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList()
        else
          Text(
            localizations.noPlansAvailable,
            style: const TextStyle(color: Colors.black54),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildManageSubscriptionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WebViewScreen(
                url: _customerPortalUrl!,
                onPaymentComplete: () async {
                  await Future.wait([
                    _loadSubscriptionData(),
                    _loadCustomerPortalUrl(),
                  ]);
                },
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        child: Text(
          localizations.manageSubscription,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class CountdownTimer extends StatefulWidget {
  final DateTime endDate;

  const CountdownTimer({super.key, required this.endDate});

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Timer _timer;
  Duration _remainingTime = const Duration();

  @override
  void initState() {
    super.initState();
    _updateRemainingTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
  }

  void _updateRemainingTime() {
    final now = DateTime.now();
    final difference = widget.endDate.difference(now);
    if (difference.isNegative) {
      setState(() {
        _remainingTime = const Duration();
      });
      _timer.cancel();
    } else {
      setState(() {
        _remainingTime = difference;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final days = _remainingTime.inDays;
    final hours = _remainingTime.inHours % 24;
    final minutes = _remainingTime.inMinutes % 60;
    final seconds = _remainingTime.inSeconds % 60;

    return Text(
      localizations.timeRemaining(
          '$days days $hours hours $minutes minutes $seconds seconds'),
      style: TextStyle(color: Colors.orange[700], fontSize: 14),
    );
  }
}

class WebViewScreen extends StatelessWidget {
  final String url;
  final VoidCallback? onPaymentComplete;

  const WebViewScreen({super.key, required this.url, this.onPaymentComplete});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.checkout),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0.8,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: true,
        ),
        onLoadStart: (controller, url) => print('Loading: $url'),
        onLoadStop: (controller, url) async {
          print('Loaded: $url');
          if (url.toString().contains('/dashboard')) {
            Navigator.pop(context);
            if (onPaymentComplete != null) {
              onPaymentComplete!();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.paymentCompletedSuccessfully),
              ),
            );
          }
        },
        onLoadError: (controller, url, code, message) {
          print('Load error: $message');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.errorLoadingPage),
              backgroundColor: Colors.red,
            ),
          );
        },
      ),
    );
  }
}
