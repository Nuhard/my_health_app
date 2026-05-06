class HealthSummary {
  final String userId;
  final DateTime generatedAt;
  final List<Map<String, dynamic>> criticalAlerts;
  final List<Map<String, dynamic>> symptomPatterns;
  final Map<String, dynamic> nutritionInsights;
  final Map<String, dynamic> medicationAdherence;
  final Map<String, dynamic> vitalsTrends;
  final List<Map<String, dynamic>> recentActivities;
  final String overallHealthScore;
  final List<String> recommendations;

  HealthSummary({
    required this.userId,
    required this.generatedAt,
    required this.criticalAlerts,
    required this.symptomPatterns,
    required this.nutritionInsights,
    required this.medicationAdherence,
    required this.vitalsTrends,
    required this.recentActivities,
    required this.overallHealthScore,
    required this.recommendations,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'generatedAt': generatedAt.toIso8601String(),
      'criticalAlerts': criticalAlerts,
      'symptomPatterns': symptomPatterns,
      'nutritionInsights': nutritionInsights,
      'medicationAdherence': medicationAdherence,
      'vitalsTrends': vitalsTrends,
      'recentActivities': recentActivities,
      'overallHealthScore': overallHealthScore,
      'recommendations': recommendations,
    };
  }

  // Create from JSON
  factory HealthSummary.fromJson(Map<String, dynamic> json) {
    return HealthSummary(
      userId: json['userId'] ?? '',
      generatedAt: json['generatedAt'] is String
          ? DateTime.parse(json['generatedAt'])
          : DateTime.now(),
      criticalAlerts: List<Map<String, dynamic>>.from(
          json['criticalAlerts'] ?? []),
      symptomPatterns: List<Map<String, dynamic>>.from(
          json['symptomPatterns'] ?? []),
      nutritionInsights: Map<String, dynamic>.from(
          json['nutritionInsights'] ?? {}),
      medicationAdherence: Map<String, dynamic>.from(
          json['medicationAdherence'] ?? {}),
      vitalsTrends: Map<String, dynamic>.from(
          json['vitalsTrends'] ?? {}),
      recentActivities: List<Map<String, dynamic>>.from(
          json['recentActivities'] ?? []),
      overallHealthScore: json['overallHealthScore'] ?? 'N/A',
      recommendations: List<String>.from(json['recommendations'] ?? []),
    );
  }

  // Create empty summary
  factory HealthSummary.empty(String userId) {
    return HealthSummary(
      userId: userId,
      generatedAt: DateTime.now(),
      criticalAlerts: [],
      symptomPatterns: [],
      nutritionInsights: {},
      medicationAdherence: {},
      vitalsTrends: {},
      recentActivities: [],
      overallHealthScore: 'N/A',
      recommendations: [],
    );
  }
}