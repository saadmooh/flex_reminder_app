import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flex_reminder/pages/edit_reminder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';

class ReminderDetailScreen extends StatefulWidget {
  final int reminderId;

  const ReminderDetailScreen({Key? key, required this.reminderId})
      : super(key: key);

  @override
  _ReminderDetailScreenState createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  Reminder? _reminder;
  late AppLocalizations localizations;
  bool _isLoadingLink = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReminder();
    });
  }

  Future<void> _loadReminder() async {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    try {
      _reminder = await remindersNotifier.getReminderById(widget.reminderId);
      if (_reminder == null) {
        throw Exception('التذكير غير موجود');
      }
      await _storeReminderId();
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

  Future<void> _storeReminderId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_reminder_id', widget.reminderId);
    print('تم حفظ معرف التذكير ${widget.reminderId} في التخزين المحلي');
  }

  Future<void> _clearLastReminderId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_reminder_id');
    print('تم إزالة معرف التذكير الأخير من التخزين المحلي');
  }

  Future<void> _refreshAllReminders() async {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    try {
      await remindersNotifier.fetchReminders(forceFetch: true);
      print('تم جلب جميع التذكيرات من السيرفر عند إغلاق الشاشة');
    } catch (e) {
      print('خطأ في جلب التذكيرات عند الإغلاق: $e');
    }
  }

  Future<void> _rescheduleReminder() async {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    try {
      setState(() => _isLoading = true);
      final response = await ApiService().reschedulePost(
        _reminder!.url!,
        _reminder!.importance!,
      );
      if (response['success'] == true) {
        // تحديث التذكير في Notifier
        final updatedReminder = Reminder.fromJson(response['post']);
        await remindersNotifier.updateSingleReminder(updatedReminder.id!);
        setState(() => _reminder = updatedReminder);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.reminderRescheduled),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to reschedule reminder');
      }
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
        await _clearLastReminderId();
        await _refreshAllReminders();
        Navigator.pop(context, {'type': 'update', 'id': _reminder!.id});
        return false;
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
            // عرض زر Edit أو Reset بناءً على حالة isOpened
            _reminder!.isOpened == 1
                ? IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    tooltip: localizations.rescheduleReminder,
                    onPressed: _rescheduleReminder,
                  )
                : IconButton(
                    icon: const Icon(Icons.edit, color: Colors.black),
                    tooltip: localizations.editReminderTitle,
                    onPressed: () async {
                      final updatedReminder = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditReminderScreen(
                            reminderId: _reminder!.id!,
                          ),
                        ),
                      );
                      if (updatedReminder != null &&
                          updatedReminder is Reminder) {
                        setState(() => _reminder = updatedReminder);
                        await _clearLastReminderId();
                        await _refreshAllReminders();
                        Navigator.pop(
                            context, {'type': 'update', 'id': _reminder!.id});
                      }
                    },
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
                              ? _reminder!.nextReminderTime!
                              : localizations.noReminderSet,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                        '${localizations.importancePrefix} ${_reminder!.importance}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 24),
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
                  onPressed: _isLoadingLink
                      ? null
                      : () async {
                          setState(() => _isLoadingLink = true);
                          try {
                            await ApiService()
                                .updateStats(_reminder!.url!, true);
                            final remindersNotifier =
                                Provider.of<RemindersNotifier>(context,
                                    listen: false);
                            await remindersNotifier
                                .updateSingleReminder(_reminder!.id!);
                            if (!await launchUrlString(_reminder!.url!)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(localizations.unableToOpenLink),
                                  backgroundColor: const Color(0xfffb0a0a),
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
                    backgroundColor: const Color(0xff050505),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoadingLink
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          localizations.goTo,
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

  String _formatDate(String dateString, BuildContext context) {
    final date = DateTime.parse(dateString);
    return '${date.monthName(context)} ${date.day}، ${date.year}';
  }

  Widget _buildDeleteButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete, color: Colors.black),
      tooltip: localizations.deleteReminder,
      onPressed: () async {
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
                    if (_reminder != null && _reminder!.id != null) {
                      await ApiService().deleteReminder(_reminder!.id!);
                      await NotificationService()
                          .cancelReminderNotifications(_reminder!.id!);
                      await _clearLastReminderId();
                      await _refreshAllReminders();
                      Navigator.pop(context);
                      Navigator.pop(
                          context, {'type': 'delete', 'id': _reminder!.id});
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
      },
    );
  }

  Widget _buildTag(String text, Color backgroundColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: backgroundColor, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 12)),
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
