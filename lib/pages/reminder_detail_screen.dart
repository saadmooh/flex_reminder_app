import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flex_reminder/pages/edit_reminder_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
import 'package:flex_reminder/utils/connectivity_helper.dart';

class ReminderDetailScreen extends StatefulWidget {
  final int reminderId;
  const ReminderDetailScreen({super.key, required this.reminderId});

  @override
  _ReminderDetailScreenState createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  Reminder? _reminder;
  late AppLocalizations localizations;
  bool _isLoadingLink = false;
  bool _isLoading = true;
  bool _hasInternetConnection = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReminder();
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    final hasConnection = await ConnectivityHelper.checkInternetConnection(verbose: true);
    if (mounted) {
      setState(() {
        _hasInternetConnection = hasConnection;
      });
    }
  }

  Future<void> _loadReminder() async {
    final remindersNotifier = Provider.of<RemindersNotifier>(context, listen: false);
    try {
      _reminder = await remindersNotifier.getReminderById(widget.reminderId);
      if (_reminder == null) {
        throw Exception('التذكير غير موجود');
      }
    } catch (e) {
      print('خطأ في جلب التذكير: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.error(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rescheduleReminder() async {
    if (!_hasInternetConnection) {
      _showNoInternetMessage();
      return;
    }

    final remindersNotifier = Provider.of<RemindersNotifier>(context, listen: false);
    try {
      setState(() => _isLoading = true);
      final updatedReminder = await remindersNotifier.rescheduleReminder(
        _reminder!.url!,
        _reminder!.importance!,
      );
      await NotificationService().updateReminderNotifications(updatedReminder.toJson());
        if (mounted) {
      Navigator.pop(context); // <-- هذا السطر هو المفتاح
    }
      setState(() => _reminder = updatedReminder);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.reminderRescheduled),
          backgroundColor: Colors.lightGreen,
        ),
      );
    } catch (e) {
      print('خطأ في إعادة جدولة التذكير: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.error(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showNoInternetMessage() {
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text(localizations.noInternetConnection),
    //     backgroundColor: Colors.orange,
    //   ),
    // );
  }

  @override
  Widget build(BuildContext context) {
    localizations = AppLocalizations.of(context)!;
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(localizations.loading,
              style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_reminder == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(localizations.editReminderTitle,
              style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        body: Center(
            child: Text(localizations.reminderNotProvided,
                style: const TextStyle(color: Colors.black))),
      );
    }
    return WillPopScope(
      onWillPop: () async {
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(_reminder?.title ?? localizations.noTitle,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            _reminder!.isOpened == 1
                ? IconButton(
                    icon: Icon(Icons.refresh, 
                        color: _hasInternetConnection ? Colors.black : Colors.grey),
                    tooltip: _hasInternetConnection 
                        ? localizations.rescheduleReminder
                        : localizations.noInternetConnection,
                    onPressed: _hasInternetConnection ? _rescheduleReminder : null,
                  )
                : IconButton(
                    icon: Icon(Icons.edit, 
                        color: _hasInternetConnection ? Colors.black : Colors.grey),
                    tooltip: _hasInternetConnection 
                        ? localizations.editReminderTitle
                        : localizations.noInternetConnection,
                    onPressed: _hasInternetConnection ? () async {
                      final updatedReminder = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditReminderScreen(
                            reminderId: _reminder!.id,
                          ),
                        ),
                      );
                      if (updatedReminder != null &&
                          updatedReminder is Reminder) {
                        setState(() => _reminder = updatedReminder);
                      }
                    } : () => _showNoInternetMessage(),
                  ),
            _buildDeleteButton(context),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_reminder!.imageUrl != null && _reminder!.imageUrl!.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: _reminder!.imageUrl!,
                  fit: BoxFit.cover,
                  height: 200,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[300],
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: Colors.lightGreen)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.error, color: Colors.red),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reminder?.title ?? localizations.noTitle,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_reminder!.category != null &&
                            _reminder!.category!.isNotEmpty)
                          _buildTag(_reminder!.category!,
                              Colors.lightBlue[100]!, Colors.blue),
                        if (_reminder!.complexity != null &&
                            _reminder!.complexity!.isNotEmpty)
                          _buildTag(_reminder!.complexity!, Colors.orange[100]!,
                              Colors.orange),
                        if (_reminder!.domain != null &&
                            _reminder!.domain!.isNotEmpty)
                          _buildTag(_reminder!.domain!, Colors.green[100]!,
                              Colors.green),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _reminder!.createdAt != null &&
                                _reminder!.createdAt!.isNotEmpty
                            ? _formatDate(_reminder!.createdAt!, context)
                            : localizations.noDate,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          (_reminder?.nextReminderTime?.isNotEmpty ?? false)
                              ? _formatDateTime(_reminder!.nextReminderTime!)
                              : localizations.noReminderSet,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                        '${localizations.importancePrefix} ${_normalizeImportance(_reminder!.importance)}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                    
                    // إضافة قسم عرض شعار واسم الموقع
                    if (_reminder!.siteLogo != null && _reminder!.siteLogo!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: Row(
                          children: [
                            Text(
                              localizations.locale.languageCode == 'ar' ? 'المصدر:' : 'Source:',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: _reminder!.siteLogo!,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.withOpacity(0.1),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.withOpacity(0.1),
                                  child: const Icon(Icons.error, size: 20),
                                ),
                              ),
                            ),
                            if (_reminder!.siteName != null && _reminder!.siteName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Text(
                                  _reminder!.siteName!,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    if (!_hasInternetConnection)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                localizations.noInternetConnection,
                                style: TextStyle(color: Colors.orange[700], fontSize: 14),
                              ),
                            ),
                            TextButton(
                              onPressed: _checkConnectivity,
                              child: Text(
                                localizations.retry,
                                style: TextStyle(color: Colors.orange[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoadingLink || !_hasInternetConnection)
                      ? null
                      : () async {
                          setState(() => _isLoadingLink = true);
                          try {
                            final hasConnection = await ConnectivityHelper.checkInternetConnection();
                            if (!hasConnection) {
                              setState(() => _hasInternetConnection = false);
                              _showNoInternetMessage();
                              return;
                            }
                            final remindersNotifier =
                                Provider.of<RemindersNotifier>(context, listen: false);
                            await remindersNotifier.markReminderAsRead(_reminder!.id);
                            if (!await launchUrlString(_reminder!.url!)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(localizations.unableToOpenLink),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(localizations.error(e.toString())),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            setState(() => _isLoadingLink = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasInternetConnection 
                        ? const Color(0xff050505)
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoadingLink
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _hasInternetConnection 
                              ? localizations.goTo
                              : localizations.noInternetConnection,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeImportance(String? importance) {
    if (importance == null) return 'يوم';
    const importanceMap = {
      'day': {'en': 'Day', 'ar': 'يوم'},
      'week': {'en': 'Week', 'ar': 'أسبوع'},
      'month': {'en': 'Month', 'ar': 'شهر'},
    };
    if (importanceMap.containsKey(importance)) {
      return localizations.locale.languageCode == 'ar'
          ? importanceMap[importance]!['ar']!
          : importanceMap[importance]!['en']!;
    }
    for (var entry in importanceMap.entries) {
      if (entry.value['ar'] == importance || entry.value['en'] == importance) {
        return localizations.locale.languageCode == 'ar'
            ? entry.value['ar']!
            : entry.value['en']!;
      }
    }
    return 'يوم';
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final date = '${dateTime.monthName(context)} ${dateTime.day}, ${dateTime.year}';
      final time = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (e) {
      return localizations.noReminderSet;
    }
  }

  String _formatDate(String dateString, BuildContext context) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.monthName(context)} ${date.day}, ${date.year}';
    } catch (e) {
      return localizations.noDate;
    }
  }

  Widget _buildDeleteButton(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.delete, 
          color: _hasInternetConnection ? Colors.black : Colors.grey),
      tooltip: _hasInternetConnection 
          ? localizations.deleteReminder
          : localizations.noInternetConnection,
      onPressed: _hasInternetConnection ? () async {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(localizations.deleteReminder,
                style: const TextStyle(color: Colors.black)),
            content: Text(localizations.confirmDeleteReminder,
                style: const TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel,
                    style: const TextStyle(color: Colors.lightGreen)),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    if (_reminder != null) {
                      final remindersNotifier =
                          Provider.of<RemindersNotifier>(context, listen: false);
                      await remindersNotifier.deleteReminder(_reminder!.id);
                      Navigator.pop(context);
                      Navigator.pop(context);
                    } else {
                      throw Exception('معرف التذكير مفقود أو غير صالح');
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.error(e.toString())),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(localizations.delete,
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      } : () => _showNoInternetMessage(),
    );
  }

  Widget _buildTag(String text, Color backgroundColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontSize: 12),
      ),
    );
  }
}

extension DateTimeExtension on DateTime {
  String monthName(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    const monthsEn = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    const monthsAr = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    return localizations.locale.languageCode == 'ar'
        ? monthsAr[month - 1]
        : monthsEn[month - 1];
  }
}