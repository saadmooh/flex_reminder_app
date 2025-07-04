class CategoryStatistic {
  final String category;
  final String complexity;
  final List<String>? preferredTimes;
  final List<dynamic> savedPosts;

  CategoryStatistic({
    required this.category,
    required this.complexity,
    this.preferredTimes,
    required this.savedPosts,
  });

  factory CategoryStatistic.fromJson(Map<String, dynamic> json) {
    final List<dynamic> data = json['data'] ?? [];
    if (data.isEmpty) {
      return CategoryStatistic(
        category: 'Uncategorized',
        complexity: 'Unknown',
        preferredTimes: [],
        savedPosts: [],
      );
    }

    final List<String> allPreferredTimes = [];
    String category = 'Uncategorized';
    String complexity = 'Unknown';

    for (var item in data) {
      final Map<String, dynamic> statItem = item as Map<String, dynamic>;
      category = statItem['category'] as String? ?? 'Uncategorized';
      complexity = statItem['complexity'] as String? ?? 'Unknown';

      final String preferredTimesString = statItem['preferred_times'] ?? '';
      if (preferredTimesString.isNotEmpty) {
        final timeMatch =
            RegExp(r'Preferred times: (\w+)').firstMatch(preferredTimesString);
        final timePeriod = timeMatch?.group(1);
        if (timePeriod != null) {
          allPreferredTimes.add(timePeriod);
        }
      }
    }

    return CategoryStatistic(
      category: category,
      complexity: complexity,
      preferredTimes: allPreferredTimes,
      savedPosts: [],
    );
  }
}
