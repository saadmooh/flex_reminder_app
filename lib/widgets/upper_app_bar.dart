import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';
// للوصول إلى navigatorKey
import 'package:flex_reminder/services/authentication_service.dart';

class UpperAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showSearch;
  final VoidCallback? onSearchPressed;
  final bool showSettings;
  final bool showLeading;
  final List<Widget>? actions;

  const UpperAppBar({
    super.key,
    this.title,
    this.showSearch = false,
    this.onSearchPressed,
    this.showSettings = true,
    this.showLeading = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageManager =
        Provider.of<LanguageManager>(context, listen: false);
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    final isArabic = languageManager.locale.languageCode == 'ar';
    final currentRoute = ModalRoute.of(context)?.settings.name;

    // Remove back button entirely on /reminders regardless of showLeading
    final bool hideLeading = currentRoute == '/reminders';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        automaticallyImplyLeading: false,
        leading: (showLeading && !hideLeading)
            ? IconButton(
                icon: Icon(
                  isArabic ? Icons.chevron_right : Icons.chevron_left,
                  color: Colors.black,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            : null,
        title: title != null
            ? Text(
                title!,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              )
            : null,
        centerTitle: true,
        actions: [
          // Search button
          if (showSearch && onSearchPressed != null)
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: onSearchPressed,
              tooltip: localizations.searchReminders,
            ),

          // Language selector
          PopupMenuButton<String>(
            color: Colors.white,
            icon: const Icon(Icons.language, color: Colors.black),
            onSelected: (value) async {
              try {
                await ApiService().updateLanguage(value);
                if (value == 'en') {
                  languageManager.setLocale(const Locale('en'));
                } else if (value == 'ar') {
                  languageManager.setLocale(const Locale('ar'));
                } else if (value == 'zh') {
                  languageManager.setLocale(const Locale('zh'));
                }
                await remindersNotifier.forceRefreshReminders();
                final currentRoute = ModalRoute.of(context)?.settings.name;
                if (currentRoute != null) {
                  Navigator.pushReplacementNamed(context, currentRoute);
                } else {
                  Navigator.pushReplacementNamed(context, '/reminders');
                }
              } catch (e) {
                print('Error updating language: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(localizations.languageUpdateFailed),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'en',
                child: Text(
                  'English',
                  style: const TextStyle(color: Colors.black),
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                ),
              ),
              PopupMenuItem(
                value: 'ar',
                child: Text(
                  'العربية',
                  style: const TextStyle(color: Colors.black),
                  textDirection:
                      isArabic ? TextDirection.rtl : TextDirection.ltr,
                ),
              ),
              const PopupMenuItem(
                value: 'zh',
                child: Text(
                  '中文',
                  style: TextStyle(color: Colors.black),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),

          // Settings menu
          if (showSettings)
            PopupMenuButton<String>(
              color: Colors.white,
              icon: const Icon(Icons.settings, color: Colors.black),
              onSelected: (value) async {
                try {
                  if (value == 'logout') {
                    final authService = AuthenticationService(context);
                    await authService.logout();
                  }
                } catch (e) {
                  print('Navigation error: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(localizations.navigationFailed(e.toString())),
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  PopupMenuItem(
                    value: 'logout',
                    child: Text(
                      localizations.logout,
                      style: const TextStyle(color: Colors.black),
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ),
                ];
              },
            ),

          // Additional actions
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}