import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
// ************** إضافة استيراد جديد **************
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io'; // يحتوي على SocketException وHttpException
import 'dart:async'; // يحتوي على TimeoutException

class SavePostScreen extends StatefulWidget {
  final String? initialUrl;
  final VoidCallback? onSave;

  const SavePostScreen({super.key, this.initialUrl, this.onSave});

  @override
  _SavePostScreenState createState() => _SavePostScreenState();
}

class _SavePostScreenState extends State<SavePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  String _selectedImportance = 'day';
  final Map<String, Map<String, String>> _importanceOptions = {
    'day': {'en': 'Day', 'ar': 'يوم'},
    'week': {'en': 'Week', 'ar': 'أسبوع'},
    'month': {'en': 'Month', 'ar': 'شهر'},
  };
  bool _isLoading = false;
  bool _isInitializing = true;

  // ************** إضافة متغير جديد **************
  bool _hasInternetConnection = true; // افتراضيًا أن هناك اتصال

  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  late AppLocalizations _localizations;

  // خريطة لربط الإزاحات الزمنية باختصارات المناطق الزمنية (بدون const)
  static final Map<Duration, String> _timeZoneAbbreviations = {
    const Duration(hours: 1): 'CET', // التوقيت الرسمي لوسط أوروبا
    const Duration(hours: 2): 'CEST', // التوقيت الصيفي لوسط أوروبا
    const Duration(hours: 0): 'UTC', // التوقيت العالمي
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }
    _initServices();
    // ************** تعديل: استدعاء دالة التحقق من الاتصال **************
    _checkConnectivity();
  }

  Future<void> _initServices() async {
    setState(() {
      _isInitializing = true;
    });

    await _initNotifications();

    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _initNotifications() async {
    await _notificationService.init();
    bool permissionsGranted = await _notificationService.checkPermissions();
    print('حالة أذونات الإشعارات: $permissionsGranted');
    if (!permissionsGranted) {
      bool granted = await _notificationService.requestPermissions();
      print('تم طلب الأذونات، النتيجة: $granted');
    }
  }

  // ************** إضافة دالة جديدة **************
  Future<void> _checkConnectivity() async {
    try {
      final List<ConnectivityResult> connectivityResult =
          await Connectivity().checkConnectivity();
      final hasConnection =
          connectivityResult.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _hasInternetConnection = hasConnection;
        });
      }
    } catch (e) {
      print('خطأ في التحقق من الاتصال: $e');
      if (mounted) {
        setState(() {
          _hasInternetConnection = false;
        });
      }
    }
  }

  // دالة لاستخراج اختصار المنطقة الزمنية بناءً على الإزاحة
  String _getTimeZoneAbbreviation(DateTime dateTime) {
    final offset = dateTime.timeZoneOffset;
    return _timeZoneAbbreviations[offset] ?? 'Unknown';
  }

  Future<void> _schedulePostNotification(
      String title, int id, String nextReminderTime) async {
    try {
      // تحليل nextReminderTime
      final DateTime scheduledDate = DateTime.parse(nextReminderTime);
      final String timeZoneAbbr = _getTimeZoneAbbreviation(scheduledDate);
      final String notificationTitle = _localizations.timeToReview(title);
      final String notificationBody = _localizations.tapToViewDetails;

      print('جدولة الإشعار الرئيسي:');
      print('العنوان: $notificationTitle');
      print('النص: $notificationBody');
      print('التاريخ المجدول: $scheduledDate ($timeZoneAbbr)');

      // جدولة الإشعار الرئيسي (مرئي مع صوت)
      bool success = await _notificationService.scheduleNotification(
        title: notificationTitle,
        body: notificationBody,
        scheduledDate: scheduledDate,
        channelKey: 'scheduled_channel',
        summary: _localizations.postNotificationSummary,
        payload: {
          'id': id.toString(),
          'url': _urlController.text,
          'title': title,
          'importance': _selectedImportance,
          'nextReminderTime': scheduledDate.toIso8601String(),
        },
        isPostNotification: false,
      );
      print('نجاح جدولة الإشعار الرئيسي: $success');

      // جدولة إشعار الفحص (صامت ومخفي) بعد ساعة من الإشعار الرئيسي
      final DateTime checkDate = scheduledDate.add(const Duration(hours: 1));
      final String checkTimeZoneAbbr = _getTimeZoneAbbreviation(checkDate);
      print('جدولة إشعار الفحص:');
      print('العنوان: إشعار الفحص');
      print('التاريخ المجدول: $checkDate ($checkTimeZoneAbbr)');

      success = await _notificationService.scheduleNotification(
        title: 'إشعار الفحص',
        body: 'التحقق مما إذا تم فتح التذكير.',
        scheduledDate: checkDate,
        channelKey: 'check_channel',
        summary: 'فحص التذكير',
        payload: {
          'id': id.toString(),
          'url': _urlController.text,
          'title': title,
          'importance': _selectedImportance,
          'nextReminderTime': scheduledDate.toIso8601String(),
          'isCheckNotification': 'true',
        },
        isPostNotification: false,
      );
      print('نجاح جدولة إشعار الفحص: $success');
    } catch (e) {
      print('خطأ أثناء جدولة الإشعارات: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_localizations.errorSchedulingNotification(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _savePost() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasInternetConnection) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizations.noInternetConnection)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = _urlController.text.trim();
      final importance = _selectedImportance;

      final data = {
        'url': url,
        'importance_en': _importanceOptions[importance]!['en'],
        'importance_ar': _importanceOptions[importance]!['ar'],
      };

      final result = await _apiService.savePost(data);

      if (result['success'] == true) {
        final title = result['title']?.toString() ?? 'Untitled Post';
        final id = result['id'];
        final nextReminderTime = result['nextReminderTime']?.toString();

        if (id == null || nextReminderTime == null) {
          throw Exception(_localizations.missingDataFromServer);
        }

        await _schedulePostNotification(title, id, nextReminderTime);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ المنشور'),
            backgroundColor: Colors.lightGreen,
          ),
        );

        widget.onSave?.call();
        Navigator.pop(context, true);
      } else {
        final msg = result['message'];
        final errorMsg = (msg is String && msg.isNotEmpty)
            ? msg
            : _localizations.unknownError;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (error, stackTrace) {
      print('Save error: $error\n$stackTrace');
      String userMessage;

      if (error is SocketException || error is TimeoutException) {
        userMessage = _localizations.noInternetConnection;
      } else if (error is HttpException) {
        userMessage = _localizations.serverError;
      } else if (error is FormatException) {
        userMessage = _localizations.invalidResponseFromServer;
      } else {
        userMessage = error.toString().contains('HttpException')
            ? _localizations.serverError
            : _localizations.postSaveFailedGeneral;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: _localizations.retry,
            onPressed: _savePost,
            textColor: Colors.white,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _localizations = AppLocalizations.of(context)!;

    if (_isInitializing) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'جار التحميل...',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Card(
          color: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _localizations.saveButton,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16.0),
                  TextFormField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: _localizations.urlLabel,
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.blue),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      hintStyle: const TextStyle(color: Colors.grey),
                    ),
                    onChanged: (value) {
                      // استخراج الرابط من النص إذا كان هناك مسافات
                      if (value.contains(' ')) {
                        final urlRegex = RegExp(
                          r'(http(s)?:\/\/.)[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)',
                        );
                        final match = urlRegex.firstMatch(value);
                        if (match != null) {
                          final extractedUrl = match.group(0)!;
                          _urlController.value = TextEditingValue(
                            text: extractedUrl,
                            selection: TextSelection.collapsed(
                                offset: extractedUrl.length),
                          );
                        }
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return _localizations.urlRequired;
                      }
                      final urlRegex = RegExp(
                        r'^(http(s)?:\/\/.)[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)$',
                      );
                      if (!urlRegex.hasMatch(value)) {
                        return _localizations.invalidUrl;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16.0),
                  DropdownButtonFormField<String>(
                    dropdownColor: Colors.white,
                    initialValue: _selectedImportance,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: _localizations.importanceLabel,
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.blue),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      hintStyle: const TextStyle(color: Colors.grey),
                    ),
                    items: _importanceOptions.keys.map((String importance) {
                      return DropdownMenuItem<String>(
                        value: importance,
                        child: Text(
                          _localizations.locale.languageCode == 'ar'
                              ? _importanceOptions[importance]!['ar']!
                              : _importanceOptions[importance]!['en']!,
                          style: const TextStyle(color: Colors.black),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedImportance = newValue!;
                      });
                    },
                  ),
                  // ************** إضافة: رسالة عدم الاتصال **************
                  if (!_hasInternetConnection)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off,
                                color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _localizations.noInternetConnection,
                                style: TextStyle(
                                    color: Colors.orange[700], fontSize: 14),
                              ),
                            ),
                            TextButton(
                              onPressed: _checkConnectivity,
                              child: Text(
                                _localizations.retry,
                                style: TextStyle(color: Colors.orange[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ************** نهاية الإضافة **************
                  const SizedBox(height: 32.0),
                  ElevatedButton(
                    // ************** تعديل: تعطيل الزر وتغيير اللون **************
                    onPressed: (_isLoading || !_hasInternetConnection)
                        ? null
                        : _savePost,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasInternetConnection
                          ? const Color(0xff030500)
                          : Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                    ),
                    // ************** نهاية التعديل **************
                    child: _isLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'جار الحفظ...',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          )
                        : Text(
                            _localizations.saveButton,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
