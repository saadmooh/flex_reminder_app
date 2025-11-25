import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/widgets/custom_app_bar.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';

class EditReminderScreen extends StatefulWidget {
  final int reminderId; // تمرير معرف التذكير بدلاً من كائن التذكير

  const EditReminderScreen({super.key, required this.reminderId});

  @override
  _EditReminderScreenState createState() => _EditReminderScreenState();
}

class _EditReminderScreenState extends State<EditReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late String _importance;
  DateTime? _nextReminderTime;
  bool _isImportanceChanged = false;
  bool _isNextReminderTimeChanged = false;
  bool _isLoading = true;
  Reminder? _reminder;
  late AppLocalizations _localizations;

  final Map<String, Map<String, String>> _importanceOptions = {
    'day': {'en': 'Day', 'ar': 'يوم'},
    'week': {'en': 'Week', 'ar': 'أسبوع'},
    'month': {'en': 'Month', 'ar': 'شهر'},
  };

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
      _titleController = TextEditingController(text: _reminder!.title);
      _importance = _normalizeImportance(_reminder!.importance);
      if (_reminder!.nextReminderTime != null &&
          _reminder!.nextReminderTime!.isNotEmpty) {
        _nextReminderTime = DateTime.parse(_reminder!.nextReminderTime!);
      }
      await _storeReminderId();
    } catch (e) {
      print('خطأ في جلب التذكير: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.error(e.toString())),
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
      await remindersNotifier.forceRefreshReminders();
      print('تم جلب جميع التذكيرات عند إغلاق الشاشة');
    } catch (e) {
      print('خطأ في جلب التذكيرات عند الإغلاق: $e');
    }
  }

  String _normalizeImportance(String? importance) {
    if (importance == null) return 'day';
    if (_importanceOptions.containsKey(importance)) {
      return importance;
    }
    for (var entry in _importanceOptions.entries) {
      if (entry.value['ar'] == importance) {
        return entry.key;
      }
    }
    return 'day';
  }

  @override
  Widget build(BuildContext context) {
    _localizations = AppLocalizations.of(context)!;

    if (_isLoading || _reminder == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_localizations.loading,
              style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        await _clearLastReminderId();
        await _refreshAllReminders();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: CustomAppBar(
          title: _localizations.editReminderTitle,
          showSettings: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
          ),
          child: Card(
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        labelText: _localizations.titleLabel,
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
                      ),
                      enabled: false,
                      validator: (value) => (value == null || value.isEmpty)
                          ? _localizations.requiredField
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildEditToggle(),
                    const SizedBox(height: 16),
                    if (_isImportanceChanged)
                      DropdownButtonFormField<String>(
                        dropdownColor: Colors.white,
                        initialValue: _importance,
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
                        ),
                        items: _importanceOptions.keys.map((String importance) {
                          return DropdownMenuItem<String>(
                            value: importance,
                            enabled: importance !=
                                _normalizeImportance(_reminder!.importance),
                            child: Text(
                              _localizations.locale.languageCode == 'ar'
                                  ? _importanceOptions[importance]!['ar']!
                                  : _importanceOptions[importance]!['en']!,
                              style: const TextStyle(color: Colors.black),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null &&
                              value !=
                                  _normalizeImportance(_reminder!.importance)) {
                            setState(() => _importance = value);
                          }
                        },
                      ),
                    if (_isNextReminderTimeChanged)
                      ListTile(
                        title: Text(
                          _localizations.nextReminderTimeLabel,
                          style: const TextStyle(color: Colors.black),
                        ),
                        subtitle: Text(
                          _nextReminderTime != null
                              ? _nextReminderTime!.toLocal().toString()
                              : _localizations.notSpecified,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: Builder(
                          builder: (BuildContext context) {
                            return IconButton(
                              icon: const Icon(Icons.calendar_today,
                                  color: Colors.black),
                              onPressed: () {
                                print('تم الضغط على زر التقويم');
                                _selectDateTime(context);
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveReminder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
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
      ),
    );
  }

  Widget _buildEditToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () {
            setState(() {
              _isImportanceChanged = true;
              _isNextReminderTimeChanged = false;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          child: Text(
            _localizations.editImportanceButton,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _isImportanceChanged = false;
              _isNextReminderTimeChanged = true;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          child: Text(
            _localizations.editNextReminderTimeButton,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDateTime(BuildContext dialogContext) async {
    print('تم استدعاء _selectDateTime');
    final now = DateTime.now();
    final initialDate =
        _nextReminderTime != null && _nextReminderTime!.isBefore(now)
            ? now
            : _nextReminderTime ?? now;

    final date = await showDatePicker(
      context: dialogContext,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        print('داخل builder لـ DatePicker');
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    ).catchError((e) {
      print('خطأ في showDatePicker: $e');
      return null;
    });

    if (date == null) {
      print('تم إلغاء اختيار التاريخ');
      return;
    }

    final time = await showTimePicker(
      context: dialogContext,
      initialTime: _nextReminderTime != null
          ? TimeOfDay.fromDateTime(_nextReminderTime!)
          : TimeOfDay.now(),
      builder: (context, child) {
        print('داخل builder لـ TimePicker');
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    ).catchError((e) {
      print('خطأ في showTimePicker: $e');
      return null;
    });

    if (time == null) {
      print('تم إلغاء اختيار الوقت');
      return;
    }

    setState(() {
      _nextReminderTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      print('تم تحديث _nextReminderTime إلى: $_nextReminderTime');
    });
  }

  Future<void> _saveReminder() async {
    if (!_formKey.currentState!.validate()) return;

    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);

    if (!_isImportanceChanged && !_isNextReminderTimeChanged) {
      await _clearLastReminderId();
      await _refreshAllReminders();
      Navigator.pop(context);
      return;
    }

    if (_isImportanceChanged &&
        _importance == _normalizeImportance(_reminder!.importance)) {
      setState(() => _isImportanceChanged = false);
    }

    if (_isNextReminderTimeChanged &&
        _nextReminderTime?.toIso8601String() == _reminder!.nextReminderTime) {
      setState(() => _isNextReminderTimeChanged = false);
    }

    if (!_isImportanceChanged && !_isNextReminderTimeChanged) {
      await _clearLastReminderId();
      await _refreshAllReminders();
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isImportanceChanged) {
        final updatedReminder = await remindersNotifier.rescheduleReminder(
          _reminder!.url!,
          _importance,
        );
        await NotificationService().updateReminderNotifications(
          updatedReminder.toJson(),
        );
        await remindersNotifier.updateSingleReminder(updatedReminder.id);
        await _clearLastReminderId();
        await _refreshAllReminders();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizations.reminderUpdatedSuccess),
            backgroundColor: Colors.lightGreen,
          ),
        );
        Navigator.pop(context, updatedReminder);
      } else if (_isNextReminderTimeChanged) {
        final updatedData = {
          'title': _titleController.text,
          'importance': _reminder!.importance,
          'next_reminder_time': _nextReminderTime?.toIso8601String(),
          'url': _reminder!.url,
          'content': _reminder!.content,
          'category': _reminder!.category,
          'complexity': _reminder!.complexity,
          'domain': _reminder!.domain,
          'image_url': _reminder!.imageUrl,
          'is_opened': _reminder!.isOpened,
        };
        await remindersNotifier.updateReminder(_reminder!.id, updatedData);
        await NotificationService().updateReminderNotifications(updatedData);
        await remindersNotifier.updateSingleReminder(_reminder!.id);
        await _clearLastReminderId();
        await _refreshAllReminders();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizations.reminderUpdatedSuccess),
            backgroundColor: Colors.lightGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('خطأ في _saveReminder: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizations.reminderUpdateError(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}
