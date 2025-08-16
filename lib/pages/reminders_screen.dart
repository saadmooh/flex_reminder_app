import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flex_reminder/globals.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flex_reminder/models/reminder.dart';
import 'package:flex_reminder/services/notification_service.dart';
import 'package:flex_reminder/pages/save_post_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flex_reminder/pages/reminder_detail_screen.dart';
import 'package:flex_reminder/widgets/upper_app_bar.dart';
import 'package:flex_reminder/widgets/lower_navigation_bar.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';
import 'package:flex_reminder/utils/language_manager.dart';
import 'package:flex_reminder/providers/reminders_notifier.dart';

// ==============================================================================
// نافذة البحث المحسنة مع الخلفية الشفافة
// ==============================================================================

class _ReminderSearchDelegate extends SearchDelegate<String> {
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;
  final AppLocalizations appLocalizations;
  final bool isArabic;

  _ReminderSearchDelegate(
    this.initialQuery,
    this.onQueryChanged,
    this.appLocalizations,
    this.isArabic,
  ) {
    query = initialQuery;
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear, color: Colors.black),
        onPressed: () {
          query = '';
          onQueryChanged('');
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(
        isArabic ? Icons.chevron_right : Icons.chevron_left,
        color: Colors.black,
      ),
      onPressed: () => close(context, query),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // تحديث الاستعلام والانتقال للنتائج فوراً
    onQueryChanged(query);
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // تحديث الاستعلام في الوقت الفعلي
    if (query != initialQuery) {
      onQueryChanged(query);
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return Consumer<RemindersNotifier>(
      builder: (context, remindersNotifier, child) {
        final filteredReminders = ReminderFilterLogic.getFilteredReminders(
          reminders: [
            ...remindersNotifier.readReminders,
            ...remindersNotifier.unreadReminders
          ],
          searchQuery: query,
        );

        return Container(
          color: const Color.fromARGB(0, 255, 255, 255), // خلفية شفافة
          child: Column(
            children: [
              // عداد النتائج مع خلفية شفافة
              if (query.isNotEmpty) ...[
                Container(
                  color: Colors.black.withOpacity(0.8), // خلفية داكنة شبه شفافة
                  margin: const EdgeInsets.all(8.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.white.withOpacity(0.8)),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? 'نتائج البحث: ${filteredReminders.length}'
                            : 'Search Results: ${filteredReminders.length}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // النتائج
              Expanded(
                child: filteredReminders.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: filteredReminders.length,
                        itemBuilder: (context, index) {
                          final reminder = filteredReminders[index];
                          return _buildSearchResultCard(context, reminder);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8), // خلفية داكنة شبه شفافة
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              query.isEmpty ? Icons.search : Icons.search_off,
              size: 64,
              color: Colors.white.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              query.isEmpty
                  ? (isArabic
                      ? 'ابدأ بكتابة كلمات البحث'
                      : 'Start typing to search')
                  : (isArabic
                      ? 'لا توجد نتائج للبحث "$query"'
                      : 'No results found for "$query"'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                isArabic
                    ? 'جرب البحث بكلمات مختلفة أو تحقق من الإملاء'
                    : 'Try different keywords or check spelling',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(BuildContext context, Reminder reminder) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85), // خلفية داكنة شبه شفافة
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            close(context, reminder.title);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReminderDetailScreen(
                  reminderId: reminder.id,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // صورة التذكير أو أيقونة افتراضية
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: reminder.imageUrl != null &&
                            reminder.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: reminder.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.white.withOpacity(0.1),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white.withOpacity(0.8),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.white.withOpacity(0.1),
                              child: Icon(
                                Icons.image,
                                color: Colors.white.withOpacity(0.6),
                                size: 24,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.white.withOpacity(0.1),
                            child: Icon(
                              Icons.article_outlined,
                              color: Colors.white.withOpacity(0.6),
                              size: 24,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // معلومات التذكير
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // العنوان
                      Text(
                        reminder.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.95),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // التصنيفات
                      if (reminder.category != null ||
                          reminder.domain != null) ...[
                        Row(
                          children: [
                            if (reminder.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.blue.withOpacity(0.5)),
                                ),
                                child: Text(
                                  reminder.category!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade200,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (reminder.category != null &&
                                reminder.domain != null)
                              const SizedBox(width: 6),
                            if (reminder.domain != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.green.withOpacity(0.5)),
                                ),
                                child: Text(
                                  reminder.domain!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade200,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // حالة التذكير والوقت
                      Row(
                        children: [
                          // حالة القراءة
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: reminder.isOpened == 1
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: reminder.isOpened == 1
                                    ? Colors.green.withOpacity(0.5)
                                    : Colors.orange.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  reminder.isOpened == 1
                                      ? Icons.check_circle
                                      : Icons.schedule,
                                  size: 12,
                                  color: reminder.isOpened == 1
                                      ? Colors.green.shade200
                                      : Colors.orange.shade200,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  reminder.isOpened == 1
                                      ? (isArabic ? 'مقروء' : 'Read')
                                      : (isArabic ? 'غير مقروء' : 'Unread'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: reminder.isOpened == 1
                                        ? Colors.green.shade200
                                        : Colors.orange.shade200,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Spacer(),

                          // وقت التذكير القادم إذا كان متوفراً
                          if (reminder.nextReminderTime != null &&
                              reminder.nextReminderTime!.isNotEmpty)
                            Text(
                              reminder.nextReminderTime!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // سهم للانتقال
                Icon(
                  isArabic ? Icons.chevron_left : Icons.chevron_right,
                  color: Colors.white.withOpacity(0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  String get searchFieldLabel =>
      appLocalizations.searchReminders ??
      (isArabic ? 'البحث في التذكيرات...' : 'Search reminders...');

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      primaryColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black.withOpacity(0.9), // خلفية داكنة شبه شفافة
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        border: InputBorder.none,
        filled: false,
      ),
      textTheme: Theme.of(context).textTheme.copyWith(
            titleLarge: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
    );
  }
}

// ==============================================================================
// منطق تصفية التذكيرات
// ==============================================================================

class ReminderFilterLogic {
  static List<Reminder> getFilteredReminders({
    required List<Reminder> reminders,
    required String searchQuery,
    String? selectedCategory,
    String? selectedComplexity,
    String? selectedDomain,
  }) {
    List<Reminder> filtered = List.from(reminders);

    filtered.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where((reminder) => _matchesSearchQuery(reminder, searchQuery))
          .toList();
    }

    if (selectedCategory != null &&
        selectedCategory != 'All' &&
        selectedCategory != 'الكل') {
      filtered = filtered
          .where((reminder) => reminder.category == selectedCategory)
          .toList();
    }

    if (selectedComplexity != null &&
        selectedComplexity != 'All' &&
        selectedComplexity != 'الكل') {
      filtered = filtered
          .where((reminder) => reminder.complexity == selectedComplexity)
          .toList();
    }

    if (selectedDomain != null &&
        selectedDomain != 'All' &&
        selectedDomain != 'الكل') {
      filtered = filtered
          .where((reminder) => reminder.domain == selectedDomain)
          .toList();
    }

    return filtered;
  }

  static bool _matchesSearchQuery(Reminder reminder, String searchQuery) {
    final query = searchQuery.toLowerCase().trim();

    if (query.isEmpty) return true;

    if (reminder.title.toLowerCase().contains(query)) {
      return true;
    }

    if (reminder.id.toString().contains(query)) {
      return true;
    }

    if (reminder.content != null &&
        reminder.content!.toLowerCase().contains(query)) {
      return true;
    }

    if (reminder.category != null &&
        reminder.category!.toLowerCase().contains(query)) {
      return true;
    }

    return false;
  }
}
// ==============================================================================
// 2. منطق البحث المُصحح
// ==============================================================================

mixin SearchLogicMixin<T extends StatefulWidget> on State<T> {
  String _searchQuery = '';

  String get searchQuery => _searchQuery;

  void showSearchInterface(BuildContext context) {
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    showSearch(
      context: context,
      delegate: _ReminderSearchDelegate(
        _searchQuery,
        (newQuery) {
          updateSearchQuery(newQuery);
        },
        AppLocalizations.of(context)!,
        isArabic,
      ),
    );
  }

  void updateSearchQuery(String newQuery) {
    if (_searchQuery != newQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      onSearchQueryChanged(newQuery);
    }
  }

  void onSearchQueryChanged(String query) {
    // يمكن للشاشات تنفيذ هذه الدالة لتحديث البيانات
  }

  void clearSearch() {
    updateSearchQuery('');
  }

  bool get hasActiveSearch => _searchQuery.isNotEmpty;
}

class RemindersScreen extends StatefulWidget {
  final int initialIndex;

  const RemindersScreen({super.key, this.initialIndex = 0});

  @override
  _RemindersScreenState createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  StreamSubscription? _intentSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _sharedText;
  String? _selectedCategory;
  String? _selectedComplexity;
  String? _selectedDomain;
  late TabController _tabController;
  late int _currentNavIndex;
  bool _isOnline = true;
  bool _hasTriedOnlineLoad = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentNavIndex = widget.initialIndex;
    _listenForShareData();
    _initializeConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeReminders();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _intentSub?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _initializeConnectivity() async {
    final List<ConnectivityResult> connectivityResult =
        await Connectivity().checkConnectivity();
    _updateConnectionStatus(connectivityResult);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey?.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey!.currentContext!);

      // التحقق من أن ScaffoldMessenger متاح
      if (scaffoldMessenger.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        print('ScaffoldMessenger غير متاح، تم تجاهل SnackBar: $message');
      }
    } else {
      print('التطبيق غير نشط، تم تجاهل SnackBar: $message');
    }
  }

  // دالة للتحقق من حالة التطبيق قبل عرض الرسائل
  void _safeShowMessage(String message, {Color? color}) {
    if (kDebugMode) {
      print('FCM Message: $message');
    }

    // محاولة عرض SnackBar مع معالجة الأخطاء
    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> connectivityResults) {
    final bool wasOnline = _isOnline;
    setState() {
      _isOnline = connectivityResults
          .any((result) => result != ConnectivityResult.none);
    }

    ;

    if (!wasOnline && _isOnline && mounted) {
      print('🌐 الاتصال عاد، تحديث البيانات...');
      _refreshRemindersIfOnline();
    } else if (!_isOnline) {
      print('📴 لا يوجد اتصال بالإنترنت، استخدام البيانات المحلية');
      _showOfflineSnackBar();
    }
  }

  void _showOfflineSnackBar() {
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isArabic
              ? 'لا يوجد اتصال بالإنترنت - عرض البيانات المحلية'
              : 'No internet connection - showing offline data',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _initializeReminders() async {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    _safeShowMessage('🔄 بدء تهيئة التذكيرات في RemindersScreen');

    try {
      if (remindersNotifier.isInitialized) {
        _safeShowMessage('✅ RemindersNotifier مهيء مسبقاً، تجاهل التهيئة');
        return;
      }

      if (_isOnline && !_hasTriedOnlineLoad) {
        _safeShowMessage('🌐 محاولة تحميل البيانات من الإنترنت...');
        _hasTriedOnlineLoad = true;

        try {
          await remindersNotifier.initializeImproved(forceRefresh: false);
          _safeShowMessage('✅ تم تحميل البيانات من الإنترنت بنجاح');
        } catch (e) {
          print('❌ فشل تحميل البيانات من الإنترنت: $e');
          await _loadOfflineDataFallback(remindersNotifier);
        }
      } else {
        print('💾 تحميل البيانات المحلية فقط...');
        await _loadOfflineDataFallback(remindersNotifier);
      }
    } catch (e) {
      print('❌ خطأ في تهيئة التذكيرات: $e');
      _showErrorSnackBar('خطأ في تحميل التذكيرات: $e');
    }
  }

  Future<void> _refreshRemindersIfOnline() async {
    if (!_isOnline) return;

    print('🔄 تحديث البيانات بعد عودة الاتصال...');
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);

    try {
      await remindersNotifier.initializeImproved(forceRefresh: true);

      final isArabic = Provider.of<LanguageManager>(context, listen: false)
              .locale
              .languageCode ==
          'ar';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic ? 'تم تحديث البيانات بنجاح' : 'Data updated successfully',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ فشل في تحديث البيانات: $e');
      _showErrorSnackBar('فشل في تحديث البيانات');
    }
  }

  Future<void> _loadOfflineDataFallback(
      RemindersNotifier remindersNotifier) async {
    try {
      print('💾 تحميل البيانات المحلية كخطة احتياطية...');
      await remindersNotifier.loadCachedDataImproved();
      print('✅ تم تحميل البيانات المحلية بنجاح');
    } catch (e) {
      print('❌ فشل في تحميل البيانات المحلية: $e');
      _showErrorSnackBar('فشل في تحميل البيانات المحلية');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isArabic ? message : 'Error loading data',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: isArabic ? 'إعادة المحاولة' : 'Retry',
          textColor: Colors.white,
          onPressed: () => _initializeReminders(),
        ),
      ),
    );
  }

  List<Reminder> _getFilteredReminders(bool showOpened) {
    final remindersNotifier = Provider.of<RemindersNotifier>(context);
    final reminders = showOpened
        ? remindersNotifier.readReminders
        : remindersNotifier.unreadReminders;
    List<Reminder> filtered = List.from(reminders);
    filtered.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((r) =>
              r.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (r.id.toString().contains(_searchQuery) ?? false))
          .toList();
    }

    if (_selectedCategory != null &&
        _selectedCategory != 'All' &&
        _selectedCategory != 'الكل') {
      filtered =
          filtered.where((r) => r.category == _selectedCategory).toList();
    }

    if (_selectedComplexity != null &&
        _selectedComplexity != 'All' &&
        _selectedComplexity != 'الكل') {
      filtered =
          filtered.where((r) => r.complexity == _selectedComplexity).toList();
    }

    if (_selectedDomain != null &&
        _selectedDomain != 'All' &&
        _selectedDomain != 'الكل') {
      filtered = filtered.where((r) => r.domain == _selectedDomain).toList();
    }

    return filtered;
  }

  void _listenForShareData() {
    print('الاستماع إلى البيانات المشاركة...');
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty && mounted) {
          print('تم استقبال بيانات مشتركة: ${value.first.path}');
          setState(() {
            _sharedText = value.first.path;
            _showSavePostModal(_sharedText);
          });
        }
      },
      onError: (err) => print("خطأ getMediaStream: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty && mounted) {
        print('تم استقبال بيانات مشتركة أولية: ${value.first.path}');
        setState(() {
          _sharedText = value.first.path;
          _showSavePostModal(_sharedText);
          ReceiveSharingIntent.instance.reset();
        });
      }
    });
  }

  Future<void> _showSavePostModal(String? sharedUrl) async {
    if (!_isOnline && sharedUrl != null) {
      final isArabic = Provider.of<LanguageManager>(context, listen: false)
              .locale
              .languageCode ==
          'ar';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'يتطلب إضافة منشور جديد اتصال بالإنترنت'
                : 'Adding new posts requires internet connection',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    print('عرض نافذة حفظ منشور مع رابط: $sharedUrl');
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SavePostScreen(
          initialUrl: sharedUrl,
          onSave: () {
            print('saved post, triggering reminders refresh');
            if (_isOnline) {
              Provider.of<RemindersNotifier>(context, listen: false)
                  .forceRefreshReminders();
            }
          },
        ),
      ),
    );

    if (result == true && _isOnline) {
      await Provider.of<RemindersNotifier>(context, listen: false)
          .forceRefreshReminders();
    }
  }

  void _loadMoreReminders(bool showOpened) {
    if (!_isOnline) {
      print('لا يوجد اتصال بالإنترنت لتحميل المزيد من التذكيرات');
      return;
    }

    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    if (!remindersNotifier.isLoadingMore &&
        (remindersNotifier.readReminders.length +
                remindersNotifier.unreadReminders.length) <
            remindersNotifier.totalReminders) {
      print(
          'تحميل المزيد من التذكيرات للصفحة ${remindersNotifier.currentPage}');
      remindersNotifier.fetchReminders(
        searchQuery: _searchQuery,
        category: _selectedCategory,
        complexity: _selectedComplexity,
        domain: _selectedDomain,
        isLoadMore: true,
        forceFetch: true,
      );
    } else {
      print('لا توجد تذكيرات أخرى للتحميل أو التحميل قيد التنفيذ');
    }
  }

  void _showSearch() {
    print('عرض شريط البحث');
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    showSearch(
      context: context,
      delegate: _ReminderSearchDelegate(
        _searchQuery,
        (newQuery) {
          setState(() {
            _searchQuery = newQuery;
            print('تم تحديث استعلام البحث إلى: $_searchQuery');
          });
        },
        AppLocalizations.of(context)!,
        isArabic, // إضافة هذا المعامل المفقود
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    return Consumer2<LanguageManager, RemindersNotifier>(
      builder: (context, languageManager, remindersNotifier, child) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: Column(
                children: [
                  if (!_isOnline)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.orange,
                      child: Text(
                        isArabic
                            ? 'وضع عدم الاتصال - عرض البيانات المحلية'
                            : 'Offline Mode - Showing Local Data',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  UpperAppBar(
                    showSearch: true,
                    onSearchPressed: _showSearch,
                    showLeading: false,
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.white,
            body: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: localizations?.unreadReminders ?? 'Unread'),
                    Tab(text: localizations?.readReminders ?? 'Read'),
                  ],
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: Colors.black,
                  labelStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRemindersList(false),
                      _buildRemindersList(true),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                _showSavePostModal(null);
              },
              backgroundColor: _isOnline ? Colors.black : Colors.grey,
              shape: const CircleBorder(),
              child: Icon(
                Icons.add,
                color: Colors.white,
              ),
            ),
            bottomNavigationBar: LowerNavigationBar(
              currentIndex: _currentNavIndex,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemindersList(bool showOpened) {
    final remindersNotifier = Provider.of<RemindersNotifier>(context);
    final filteredReminders = _getFilteredReminders(showOpened);
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';
    final listName = showOpened
        ? (isArabic ? 'المقروءة' : 'Read')
        : (isArabic ? 'غير المقروءة' : 'Unread');

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200 &&
            !remindersNotifier.isLoadingMore &&
            _isOnline) {
          _loadMoreReminders(showOpened);
        }
        return false;
      },
      child: Column(
        children: [
          _buildFilterBar(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isArabic
                      ? 'عدد التذكيرات $listName: ${filteredReminders.length}'
                      : 'Number of $listName Reminders: ${filteredReminders.length}',
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isOnline ? Icons.cloud_done : Icons.cloud_off,
                  size: 16,
                  color: _isOnline ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),
          Expanded(
            child: remindersNotifier.isLoading && filteredReminders.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  )
                : filteredReminders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isOnline ? Icons.inbox : Icons.cloud_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              showOpened
                                  ? AppLocalizations.of(context)
                                          ?.noReadReminders ??
                                      'No read reminders'
                                  : AppLocalizations.of(context)
                                          ?.noUnreadReminders ??
                                      'No unread reminders',
                              style: const TextStyle(color: Colors.black),
                            ),
                            if (!_isOnline) ...[
                              const SizedBox(height: 8),
                              Text(
                                isArabic
                                    ? 'تحقق من اتصال الإنترنت للمزيد من البيانات'
                                    : 'Check internet connection for more data',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _refreshRemindersIfOnline(),
                        color: Colors.black,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8.0),
                          itemCount: filteredReminders.length +
                              (filteredReminders.length <
                                          remindersNotifier.totalReminders &&
                                      _isOnline
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == filteredReminders.length &&
                                filteredReminders.length <
                                    remindersNotifier.totalReminders &&
                                _isOnline) {
                              return remindersNotifier.isLoadingMore
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.black),
                                    )
                                  : const SizedBox.shrink();
                            }
                            return _buildReminderCard(filteredReminders[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final remindersNotifier = Provider.of<RemindersNotifier>(context);
    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';
    final allLabel = isArabic ? 'الكل' : 'All';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedCategory != null && _selectedCategory != allLabel)
                  Chip(
                    label: Text(_selectedCategory!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _selectedCategory = null;
                        print('تم إزالة تصفية الفئة');
                      });
                    },
                  ),
                if (_selectedComplexity != null &&
                    _selectedComplexity != allLabel)
                  Chip(
                    label: Text(_selectedComplexity!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _selectedComplexity = null;
                        print('تم إزالة تصفية التعقيد');
                      });
                    },
                  ),
                if (_selectedDomain != null && _selectedDomain != allLabel)
                  Chip(
                    label: Text(_selectedDomain!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _selectedDomain = null;
                        print('تم إزالة تصفية المجال');
                      });
                    },
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onPressed: () {
              print('تم الضغط على زر التصفية');
              _showFilterDialog();
            },
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    print('عرض نافذة التصفية');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.filters ?? 'Filters',
            style: const TextStyle(color: Colors.black)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterSection(
                title: AppLocalizations.of(context)?.categories ?? 'Categories',
                items: remindersNotifier.categories,
                selectedItem: _selectedCategory,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _selectedCategory =
                        (selected && item != allLabel) ? item : null;
                    print('تم تعيين تصفية الفئة إلى: $_selectedCategory');
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              _buildFilterSection(
                title: AppLocalizations.of(context)?.complexity ?? 'Complexity',
                items: remindersNotifier.complexities,
                selectedItem: _selectedComplexity,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _selectedComplexity =
                        (selected && item != allLabel) ? item : null;
                    print('تم تعيين تصفية التعقيد إلى: $_selectedComplexity');
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              _buildFilterSection(
                title: AppLocalizations.of(context)?.domains ?? 'Domains',
                items: remindersNotifier.domains,
                selectedItem: _selectedDomain,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _selectedDomain =
                        (selected && item != allLabel) ? item : null;
                    print('تم تعيين تصفية المجال إلى: $_selectedDomain');
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCategory = null;
                _selectedComplexity = null;
                _selectedDomain = null;
                print('تم إزالة جميع التصفيات');
              });
              Navigator.pop(context);
            },
            child: Text(
                AppLocalizations.of(context)?.clearFilters ?? 'Clear Filters',
                style: const TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () {
              print('إغلاق نافذة التصفية');
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)?.close ?? 'Close',
                style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection({
    required String title,
    required List<String> items,
    required String? selectedItem,
    required Function(bool, String) onSelected,
  }) {
    print('بناء قسم التصفية: $title');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = selectedItem == item;
              return FilterChip(
                key: ValueKey(item),
                label: Text(
                  item,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) => onSelected(selected, item),
                backgroundColor: Colors.white,
                selectedColor: Colors.black,
                side: const BorderSide(color: Colors.black),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReminderCard(Reminder reminder) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReminderDetailScreen(
                reminderId: reminder.id,
              ),
            ),
          ) as Map<String, dynamic>?;
          if (result != null && result['id'] != null && result['id'] != 0) {
            print('تم إرجاع نتيجة من ReminderDetailScreen: $result');
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reminder.imageUrl != null && reminder.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: reminder.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.white,
                      child: const Center(
                          child:
                              CircularProgressIndicator(color: Colors.black)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.white,
                      child: const Icon(Icons.error, color: Colors.black),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          reminder.title ?? '',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                      const Icon(Icons.notifications_none, color: Colors.black),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (reminder.nextReminderTime != null &&
                      reminder.nextReminderTime!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(
                          reminder.nextReminderTime!,
                          style: const TextStyle(
                              color: Colors.black, fontSize: 12),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  _buildTags(reminder),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTags(Reminder reminder) {
    final List<Widget> tags = [];
    if (reminder.domain != null && reminder.domain!.isNotEmpty) {
      tags.add(_buildTag(reminder.domain!, Colors.white, Colors.black));
    }
    if (reminder.complexity != null && reminder.complexity!.isNotEmpty) {
      tags.add(_buildTag(reminder.complexity!, Colors.white, Colors.black));
    }
    if (reminder.category != null && reminder.category!.isNotEmpty) {
      tags.add(_buildTag(reminder.category!, Colors.white, Colors.black));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: tags);
  }

  Widget _buildTag(String text, Color backgroundColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: Colors.black),
          borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 12)),
    );
  }
}
