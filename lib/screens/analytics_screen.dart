import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/health_provider.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Analytics'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Consumer<HealthProvider>(
        builder: (context, healthProvider, child) {
          final analytics = healthProvider.getAnalytics();
          final weeklyData = analytics['weeklyData'] as List<Map<String, dynamic>>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Logs',
                        '${analytics['totalLogs']}',
                        Icons.assignment,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Avg Weight',
                        '${analytics['averageWeight'].toStringAsFixed(1)} kg',
                        Icons.monitor_weight,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Active Days',
                        '${analytics['activityCount']}',
                        Icons.fitness_center,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'This Week',
                        '${analytics['recentLogs']}',
                        Icons.calendar_today,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Weekly Weight Chart
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📊 Weekly Weight Trend',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: LineChart(
                            LineChartData(
                              gridData: FlGridData(show: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      if (value.toInt() < weeklyData.length) {
                                        return Text(
                                          weeklyData[value.toInt()]['day'],
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: weeklyData.asMap().entries.map((entry) {
                                    return FlSpot(
                                      entry.key.toDouble(),
                                      entry.value['weight'] as double,
                                    );
                                  }).toList(),
                                  isCurved: true,
                                  color: Colors.deepPurple,
                                  barWidth: 3,
                                  dotData: FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.deepPurple.withOpacity(0.2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Mood Distribution
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '😊 Mood Distribution',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sections: _buildPieChartSections(
                                analytics['moodDistribution'] as Map<String, int>,
                              ),
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildMoodLegend(analytics['moodDistribution'] as Map<String, int>),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Health Tips
                Card(
                  elevation: 4,
                  color: Colors.teal.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.lightbulb, color: Colors.teal),
                            SizedBox(width: 8),
                            Text(
                              'Health Tips',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildHealthTip('💧', 'Drink at least 8 glasses of water daily'),
                        _buildHealthTip('🏃', 'Aim for 30 minutes of activity daily'),
                        _buildHealthTip('🥗', 'Include fruits and vegetables in every meal'),
                        _buildHealthTip('😴', 'Get 7-8 hours of quality sleep'),
                        _buildHealthTip('📝', 'Track your health consistently'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(Map<String, int> moodDist) {
    final colors = {
      'Happy': Colors.green,
      'Neutral': Colors.blue,
      'Sad': Colors.orange,
      'Tired': Colors.purple,
    };

    final total = moodDist.values.fold(0, (sum, val) => sum + val);
    if (total == 0) return [];

    return moodDist.entries.map((entry) {
      final percentage = (entry.value / total * 100).toStringAsFixed(1);
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '$percentage%',
        color: colors[entry.key] ?? Colors.grey,
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildMoodLegend(Map<String, int> moodDist) {
    final colors = {
      'Happy': Colors.green,
      'Neutral': Colors.blue,
      'Sad': Colors.orange,
      'Tired': Colors.purple,
    };

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: moodDist.entries.map((entry) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors[entry.key],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text('${entry.key}: ${entry.value}'),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildHealthTip(String emoji, String tip) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}