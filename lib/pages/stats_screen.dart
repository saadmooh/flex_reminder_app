import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/widgets/upper_app_bar.dart';
import 'package:flex_reminder/widgets/lower_navigation_bar.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class StatsScreen extends StatefulWidget {
  final int initialIndex;

  const StatsScreen({Key? key, this.initialIndex = 1}) : super(key: key);

  @override
  _StatsScreenState createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _noDataAvailable = false;
  Map<String, dynamic>? _savedPostStats;
  Map<String, dynamic>? _openedStatsAnalysis;

  int _currentNavIndex = 1;
  late AppLocalizations localizations;

  @override
  void initState() {
    super.initState();
    _currentNavIndex = widget.initialIndex;
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      // Fetch saved post statistics
      final savedPostResponse = await _apiService.getSavedPostStatistics();
      if (savedPostResponse['statusCode'] == 200) {
        _savedPostStats = savedPostResponse['data'];
      } else {
        throw Exception(
            savedPostResponse['error'] ?? 'Failed to fetch saved post stats');
      }

      // Fetch opened stats analysis
      final openedStatsResponse = await _apiService.getOpenedStatsAnalysis();
      if (openedStatsResponse['statusCode'] == 200) {
        _openedStatsAnalysis = {
          'detailed_stats': openedStatsResponse['detailed_stats'],
          'graph_data': openedStatsResponse['graph_data'],
        };
      } else {
        throw Exception(
            openedStatsResponse['error'] ?? 'Failed to fetch opened stats');
      }

      // Check if there's no data
      if ((_savedPostStats?['total_saved_posts'] == 0 ||
              _savedPostStats == null) &&
          (_openedStatsAnalysis?['detailed_stats']?.isEmpty ?? true)) {
        setState(() => _noDataAvailable = true);
      } else {
        setState(() => _noDataAvailable = false);
      }
    } catch (e) {
      String errorMessage =
          localizations.errorSchedulingNotification(e.toString());
      if (e.toString().contains('Unauthorized') ||
          e.toString().contains('403')) {
        errorMessage = localizations.unauthorizedError;
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/auth');
        }
      }
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    localizations = AppLocalizations.of(context)!;
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        appBar: UpperAppBar(
          title: localizations.stats,
          showSearch: false,
          showSettings: true,
          showLeading: true,
        ),
        backgroundColor: Colors.white,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.black))
            : _noDataAvailable
                ? Center(
                    child: Text(
                      localizations.noDataAvailable,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Score Bar for Reminder Opening Percentage
                        if (_savedPostStats != null)
                          _buildScoreBarCard(localizations.openingPercentage),
                        const SizedBox(height: 16),
                        // Saved Post Statistics
                        if (_savedPostStats != null) ...[
                          _buildStatCard(localizations.remindersTitle,
                              _savedPostStats!['total_saved_posts'].toString()),
                          _buildStatCard(localizations.readReminders,
                              _savedPostStats!['opened_posts'].toString()),
                          _buildStatCard(localizations.unreadReminders,
                              _savedPostStats!['unopened_posts'].toString()),
                        ],
                        const SizedBox(height: 16),
                        // Category Distribution Pie Chart
                        if (_savedPostStats != null &&
                            _savedPostStats!['posts_by_category'] != null)
                          _buildChart(
                              localizations.categories,
                              _buildPieChart(
                                  _savedPostStats!['posts_by_category'])),
                        const SizedBox(height: 16),
                        // Complexity Distribution Pie Chart
                        if (_savedPostStats != null &&
                            _savedPostStats!['posts_by_complexity'] != null)
                          _buildChart(
                              localizations.complexity,
                              _buildPieChart(
                                  _savedPostStats!['posts_by_complexity'])),
                        const SizedBox(height: 16),
                        // Post Opening Trend Line Chart
                        if (_openedStatsAnalysis != null &&
                            _openedStatsAnalysis!['detailed_stats'] != null)
                          _buildChart(
                            localizations.postOpeningTrendLastWeek,
                            _buildLineChart(
                                _openedStatsAnalysis!['detailed_stats']),
                          ),
                      ],
                    ),
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _fetchStats,
          backgroundColor: Colors.black,
          shape: const CircleBorder(),
          child: const Icon(Icons.refresh, color: Colors.white),
        ),
        bottomNavigationBar: LowerNavigationBar(
          currentIndex: _currentNavIndex,
        ),
      ),
    );
  }

  Widget _buildScoreBarCard(String title) {
    // حساب النسبة المئوية
    final int totalPosts = _savedPostStats!['total_saved_posts'] ?? 0;
    final int openedPosts = _savedPostStats!['opened_posts'] ?? 0;
    final double percentage =
        totalPosts > 0 ? (openedPosts / totalPosts) * 100 : 0.0;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: percentage / 100, // القيمة بين 0 و1
              backgroundColor: Colors.grey[300],
              color: Colors.black,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 8),
            Text(
              '${percentage.toStringAsFixed(1)}% ${localizations.ofRemindersOpened}',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(color: Colors.black, fontSize: 16)),
            Text(value,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(String title, Widget chart) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(height: 200, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, dynamic> data) {
    final List<PieChartSectionData> sections = [];
    int index = 0;
    data.forEach((key, value) {
      if (value is int) {
        sections.add(PieChartSectionData(
          value: value.toDouble(),
          title: '$key\n$value',
          color: Colors.primaries[index % Colors.primaries.length],
          radius: 80,
          titleStyle: const TextStyle(color: Colors.black),
        ));
        index++;
      }
    });
    return PieChart(
      PieChartData(
        sections: sections.isEmpty
            ? [PieChartSectionData(value: 1, color: Colors.grey, radius: 80)]
            : sections,
      ),
    );
  }

  Widget _buildLineChart(List<dynamic> detailedStats) {
    // تجميع البيانات حسب اليوم
    Map<String, int> openingsByDay = {};

    // استخراج جميع الفتحات من detailed_stats
    for (var stat in detailedStats) {
      final List<dynamic> openedStats = stat['opened_stats'] ?? [];
      for (var entry in openedStats) {
        final String fullDate = entry['full_date'];
        // استخراج اليوم فقط من التاريخ (مثال: "2025-03-27")
        final String day = fullDate.split(' ')[0];
        openingsByDay[day] = (openingsByDay[day] ?? 0) + 1;
      }
    }

    // إذا لم تكن هناك بيانات، نعرض رسالة
    if (openingsByDay.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    // تحديد نطاق الأيام (أسبوع كامل بناءً على أول تاريخ)
    List<String> daysInRange = [];
    List<DateTime> allDays = [];
    final List<String> days = openingsByDay.keys.toList()..sort();
    final DateTime firstDate = DateTime.parse(days.first);

    // نحدد بداية الأسبوع (الإثنين) بناءً على أول تاريخ
    DateTime startOfWeek =
        firstDate.subtract(Duration(days: firstDate.weekday - 1));
    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      final dayString = day.toString().split(' ')[0]; // مثال: "2025-03-24"
      daysInRange.add(dayString);
      allDays.add(day);
      // إذا لم يكن اليوم موجودًا في البيانات، نضيف 0
      if (!openingsByDay.containsKey(dayString)) {
        openingsByDay[dayString] = 0;
      }
    }

    // إنشاء نقاط الرسم البياني
    final List<FlSpot> spots = [];
    for (int i = 0; i < daysInRange.length; i++) {
      final day = daysInRange[i];
      final count = openingsByDay[day]!.toDouble();
      spots.add(FlSpot(i.toDouble(), count));
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.black,
            barWidth: 4,
            belowBarData: BarAreaData(
              show: true,
              color: Colors.black.withOpacity(0.1),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < allDays.length) {
                  // تحويل التاريخ إلى اسم اليوم
                  final date = allDays[index];
                  final dayName = localizations.locale.languageCode == 'ar'
                      ? _getArabicDayName(date.weekday)
                      : date.weekday == 1
                          ? 'Mon'
                          : date.weekday == 2
                              ? 'Tue'
                              : date.weekday == 3
                                  ? 'Wed'
                                  : date.weekday == 4
                                      ? 'Thu'
                                      : date.weekday == 5
                                          ? 'Fri'
                                          : date.weekday == 6
                                              ? 'Sat'
                                              : 'Sun';
                  return Text(
                    dayName,
                    style: const TextStyle(color: Colors.black, fontSize: 12),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                );
              },
              reservedSize: 40,
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: 6, // 7 أيام (0 إلى 6)
        minY: 0,
        maxY: spots.isEmpty
            ? 1
            : (spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) + 1)
                .toDouble(),
      ),
    );
  }

  // دالة مساعدة للحصول على اسم اليوم بالعربية
  String _getArabicDayName(int weekday) {
    const arabicDays = [
      'الأحد', // Sunday
      'الإثنين', // Monday
      'الثلاثاء', // Tuesday
      'الأربعاء', // Wednesday
      'الخميس', // Thursday
      'الجمعة', // Friday
      'السبت', // Saturday
    ];
    return arabicDays[weekday % 7];
  }
}
