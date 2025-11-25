import 'package:flutter/material.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class LowerNavigationBar extends StatelessWidget {
  final int? currentIndex; // تغيير إلى nullable
  final Function(int)? onTap;

  const LowerNavigationBar({
    super.key,
    this.currentIndex, // جعله اختياري
    this.onTap,
  });

  void _navigate(BuildContext context, int index) {
    final List<String> routes = [
      '/reminders',
      '/stats',
      '/time_slots',
    ];

    // إذا كان الفهرس الحالي هو نفس الفهرس المضغوط، لا نفعل شيئًا
    if (currentIndex == index) return;

    Navigator.pushNamed(context, routes[index], arguments: index);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return BottomNavigationBar(
      currentIndex: currentIndex ?? -1, // استخدام -1 عندما لا نريد تحديد أي زر
      onTap: (index) => _navigate(context, index),
      backgroundColor: Colors.white,
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.black.withOpacity(0.6),
      type: BottomNavigationBarType.fixed, // ضروري عند استخدام currentIndex = -1
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
          icon: const Icon(Icons.access_time),
          label: localizations.timeSlots,
        ),
      ],
    );
  }
}