import 'package:flutter/material.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/models/user_free_time.dart';
import 'package:flex_reminder/widgets/upper_app_bar.dart';
import 'package:flex_reminder/widgets/lower_navigation_bar.dart';
import 'package:flex_reminder/l10n/app_localizations.dart'; // استيراد الترجمة
import '../services/api_functions/exceptions.dart'; // <-- استيراد الاستثناء الجديد

class TimeSlotsScreen extends StatefulWidget {
  final int initialIndex;

  const TimeSlotsScreen({super.key, this.initialIndex = 2});

  @override
  _TimeSlotsScreenState createState() => _TimeSlotsScreenState();
}

class _TimeSlotsScreenState extends State<TimeSlotsScreen> {
  final ApiService _apiService = ApiService();
  List<UserFreeTime> _freeTimes = [];
  bool _isLoading = true;

  // قائمة الأيام باللغة الإنجليزية لإرسالها إلى الـ API
  final List<String> _daysOfWeekApi = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  // دالة لتحويل اليوم من العرض إلى القيمة المرسلة للـ API
  String _convertDayToApiFormat(String displayDay) {
    final localizations = AppLocalizations.of(context)!;
    // Map the display day (translated) back to the API day (English)
    final dayMap = {
      localizations.monday.toLowerCase(): 'monday',
      localizations.tuesday.toLowerCase(): 'tuesday',
      localizations.wednesday.toLowerCase(): 'wednesday',
      localizations.thursday.toLowerCase(): 'thursday',
      localizations.friday.toLowerCase(): 'friday',
      localizations.saturday.toLowerCase(): 'saturday',
      localizations.sunday.toLowerCase(): 'sunday',
    };
    return dayMap[displayDay.toLowerCase()] ?? displayDay;
  }

  // دالة لتحويل اليوم من القيمة المرسلة للـ API إلى العرض
  String _convertDayFromApiFormat(String apiDay) {
    final localizations = AppLocalizations.of(context)!;
    // Map the API day (English) to the translated display day
    switch (apiDay.toLowerCase()) {
      case 'monday':
        return localizations.monday;
      case 'tuesday':
        return localizations.tuesday;
      case 'wednesday':
        return localizations.wednesday;
      case 'thursday':
        return localizations.thursday;
      case 'friday':
        return localizations.friday;
      case 'saturday':
        return localizations.saturday;
      case 'sunday':
        return localizations.sunday;
      default:
        return apiDay; // Fallback to the API day if not found
    }
  }

  int _currentNavIndex = 2;
  late AppLocalizations localizations; // متغير لتخزين الترجمة

  @override
  void initState() {
    super.initState();
    _currentNavIndex = widget.initialIndex;
    _loadFreeTimes();
  }

  Future<void> _loadFreeTimes() async {
    setState(() => _isLoading = true);
    try {
      final freeTimes = await _apiService.fetchFreeTimes();
      setState(() {
        _freeTimes = freeTimes;
      });
    } on NoValidSubscriptionException {
      // تم التعامل مع الخطأ بالفعل في UtilsService (تسجيل الخروج)
      // لذلك لا نعرض أي رسالة خطأ للمستخدم وننهي التنفيذ
      return;
    } catch (error) {
      // عرض رسالة الخطأ للأخطاء الأخرى فقط
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.errorLoadingFreeTimes(error.toString())),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFreeTime(int id) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[800],
          title: Text(
            localizations.confirmDelete,
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            localizations.areYouSureDelete,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                localizations.cancel,
                style: const TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                localizations.delete,
                style: const TextStyle(color: Colors.red),
              ),
              onPressed: () async {
                try {
                  await _apiService.deleteFreeTime(id);
                  _loadFreeTimes();
                  Navigator.of(context).pop();
                } on NoValidSubscriptionException {
                  // تم التعامل مع الخطأ بالفعل في UtilsService (تسجيل الخروج)
                  Navigator.of(context).pop(); // إغلاق الديالوج أولاً
                  return;
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          localizations.errorDeletingFreeTime(e.toString())),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    localizations = AppLocalizations.of(context)!; // تهيئة الترجمة
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        appBar: UpperAppBar(
          title: localizations.freeTimes,
          showSearch: false,
          showSettings: true,
          showLeading: true,
        ),
        backgroundColor: Colors.white,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: _daysOfWeekApi.map((apiDay) {
                          return _buildDayColumn(apiDay);
                        }).toList(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, // لون الخلفية الأسود
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero, // بدون حواف منحنية
                        ),
                        minimumSize: const Size(double.infinity,
                            0), // جعل العرض يأخذ كامل المساحة المتاحة
                      ),
                      onPressed: () {
                        _showTimeSlotDialog();
                      },
                      child: Text(
                        localizations.addFreeTime,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: LowerNavigationBar(
          currentIndex: _currentNavIndex,
        ),
      ),
    );
  }

  Widget _buildDayColumn(String apiDay) {
    final displayDay = _convertDayFromApiFormat(apiDay);
    final List<UserFreeTime> todaysFreeTimes = _freeTimes
        .where((time) => time.day.toLowerCase() == apiDay.toLowerCase())
        .toList();

    bool isDayOff = todaysFreeTimes.any((time) => time.isOffDay);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  displayDay.toUpperCase(),
                  style: TextStyle(
                    color: isDayOff ? Colors.grey[600] : Colors.green[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Switch(
                  value: isDayOff,
                  activeThumbColor: Colors.red,
                  onChanged: (bool value) async {
                    try {
                      if (value) {
                        await _apiService.createFreeTime(
                          apiDay, // إرسال اليوم باللغة الإنجليزية
                          const TimeOfDay(hour: 0, minute: 0),
                          const TimeOfDay(hour: 23, minute: 59),
                          true,
                        );
                      } else {
                        for (var time in todaysFreeTimes) {
                          if (time.id != null) {
                            await _apiService.deleteFreeTime(time.id!);
                          }
                        }
                      }
                      _loadFreeTimes();
                    } on NoValidSubscriptionException {
                      // تم التعامل مع الخطأ بالفعل في UtilsService (تسجيل الخروج)
                      return;
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              localizations.errorUpdatingDayOff(e.toString())),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          if (isDayOff)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                localizations.dayOff,
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else ...[
            ...todaysFreeTimes
                .where((time) => !time.isOffDay)
                .map((freeTime) => _buildTimeSlotItem(freeTime)),
            if (todaysFreeTimes.where((time) => !time.isOffDay).isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  localizations.noFreeTimes,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showTimeSlotDialog({UserFreeTime? existingTime}) async {
    final availableDaysApi = _daysOfWeekApi
        .where((apiDay) => !_freeTimes.any(
              (time) =>
                  time.day.toLowerCase() == apiDay.toLowerCase() &&
                  time.isOffDay,
            ))
        .toList();

    final availableDaysDisplay = availableDaysApi
        .map((apiDay) => _convertDayFromApiFormat(apiDay))
        .toList();

    if (existingTime != null) {
      final existingDayApi = existingTime.day.toLowerCase();
      if (!availableDaysApi.any((d) => d.toLowerCase() == existingDayApi)) {
        availableDaysApi.add(existingTime.day);
        availableDaysDisplay.add(_convertDayFromApiFormat(existingTime.day));
      }
    }

    if (availableDaysApi.isEmpty && existingTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.noDaysAvailable),
        ),
      );
      return;
    }

    String selectedDayDisplay = existingTime != null
        ? _convertDayFromApiFormat(existingTime.day)
        : availableDaysDisplay.first;

    TimeOfDay selectedStartTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay selectedEndTime = const TimeOfDay(hour: 17, minute: 0);

    if (existingTime != null) {
      final parsedStart = _parseTimeOfDay(existingTime.startTime);
      final parsedEnd = _parseTimeOfDay(existingTime.endTime);
      if (parsedStart != null) selectedStartTime = parsedStart;
      if (parsedEnd != null) selectedEndTime = parsedEnd;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[800],
              title: Text(
                existingTime == null
                    ? localizations.addFreeTime
                    : localizations.editFreeTime,
                style: const TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedDayDisplay,
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: localizations.day,
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.grey[900],
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.blue),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        hintStyle: const TextStyle(color: Colors.white70),
                      ),
                      items: availableDaysDisplay.map((day) {
                        return DropdownMenuItem(
                          value: day,
                          child: Text(day,
                              style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedDayDisplay = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: Text(
                        '${localizations.startTime}: ${selectedStartTime.format(context)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing:
                          const Icon(Icons.access_time, color: Colors.white),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedStartTime,
                          builder: (BuildContext context, Widget? child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Colors.blue,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.white,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedStartTime = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: Text(
                        '${localizations.endTime}: ${selectedEndTime.format(context)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing:
                          const Icon(Icons.access_time, color: Colors.white),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime,
                          builder: (BuildContext context, Widget? child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Colors.blue,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.white,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedEndTime = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(
                    localizations.cancel,
                    style: const TextStyle(color: Colors.red),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(
                    existingTime == null
                        ? localizations.addFreeTime
                        : localizations.editFreeTime,
                    style: const TextStyle(color: Colors.blue),
                  ),
                  onPressed: () async {
                    final selectedDayApi =
                        _convertDayToApiFormat(selectedDayDisplay);
                    final userChoice = await _checkAndHandleOverlap(
                      selectedDay: selectedDayApi,
                      startTime: selectedStartTime,
                      endTime: selectedEndTime,
                      existingId: existingTime?.id,
                    );

                    if (userChoice == _OverlapAction.cancel) {
                      Navigator.of(context).pop();
                      return;
                    } else if (userChoice == _OverlapAction.mergeAndSave) {
                      _loadFreeTimes();
                      Navigator.of(context).pop();
                      return;
                    }

                    try {
                      if (existingTime == null) {
                        await _apiService.createFreeTime(
                          selectedDayApi,
                          selectedStartTime,
                          selectedEndTime,
                          false,
                        );
                      } else {
                        final result = await _apiService.updateFreeTime(
                          existingTime.id!,
                          selectedDayApi,
                          selectedStartTime,
                          selectedEndTime,
                          false,
                        );
                        if (result['success'] != true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations
                                  .updateFailed(result["message"])),
                            ),
                          );
                          return;
                        }
                      }
                      _loadFreeTimes();
                      Navigator.of(context).pop();
                    } on NoValidSubscriptionException {
                      // تم التعامل مع الخطأ بالفعل في UtilsService (تسجيل الخروج)
                      Navigator.of(context).pop(); // إغلاق الديالوج أولاً
                      return;
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(localizations.error(e.toString())),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_OverlapAction> _checkAndHandleOverlap({
    required String selectedDay,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    int? existingId,
  }) async {
    final sameDaySlots = _freeTimes.where((slot) {
      if (slot.isOffDay) return false;
      if (slot.day.toLowerCase() != selectedDay.toLowerCase()) return false;
      if (existingId != null && slot.id == existingId) return false;
      return true;
    }).toList();

    int newStart = startTime.hour * 60 + startTime.minute;
    int newEnd = endTime.hour * 60 + endTime.minute;

    if (newEnd <= newStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.invalidTimeRange),
        ),
      );
      return _OverlapAction.cancel;
    }

    List<UserFreeTime> overlappingSlots = [];
    for (var slot in sameDaySlots) {
      final st = _parseTimeOfDay(slot.startTime);
      final en = _parseTimeOfDay(slot.endTime);
      if (st == null || en == null) continue;

      int slotStart = st.hour * 60 + st.minute;
      int slotEnd = en.hour * 60 + en.minute;

      if (newStart < slotEnd && newEnd > slotStart) {
        overlappingSlots.add(slot);
      }
    }

    if (overlappingSlots.isEmpty) {
      return _OverlapAction.noOverlap;
    }

    final action = await showDialog<_OverlapAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(localizations.overlapDetected),
          content: Text(
              localizations.overlapMessage(overlappingSlots.length.toString())),
          actions: [
            TextButton(
              child: Text(localizations.cancel),
              onPressed: () => Navigator.pop(context, _OverlapAction.cancel),
            ),
            TextButton(
              child: Text(localizations.merge),
              onPressed: () =>
                  Navigator.pop(context, _OverlapAction.mergeAndSave),
            ),
          ],
        );
      },
    );

    if (action == null || action == _OverlapAction.cancel) {
      return _OverlapAction.cancel;
    }

    if (action == _OverlapAction.mergeAndSave) {
      int earliest = newStart;
      int latest = newEnd;

      for (var slot in overlappingSlots) {
        final st = _parseTimeOfDay(slot.startTime)!;
        final en = _parseTimeOfDay(slot.endTime)!;
        int s = st.hour * 60 + st.minute;
        int e = en.hour * 60 + en.minute;
        if (s < earliest) earliest = s;
        if (e > latest) latest = e;
      }

      if (existingId != null) {
        await _apiService.deleteFreeTime(existingId);
      }

      for (var slot in overlappingSlots) {
        if (slot.id != null) {
          await _apiService.deleteFreeTime(slot.id!);
        }
      }

      final mergedStart =
          TimeOfDay(hour: earliest ~/ 60, minute: earliest % 60);
      final mergedEnd = TimeOfDay(hour: latest ~/ 60, minute: latest % 60);

      await _apiService.createFreeTime(
        selectedDay,
        mergedStart,
        mergedEnd,
        false,
      );

      return _OverlapAction.mergeAndSave;
    }

    return _OverlapAction.cancel;
  }

  Widget _buildTimeSlotItem(UserFreeTime freeTime) {
    return GestureDetector(
      onTap: () {
        _showTimeSlotDialog(existingTime: freeTime);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: freeTime.isOffDay ? Colors.grey[300] : Colors.green[100],
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: freeTime.isOffDay ? Colors.grey : Colors.green[800]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${freeTime.startTime} - ${freeTime.endTime}',
              style: TextStyle(
                color: freeTime.isOffDay ? Colors.grey[700] : Colors.green[900],
                fontWeight: FontWeight.bold,
              ),
            ),
            if (freeTime.isOffDay)
              Text(
                localizations.dayOff,
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () {
                    _showTimeSlotDialog(existingTime: freeTime);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _deleteFreeTime(freeTime.id!);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay? _parseTimeOfDay(String timeString) {
    final parts = timeString.split(':');
    if (parts.length < 2) return null;

    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print("Cannot parse time $timeString: $e");
      return null;
    }
  }
}

enum _OverlapAction {
  noOverlap,
  mergeAndSave,
  cancel,
}
