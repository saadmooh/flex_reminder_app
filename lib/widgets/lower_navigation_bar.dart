import 'package:flutter/material.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class LowerNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int)? onTap; // جعل onTap اختياريًا

  const LowerNavigationBar({
    Key? key,
    required this.currentIndex,
    this.onTap, // لن نستخدمه مباشرة، لكن سنتركه للتوافق
  }) : super(key: key);

  // دالة التنقل المركزية
  void _navigate(BuildContext context, int index) {
    final List<String> routes = [
      '/reminders', // المسار الأساسي الآن هو /reminders
      '/stats',
      '/time_slots',
    ];

    // إذا كان الفهرس الحالي هو نفس الفهرس المضغوط، لا نفعل شيئًا
    if (currentIndex == index) return;

    // التنقل باستخدام pushNamed للحفاظ على مكدس التنقل
    Navigator.pushNamed(context, routes[index], arguments: index);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) =>
          _navigate(context, index), // استخدام دالة التنقل المركزية
      backgroundColor: Colors.white,
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.black.withOpacity(0.6),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home),
          label: localizations.home ?? 'Home',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.analytics),
          label: localizations.stats,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.access_time), // تغيير الأيقونة إلى Time Slots
          label: localizations.timeSlots,
        ),
      ],
    );
  }
}
