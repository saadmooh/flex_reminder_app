import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flex_reminder/services/api_service.dart';
import 'package:flex_reminder/widgets/upper_app_bar.dart';
import 'package:flex_reminder/widgets/lower_navigation_bar.dart';
import 'package:flex_reminder/l10n/app_localizations.dart';

class StatsScreen extends StatefulWidget {
  final int initialIndex;

  const StatsScreen({super.key, this.initialIndex = 1});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchStats();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    localizations = AppLocalizations.of(context)!;
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _noDataAvailable = false;
    });

    try {
      print('🔄 Fetching stats...');
      
      // Fetch saved post statistics
      final savedPostResponse = await _apiService.getSavedPostStatistics();
      print('📊 Saved post response: $savedPostResponse');
      
      if (savedPostResponse['statusCode'] == 200) {
        _savedPostStats = savedPostResponse['data'];
        print('✅ Saved post stats loaded: $_savedPostStats');
      } else {
        print('❌ Failed to fetch saved post stats: ${savedPostResponse['error']}');
        throw Exception(savedPostResponse['error'] ?? 'Failed to fetch saved post stats');
      }

      // Fetch opened stats analysis
      final openedStatsResponse = await _apiService.getOpenedStatsAnalysis();
      print('📈 Opened stats response: $openedStatsResponse');
      
      if (openedStatsResponse['statusCode'] == 200) {
        _openedStatsAnalysis = {
          'detailed_stats': openedStatsResponse['detailed_stats'],
          'graph_data': openedStatsResponse['graph_data'],
        };
        print('✅ Opened stats loaded: $_openedStatsAnalysis');
      } else {
        print('❌ Failed to fetch opened stats: ${openedStatsResponse['error']}');
        throw Exception(openedStatsResponse['error'] ?? 'Failed to fetch opened stats');
      }

      // Check if there's no data
      final bool hasNoSavedPosts = (_savedPostStats?['total_saved_posts'] ?? 0) == 0;
      final bool hasNoOpenedStats = (_openedStatsAnalysis?['detailed_stats']?.isEmpty ?? true);
      
      if (hasNoSavedPosts && hasNoOpenedStats) {
        setState(() => _noDataAvailable = true);
        print('ℹ️ No data available');
      } else {
        setState(() => _noDataAvailable = false);
        print('✅ Data available');
      }
      
    } catch (e) {
      print('❌ Error fetching stats: $e');
      
      String errorMessage = 'Error fetching statistics: ${e.toString()}';
      
      if (e.toString().contains('Unauthorized') || e.toString().contains('403')) {
        errorMessage = localizations.unauthorizedError;
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/auth');
          return;
        }
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
        // Set no data available if there's an error
        setState(() => _noDataAvailable = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
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
    return Scaffold(
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        localizations.noDataAvailable,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start using the app to see your statistics',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Score Bar for Reminder Opening Percentage
                        if (_savedPostStats != null) ...[
                          _buildScoreBarCard(localizations.openingPercentage),
                          const SizedBox(height: 16),
                          
                          // Saved Post Statistics
                          _buildStatCard(
                            localizations.remindersTitle,
                            (_savedPostStats!['total_saved_posts'] ?? 0).toString(),
                          ),
                          _buildStatCard(
                            localizations.readReminders,
                            (_savedPostStats!['opened_posts'] ?? 0).toString(),
                          ),
                          _buildStatCard(
                            localizations.unreadReminders,
                            (_savedPostStats!['unopened_posts'] ?? 0).toString(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Category Distribution Pie Chart
                        if (_savedPostStats != null && 
                            _savedPostStats!['posts_by_category'] != null &&
                            _savedPostStats!['posts_by_category'].isNotEmpty) ...[
                          _buildChart(
                            localizations.categories,
                            _buildPieChart(_savedPostStats!['posts_by_category']),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Complexity Distribution Pie Chart
                        if (_savedPostStats != null && 
                            _savedPostStats!['posts_by_complexity'] != null &&
                            _savedPostStats!['posts_by_complexity'].isNotEmpty) ...[
                          _buildChart(
                            localizations.complexity,
                            _buildPieChart(_savedPostStats!['posts_by_complexity']),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Post Opening Trend Line Chart
                        if (_openedStatsAnalysis != null && 
                            _openedStatsAnalysis!['detailed_stats'] != null &&
                            _openedStatsAnalysis!['detailed_stats'].isNotEmpty) ...[
                          _buildChart(
                            localizations.postOpeningTrendLastWeek,
                            _buildLineChart(_openedStatsAnalysis!['detailed_stats']),
                          ),
                        ],
                        
                        // Add some bottom padding for the FAB
                        const SizedBox(height: 80),
                      ],
                    ),
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
    );
  }

  Widget _buildScoreBarCard(String title) {
    // Calculate percentage
    final int totalPosts = _savedPostStats!['total_saved_posts'] ?? 0;
    final int openedPosts = _savedPostStats!['opened_posts'] ?? 0;
    final double percentage = totalPosts > 0 ? (openedPosts / totalPosts) * 100 : 0.0;

    return Card(
      color: Colors.white,
      elevation: 2,
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
            const SizedBox(height: 12),
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(5),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: percentage / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.black, fontSize: 16),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(String title, Widget chart) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 200, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          'No data available for chart',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final List<PieChartSectionData> sections = [];
    int index = 0;
    
    data.forEach((key, value) {
      if (value is int && value > 0) {
        sections.add(PieChartSectionData(
          value: value.toDouble(),
          title: '$key\n$value',
          color: Colors.primaries[index % Colors.primaries.length],
          radius: 80,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ));
        index++;
      }
    });

    if (sections.isEmpty) {
      return const Center(
        child: Text(
          'No data available for chart',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _buildLineChart(List<dynamic> detailedStats) {
    try {
      // Group data by day
      Map<String, int> openingsByDay = {};

      // Extract all openings from detailed_stats
      for (var stat in detailedStats) {
        final List<dynamic> openedStats = stat['opened_stats'] ?? [];
        for (var entry in openedStats) {
          final String fullDate = entry['full_date'] ?? '';
          if (fullDate.isNotEmpty) {
            // Extract day only from date (e.g., "2025-03-27")
            final String day = fullDate.split(' ')[0];
            openingsByDay[day] = (openingsByDay[day] ?? 0) + 1;
          }
        }
      }

      // If no data, show message
      if (openingsByDay.isEmpty) {
        return const Center(
          child: Text(
            'No data available for the last week',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      // Determine day range (full week based on first date)
      List<String> daysInRange = [];
      List<DateTime> allDays = [];
      final List<String> days = openingsByDay.keys.toList()..sort();
      final DateTime firstDate = DateTime.parse(days.first);

      // Determine start of week (Monday) based on first date
      DateTime startOfWeek = firstDate.subtract(Duration(days: firstDate.weekday - 1));
      
      for (int i = 0; i < 7; i++) {
        final day = startOfWeek.add(Duration(days: i));
        final dayString = day.toString().split(' ')[0]; // e.g., "2025-03-24"
        daysInRange.add(dayString);
        allDays.add(day);
        // If day doesn't exist in data, add 0
        if (!openingsByDay.containsKey(dayString)) {
          openingsByDay[dayString] = 0;
        }
      }

      // Create chart points
      final List<FlSpot> spots = [];
      for (int i = 0; i < daysInRange.length; i++) {
        final day = daysInRange[i];
        final count = (openingsByDay[day] ?? 0).toDouble();
        spots.add(FlSpot(i.toDouble(), count));
      }

      if (spots.isEmpty) {
        return const Center(
          child: Text(
            'No data points available',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      final double maxY = spots.isEmpty ? 1 : 
          (spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) + 1);

      return LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.black,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: Colors.black.withOpacity(0.1),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.black,
                    strokeWidth: 0,
                  );
                },
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < allDays.length) {
                    // Convert date to day name
                    final date = allDays[index];
                    final dayName = localizations.locale.languageCode == 'ar'
                        ? _getArabicDayName(date.weekday)
                        : _getEnglishDayName(date.weekday);
                    
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        dayName,
                        style: const TextStyle(color: Colors.black, fontSize: 11),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 35,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.black, fontSize: 11),
                  );
                },
                reservedSize: 35,
                interval: 1,
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey[300]!,
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey[300]!,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey[400]!, width: 1),
          ),
          minX: 0,
          maxX: 6, // 7 days (0 to 6)
          minY: 0,
          maxY: maxY,
        ),
      );
    } catch (e) {
      print('❌ Error building line chart: $e');
      return Center(
        child: Text(
          'Error loading chart: ${e.toString()}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }

  // Helper function to get Arabic day name
  String _getArabicDayName(int weekday) {
    const arabicDays = [
      'الإثنين',   // Monday (weekday 1)
      'الثلاثاء',   // Tuesday (weekday 2)
      'الأربعاء',   // Wednesday (weekday 3)
      'الخميس',    // Thursday (weekday 4)
      'الجمعة',    // Friday (weekday 5)
      'السبت',     // Saturday (weekday 6)
      'الأحد',     // Sunday (weekday 7)
    ];
    return arabicDays[weekday - 1]; // weekday is 1-indexed
  }

  // Helper function to get English day name
  String _getEnglishDayName(int weekday) {
    const englishDays = [
      'Mon',  // Monday (weekday 1)
      'Tue',  // Tuesday (weekday 2)
      'Wed',  // Wednesday (weekday 3)
      'Thu',  // Thursday (weekday 4)
      'Fri',  // Friday (weekday 5)
      'Sat',  // Saturday (weekday 6)
      'Sun',  // Sunday (weekday 7)
    ];
    return englishDays[weekday - 1]; // weekday is 1-indexed
  }
}