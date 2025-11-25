import 'dart:async';
import 'dart:convert';
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
import 'package:shared_preferences/shared_preferences.dart';

// ==============================================================================
// 1. تحسين إدارة الحالة باستخدام State Machine
// ==============================================================================

enum DataState {
  initial,
  loadingOnline,
  loadingOffline,
  online,
  offline,
  error
}

class RemindersState {
  final DataState state;
  final List<Reminder> reminders;
  final String? error;
  final bool hasMore;

  RemindersState({
    required this.state,
    required this.reminders,
    this.error,
    this.hasMore = false,
  });

  RemindersState copyWith({
    DataState? state,
    List<Reminder>? reminders,
    String? error,
    bool? hasMore,
  }) {
    return RemindersState(
      state: state ?? this.state,
      reminders: reminders ?? this.reminders,
      error: error ?? this.error,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// ==============================================================================
// 2. تحسين إدارة حالة الفلاتر
// ==============================================================================

class FilterState {
  final String? category;
  final String? complexity;
  final String? domain;

  const FilterState({
    this.category,
    this.complexity,
    this.domain,
  });

  FilterState copyWith({
    String? category,
    String? complexity,
    String? domain,
  }) {
    return FilterState(
      category: category ?? this.category,
      complexity: complexity ?? this.complexity,
      domain: domain ?? this.domain,
    );
  }

  bool get hasActiveFilters =>
      category != null || complexity != null || domain != null;

  FilterState clear() => const FilterState();

  Map<String, dynamic> toJson() => {
        'category': category,
        'complexity': complexity,
        'domain': domain,
      };

  factory FilterState.fromJson(Map<String, dynamic> json) => FilterState(
        category: json['category'],
        complexity: json['complexity'],
        domain: json['domain'],
      );
}

// ==============================================================================
// 3. تحسين منطق البحث مع memoization
// ==============================================================================

class SearchLogic {
  static List<Reminder>? _cachedFilteredReminders;
  static String? _lastSearchQuery;
  static String? _lastCategory;
  static String? _lastComplexity;
  static String? _lastDomain;
  static bool? _lastShowOpened;

  static List<Reminder> getFilteredReminders({
    required List<Reminder> reminders,
    required String searchQuery,
    String? category,
    String? complexity,
    String? domain,
    required bool showOpened,
  }) {
    // إرجاع النتيجة المخزنة إذا لم تتغير المعاملات
    if (_cachedFilteredReminders != null &&
        _lastSearchQuery == searchQuery &&
        _lastCategory == category &&
        _lastComplexity == complexity &&
        _lastDomain == domain &&
        _lastShowOpened == showOpened) {
      return _cachedFilteredReminders!;
    }

    List<Reminder> filtered = List.from(reminders);
    filtered.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where((reminder) => _matchesSearchQuery(reminder, searchQuery))
          .toList();
    }

    if (category != null && category != 'All' && category != 'الكل') {
      filtered =
          filtered.where((reminder) => reminder.category == category).toList();
    }

    if (complexity != null && complexity != 'All' && complexity != 'الكل') {
      filtered = filtered
          .where((reminder) => reminder.complexity == complexity)
          .toList();
    }

    if (domain != null && domain != 'All' && domain != 'الكل') {
      filtered =
          filtered.where((reminder) => reminder.domain == domain).toList();
    }

    // حفظ النتيجة
    _cachedFilteredReminders = filtered;
    _lastSearchQuery = searchQuery;
    _lastCategory = category;
    _lastComplexity = complexity;
    _lastDomain = domain;
    _lastShowOpened = showOpened;

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

  static void clearCache() {
    _cachedFilteredReminders = null;
    _lastSearchQuery = null;
    _lastCategory = null;
    _lastComplexity = null;
    _lastDomain = null;
    _lastShowOpened = null;
  }
}

// ==============================================================================
// 4. نافذة البحث المحسنة مع debouncing
// ==============================================================================

class _ReminderSearchDelegate extends SearchDelegate<String> {
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;
  final AppLocalizations appLocalizations;
  final bool isArabic;
  Timer? _debounceTimer;

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
    onQueryChanged(query);
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // استخدام debouncing
    _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (query != initialQuery) {
        onQueryChanged(query);
      }
    });

    return _buildSearchResults(context);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Widget _buildSearchResults(BuildContext context) {
    return Consumer<RemindersNotifier>(
      builder: (context, remindersNotifier, child) {
        final filteredReminders = SearchLogic.getFilteredReminders(
          reminders: [
            ...remindersNotifier.readReminders,
            ...remindersNotifier.unreadReminders
          ],
          searchQuery: query,
          showOpened: true, // في البحث نعرض كل النتائج
        );

        return Container(
          color: Colors.white,
          child: Column(
            children: [
              if (query.isNotEmpty) ...[
                Container(
                  color: Colors.white,
                  margin: const EdgeInsets.all(8.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? 'نتائج البحث: ${filteredReminders.length}'
                            : 'Search Results: ${filteredReminders.length}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              query.isEmpty ? Icons.search : Icons.search_off,
              size: 64,
              color: Colors.black.withOpacity(0.7),
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
              style: const TextStyle(
                color: Colors.black,
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
                  color: Colors.black.withOpacity(0.6),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // صورة التذكير مع إعدادات cache محسنة
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey.withOpacity(0.1),
                        border:
                            Border.all(color: Colors.black.withOpacity(0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: reminder.imageUrl != null &&
                                reminder.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: reminder.imageUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 120,
                                memCacheHeight: 120,
                                cacheKey: 'search_${reminder.id}',
                                placeholder: (context, url) => Container(
                                  color: Colors.grey.withOpacity(0.1),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey.withOpacity(0.1),
                                  child: Icon(
                                    Icons.image,
                                    color: Colors.black.withOpacity(0.6),
                                    size: 24,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey.withOpacity(0.1),
                                child: Icon(
                                  Icons.article_outlined,
                                  color: Colors.black.withOpacity(0.6),
                                  size: 24,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reminder.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 8),
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
                                        color: Colors.blue.shade700,
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
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
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
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      reminder.isOpened == 1
                                          ? (isArabic ? 'مقروء' : 'Read')
                                          : (isArabic ? 'غير مقروء' : 'Unread'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: reminder.isOpened == 1
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (reminder.nextReminderTime != null &&
                                  reminder.nextReminderTime!.isNotEmpty)
                                Text(
                                  reminder.nextReminderTime!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    Icon(
                      isArabic ? Icons.chevron_left : Icons.chevron_right,
                      color: Colors.black.withOpacity(0.5),
                      size: 20,
                    ),
                  ],
                ),
                if (reminder.siteLogo != null && reminder.siteLogo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: reminder.siteLogo!,
                            fit: BoxFit.contain,
                            memCacheWidth: 40,
                            memCacheHeight: 40,
                            cacheKey: 'logo_${reminder.id}',
                            placeholder: (context, url) => Container(
                              color: Colors.grey.withOpacity(0.1),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.withOpacity(0.1),
                              child: const Icon(Icons.error, size: 14),
                            ),
                          ),
                        ),
                        if (reminder.siteName != null &&
                            reminder.siteName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              reminder.siteName!,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
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
      primaryColor: Colors.white,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        elevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.black.withOpacity(0.7)),
        border: InputBorder.none,
        filled: false,
      ),
      textTheme: Theme.of(context).textTheme.copyWith(
            titleLarge: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
    );
  }
}

// ==============================================================================
// 5. الشاشة الرئيسية مع جميع التحسينات
// ==============================================================================

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
  FilterState _filterState = const FilterState();
  late TabController _tabController;
  late int _currentNavIndex;
  bool _isOnline = true;
  bool _hasTriedOnlineLoad = false;
  bool _isInitializing = false;
  bool _isLoadingMoreTriggered = false;
  RemindersState _remindersState = RemindersState(
    state: DataState.initial,
    reminders: [],
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentNavIndex = widget.initialIndex;
    _listenForShareData();
    _initializeConnectivity();
    _loadFilters();
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

  // تحسين إدارة الاتصال
  void _initializeConnectivity() async {
    await _connectivitySubscription?.cancel();

    final List<ConnectivityResult> connectivityResult =
        await Connectivity().checkConnectivity();
    _updateConnectionStatus(connectivityResult);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
      onError: (error) {
        print('خطأ في connectivity: $error');
      },
      cancelOnError: false,
    );
  }

  // تحسين عرض الرسائل
  void _showSnackBar(String message, Color backgroundColor) {
    if (navigatorKey.currentContext != null) {
      final scaffoldMessenger =
          ScaffoldMessenger.of(navigatorKey.currentContext!);

      if (scaffoldMessenger.mounted) {
        scaffoldMessenger.clearSnackBars();

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  void _safeShowMessage(String message, {Color? color}) {
    try {
      _showSnackBar(message, color ?? Colors.blue);
    } catch (e) {
      print('خطأ في عرض الرسالة: $e');
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> connectivityResults) {
    final bool wasOnline = _isOnline;
    setState(() {
      _isOnline = connectivityResults
          .any((result) => result != ConnectivityResult.none);
    });

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

    _showSnackBar(
      isArabic
          ? 'لا يوجد اتصال بالإنترنت - عرض البيانات المحلية'
          : 'No internet connection - showing offline data',
      Colors.orange,
    );
  }

  // تحسين التهيئة مع استراتيجيات متعددة
  Future<void> _initializeReminders() async {
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);

    if (_isInitializing || remindersNotifier.isInitialized) {
      return;
    }

    _isInitializing = true;

    try {
      setState(() {
        _remindersState =
            _remindersState.copyWith(state: DataState.loadingOnline);
      });

      if (_isOnline && !_hasTriedOnlineLoad) {
        _hasTriedOnlineLoad = true;
        await remindersNotifier.initializeImproved();

        setState(() {
          _remindersState = _remindersState.copyWith(
            state: DataState.online,
            reminders: [
              ...remindersNotifier.readReminders,
              ...remindersNotifier.unreadReminders
            ],
          );
        });
      } else {
        await _loadOfflineDataFallback(remindersNotifier);
      }
    } catch (e) {
      print('❌ خطأ في تهيئة التذكيرات: $e');
      await _loadOfflineDataFallback(remindersNotifier);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadOfflineDataFallback(
      RemindersNotifier remindersNotifier) async {
    try {
      setState(() {
        _remindersState =
            _remindersState.copyWith(state: DataState.loadingOffline);
      });

      await remindersNotifier.loadCachedDataImproved();

      setState(() {
        _remindersState = _remindersState.copyWith(
          state: DataState.offline,
          reminders: [
            ...remindersNotifier.readReminders,
            ...remindersNotifier.unreadReminders
          ],
        );
      });
    } catch (e) {
      print('❌ فشل في تحميل البيانات المحلية: $e');
      setState(() {
        _remindersState = _remindersState.copyWith(
          state: DataState.error,
          error: e.toString(),
        );
      });

      _showErrorWithRetry(
        'فشل تحميل البيئة',
        onRetry: () => _initializeReminders(),
      );
    }
  }

  void _showErrorWithRetry(String message, {VoidCallback? onRetry}) {
    if (!mounted) return;

    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: isArabic ? 'إعادة المحاولة' : 'Retry',
          textColor: Colors.white,
          onPressed: onRetry ?? () {},
        ),
      ),
    );
  }

  Future<void> _refreshRemindersIfOnline() async {
    if (!_isOnline) return;

    print('🔄 تحديث البيانات بعد عودة الاتصال...');
    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);

    try {
      await remindersNotifier.initializeImproved();

      setState(() {
        _remindersState = _remindersState.copyWith(
          state: DataState.online,
          reminders: [
            ...remindersNotifier.readReminders,
            ...remindersNotifier.unreadReminders
          ],
        );
      });

      final isArabic = Provider.of<LanguageManager>(context, listen: false)
              .locale
              .languageCode ==
          'ar';

      _safeShowMessage(
        isArabic ? 'تم تحديث البيانات بنجاح' : 'Data updated successfully',
        color: Colors.green,
      );
    } catch (e) {
      print('❌ فشل في تحديث البيانات: $e');
      _showErrorSnackBar('فشل في تحديث البيانات');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    final isArabic = Provider.of<LanguageManager>(context, listen: false)
            .locale
            .languageCode ==
        'ar';

    _showSnackBar(
      isArabic ? message : 'Error loading data',
      Colors.red,
    );
  }

  // تحسين الحصول على التذكيرات المفلترة باستخدام memoization
  List<Reminder> _getFilteredReminders(bool showOpened) {
    final remindersNotifier = Provider.of<RemindersNotifier>(context);
    final reminders = showOpened
        ? remindersNotifier.readReminders
        : remindersNotifier.unreadReminders;

    return SearchLogic.getFilteredReminders(
      reminders: reminders,
      searchQuery: _searchQuery,
      category: _filterState.category,
      complexity: _filterState.complexity,
      domain: _filterState.domain,
      showOpened: showOpened,
    );
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

      _showSnackBar(
        isArabic
            ? 'يتطلب إضافة منشور جديد اتصال بالإنترنت'
            : 'Adding new posts requires internet connection',
        Colors.red,
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
              // مسح الـ cache بعد إضافة تذكير جديد
              SearchLogic.clearCache();
            }
          },
        ),
      ),
    );

    if (result == true && _isOnline) {
      await Provider.of<RemindersNotifier>(context, listen: false)
          .forceRefreshReminders();
      // مسح الـ cache بعد إضافة تذكير جديد
      SearchLogic.clearCache();
    }
  }

  // تحسين تحميل المزيد من التذكيرات مع منع التكرار
  Future<void> _loadMoreReminders(bool showOpened) async {
    if (!_isOnline) {
      print('لا يوجد اتصال بالإنترنت لتحميل المزيد من التذكيرات');
      return;
    }

    final remindersNotifier =
        Provider.of<RemindersNotifier>(context, listen: false);
    if (!remindersNotifier.isLoadingMore &&
        (remindersNotifier.readReminders.length +
                remindersNotifier.unreadReminders.length) <
            remindersNotifier.totalReminders &&
        !_isLoadingMoreTriggered) {
      _isLoadingMoreTriggered = true;

      print(
          'تحميل المزيد من التذكيرات للصفحة ${remindersNotifier.currentPage}');

      try {
        await remindersNotifier.fetchReminders(
          searchQuery: _searchQuery,
          category: _filterState.category,
          complexity: _filterState.complexity,
          domain: _filterState.domain,
          isLoadMore: true,
          forceFetch: true,
        );
      } catch (e) {
        print('❌ خطأ في تحميل المزيد: $e');
      } finally {
        // إعادة التعيين بعد انتهاء التحميل، سواء نجح أو فشل
        _isLoadingMoreTriggered = false;
      }
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
        isArabic,
      ),
    );
  }

  // حفظ الفلاتر
  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('filters', jsonEncode(_filterState.toJson()));
  }

  // استرجاع الفلاتر
  Future<void> _loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final filtersJson = prefs.getString('filters');
    if (filtersJson != null) {
      setState(() {
        _filterState = FilterState.fromJson(jsonDecode(filtersJson));
      });
    }
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
              onPressed: _isOnline
                  ? () {
                      _showSavePostModal(null);
                    }
                  : null,
              backgroundColor: _isOnline ? Colors.black : Colors.grey,
              shape: const CircleBorder(),
              child: const Icon(
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
        if (scrollInfo is ScrollUpdateNotification) {
          final threshold = scrollInfo.metrics.maxScrollExtent - 200;

          if (scrollInfo.metrics.pixels >= threshold &&
              !remindersNotifier.isLoadingMore &&
              _isOnline &&
              !_isLoadingMoreTriggered) {
            // تم إصلاح الخطأ هنا: استدعاء الدالة غير المتزامنة بشكل صحيح
            _loadMoreReminders(showOpened);
          }
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
                        onRefresh: () async {
                          print(
                              '🔄 تم السحب للأعلى - إعادة جلب التذكيرات من التخزين');
                          final remindersNotifier =
                              Provider.of<RemindersNotifier>(context,
                                  listen: false);

                          try {
                            if (_isOnline) {
                              await remindersNotifier.initializeImproved();
                              print('✅ تم تحديث البيانات من الخادم');
                            } else {
                              await remindersNotifier.loadCachedDataImproved();
                              print('✅ تم تحديث البيانات من التخزين المحلي');
                            }

                            final isArabic = Provider.of<LanguageManager>(
                                        context,
                                        listen: false)
                                    .locale
                                    .languageCode ==
                                'ar';

                            _safeShowMessage(
                              isArabic
                                  ? 'تم تحديث التذكيرات بنجاح'
                                  : 'Reminders updated successfully',
                              color: Colors.green,
                            );

                            // مسح الـ cache بعد التحديث
                            SearchLogic.clearCache();
                          } catch (e) {
                            print('❌ خطأ في تحديث التذكيرات: $e');
                            final isArabic = Provider.of<LanguageManager>(
                                        context,
                                        listen: false)
                                    .locale
                                    .languageCode ==
                                'ar';

                            _safeShowMessage(
                              isArabic
                                  ? 'فشل في تحديث التذكيرات'
                                  : 'Failed to update reminders',
                              color: Colors.red,
                            );
                          }
                        },
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
                if (_filterState.category != null &&
                    _filterState.category != allLabel)
                  Chip(
                    label: Text(_filterState.category!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _filterState = _filterState.copyWith(category: null);
                        print('تم إزالة تصفية الفئة');
                        _saveFilters();
                        // مسح الـ cache عند تغيير الفلاتر
                        SearchLogic.clearCache();
                      });
                    },
                  ),
                if (_filterState.complexity != null &&
                    _filterState.complexity != allLabel)
                  Chip(
                    label: Text(_filterState.complexity!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _filterState = _filterState.copyWith(complexity: null);
                        print('تم إزالة تصفية التعقيد');
                        _saveFilters();
                        // مسح الـ cache عند تغيير الفلاتر
                        SearchLogic.clearCache();
                      });
                    },
                  ),
                if (_filterState.domain != null &&
                    _filterState.domain != allLabel)
                  Chip(
                    label: Text(_filterState.domain!,
                        style: const TextStyle(color: Colors.black)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black),
                    onDeleted: () {
                      setState(() {
                        _filterState = _filterState.copyWith(domain: null);
                        print('تم إزالة تصفية المجال');
                        _saveFilters();
                        // مسح الـ cache عند تغيير الفلاتر
                        SearchLogic.clearCache();
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
                selectedItem: _filterState.category,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _filterState = _filterState.copyWith(
                      category: (selected && item != allLabel) ? item : null,
                    );
                    print('تم تعيين تصفية الفئة إلى: ${_filterState.category}');
                    _saveFilters();
                    // مسح الـ cache عند تغيير الفلاتر
                    SearchLogic.clearCache();
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              _buildFilterSection(
                title: AppLocalizations.of(context)?.complexity ?? 'Complexity',
                items: remindersNotifier.complexities,
                selectedItem: _filterState.complexity,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _filterState = _filterState.copyWith(
                      complexity: (selected && item != allLabel) ? item : null,
                    );
                    print(
                        'تم تعيين تصفية التعقيد إلى: ${_filterState.complexity}');
                    _saveFilters();
                    // مسح الـ cache عند تغيير الفلاتر
                    SearchLogic.clearCache();
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              _buildFilterSection(
                title: AppLocalizations.of(context)?.domains ?? 'Domains',
                items: remindersNotifier.domains,
                selectedItem: _filterState.domain,
                onSelected: (selected, item) {
                  final isArabic =
                      Provider.of<LanguageManager>(context, listen: false)
                              .locale
                              .languageCode ==
                          'ar';
                  final allLabel = isArabic ? 'الكل' : 'All';
                  setState(() {
                    _filterState = _filterState.copyWith(
                      domain: (selected && item != allLabel) ? item : null,
                    );
                    print('تم تعيين تصفية المجال إلى: ${_filterState.domain}');
                    _saveFilters();
                    // مسح الـ cache عند تغيير الفلاتر
                    SearchLogic.clearCache();
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
                _filterState = _filterState.clear();
                print('تم إزالة جميع التصفيات');
                _saveFilters();
                // مسح الـ cache عند تغيير الفلاتر
                SearchLogic.clearCache();
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
            // مسح الـ cache بعد تغيير حالة التذكير
            SearchLogic.clearCache();
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
                    memCacheWidth: 600,
                    memCacheHeight: 400,
                    cacheKey: 'reminder_${reminder.id}',
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

                  // if (reminder.siteLogo != null && reminder.siteLogo!.isNotEmpty)
                  //   Padding(
                  //     padding: const EdgeInsets.only(top: 12.0),
                  //     child: Row(
                  //       children: [
                  //         Container(
                  //           width: 24,
                  //           height: 24,
                  //           decoration: BoxDecoration(
                  //             borderRadius: BorderRadius.circular(4),
                  //           ),
                  //           child: CachedNetworkImage(
                  //             imageUrl: reminder.siteLogo!,
                  //             fit: BoxFit.contain,
                  //             memCacheWidth: 48,
                  //             memCacheHeight: 48,
                  //             cacheKey: 'logo_${reminder.id}',
                  //             placeholder: (context, url) => Container(
                  //               color: Colors.grey.withOpacity(0.1),
                  //             ),
                  //             errorWidget: (context, url, error) => Container(
                  //               color: Colors.grey.withOpacity(0.1),
                  //               child: const Icon(Icons.error, size: 16),
                  //             ),
                  //           ),
                  //         ),
                  //         if (reminder.siteName != null && reminder.siteName!.isNotEmpty)
                  //           Padding(
                  //             padding: const EdgeInsets.only(right: 8.0),
                  //             child: Text(
                  //               reminder.siteName!,
                  //               style: const TextStyle(
                  //                 color: Colors.grey,
                  //                 fontSize: 12,
                  //               ),
                  //             ),
                  //           ),
                  //      ],
                  //  ),
                  //),
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
