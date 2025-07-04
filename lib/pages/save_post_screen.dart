import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class SavePostScreen extends StatefulWidget {
  final String? initialUrl;
  final VoidCallback? onSave;

  const SavePostScreen({Key? key, this.initialUrl, this.onSave})
      : super(key: key);

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

  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  late AppLocalizations _localizations;

  // خريطة لربط الإزاحات الزمنية باختصارات المناطق الزمنية (بدون const)
  static final Map<Duration, String> _timeZoneAbbreviations = {
    Duration(hours: 1): 'CET', // التوقيت الرسمي لوسط أوروبا
    Duration(hours: 2): 'CEST', // التوقيت الصيفي لوسط أوروبا
    Duration(hours: 0): 'UTC', // التوقيت العالمي
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }
    _initServices();
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final url = _urlController.text.trim();
      if (url.isEmpty) {
        throw Exception(_localizations.urlRequired);
      }

      final importance = _selectedImportance;
      if (importance.isEmpty) {
        throw Exception(_localizations.importanceRequired);
      }

      Map<String, dynamic> data = {
        'url': url,
        'importance_en': _importanceOptions[importance]!['en'],
        'importance_ar': _importanceOptions[importance]!['ar'],
      };

      final result = await _apiService.savePost(data);

      if (result['success'] == true) {
        final title = result['title'] ?? 'Untitled Post';
        final id = result['id'];
        final nextReminderTime = result['nextReminderTime'];

        if (id == null) {
          throw Exception('معرف التذكير مفقود في استجابة الخادم');
        }
        if (title.isEmpty) {
          throw Exception(_localizations.titleMissing);
        }
        if (nextReminderTime == null || nextReminderTime.isEmpty) {
          throw Exception(_localizations.nextReminderTimeMissing);
        }

        await _schedulePostNotification(title, id, nextReminderTime);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ المنشور'),
            backgroundColor: Colors.lightGreen,
            duration: const Duration(seconds: 3),
          ),
        );

        widget.onSave?.call();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizations
                  .postSaveFailed(result['message'] ?? 'خطأ غير معروف'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      print('خطأ أثناء حفظ المنشور: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.postSaveError(error.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                    value: _selectedImportance,
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
                  const SizedBox(height: 32.0),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _savePost,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff030500),
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'جار الحفظ...',
                                style: const TextStyle(color: Colors.white),
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
