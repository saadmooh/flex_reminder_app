import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showSearch;
  final Function(String)? onSearchChanged;
  final bool showSettings;
  final bool showLeading;

  const CustomAppBar({
    Key? key,
    this.title,
    this.showSearch = false,
    this.onSearchChanged,
    this.showSettings = true,
    this.showLeading = true,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageManager =
        Provider.of<LanguageManager>(context, listen: false);
    final isArabic = languageManager.locale.languageCode == 'ar';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        leading: showLeading
            ? IconButton(
                icon: Icon(
                  isArabic ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
                  color: Colors.black,
                ),
                onPressed: () {
                  print('Back button pressed');
                  Navigator.pop(context);
                },
              )
            : null,
        title: showSearch
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD3D3D3), width: 1),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: TextField(
                        textDirection:
                            isArabic ? TextDirection.rtl : TextDirection.ltr,
                        style: const TextStyle(
                            color: Color(0xff050505), fontSize: 16),
                        onChanged: onSearchChanged,
                        decoration: InputDecoration(
                          hintText: localizations.searchPosts,
                          hintStyle: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                              fontFamily: 'Inter'),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10.0),
                          suffixIcon: onSearchChanged != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Color(0xff707070), size: 20),
                                  onPressed: () {
                                    if (onSearchChanged != null) {
                                      onSearchChanged!('');
                                    }
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : (title != null
                ? Text(
                    title!,
                    style: const TextStyle(color: Colors.black, fontSize: 20),
                    textDirection:
                        isArabic ? TextDirection.rtl : TextDirection.ltr,
                  )
                : const Text('')),
        actions: [
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
                }
                final currentRoute = ModalRoute.of(context)?.settings.name;
                if (currentRoute != null) {
                  Navigator.pushReplacementNamed(context, currentRoute);
                } else {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              } catch (e) {
                print('Error updating language: $e');
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
            ],
          ),
          if (showSettings)
            PopupMenuButton<String>(
              color: Colors.white,
              icon: const Icon(Icons.settings, color: Colors.black),
              onSelected: (value) async {
                print('PopupMenuButton selected: $value');
                try {
                  if (value == 'logout') {
                    await ApiService().logout();
                    Navigator.pushReplacementNamed(context, '/');
                  } else if (value == 'time_slots') {
                    Navigator.pushNamed(context, '/time_slots');
                  } else if (value == 'subscription_management') {
                    Navigator.pushNamed(context, '/subscription_management');
                  } else if (value == 'stats') {
                    Navigator.pushNamed(context, '/stats');
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
                    value: 'time_slots',
                    child: Text(
                      localizations.timeSlots,
                      style: const TextStyle(color: Colors.black),
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'subscription_management',
                    child: Text(
                      localizations.subscriptionManagement,
                      style: const TextStyle(color: Colors.black),
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'stats',
                    child: Text(
                      localizations.stats,
                      style: const TextStyle(color: Colors.black),
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ),
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
        ],
      ),
    );
  }
}
