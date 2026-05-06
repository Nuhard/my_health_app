import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/enhanced_health_summary.dart';

class HealthSummaryService {
  static final HealthSummaryService instance = HealthSummaryService._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  HealthSummaryService._init();

  /// Generate comprehensive health summary for a user
  /// Period: Last 30 days by default
  Future<EnhancedHealthSummary> generateHealthSummary({
    required String userId,
    String? appointmentId,
    int periodDays = 30,
  }) async {
    print('🔄 Generating health summary for user: $userId');
    
    final periodEnd = DateTime.now();
    final periodStart = periodEnd.subtract(Duration(days: periodDays));
    
    try {
      // Fetch all necessary data in parallel
      final results = await Future.wait([
        _fetchPatientOverview(userId),
        _fetchSymptomAnalysis(userId, periodStart, periodEnd),
        _fetchNutritionInsights(userId, periodStart, periodEnd),
        _fetchActivityWellness(userId, periodStart, periodEnd),
        _fetchMedicationAdherence(userId, periodStart, periodEnd),
      ]);
      
      final patientOverview = results[0] as PatientOverview;
      final symptomAnalysis = results[1] as SymptomAnalysis;
      final nutritionInsights = results[2] as NutritionInsights;
      final activityWellness = results[3] as ActivityWellness;
      final medicationAdherence = results[4] as MedicationAdherence?;
      
      // Calculate overall health score (0-100)
      final healthScore = _calculateHealthScore(
        symptomAnalysis,
        nutritionInsights,
        activityWellness,
        medicationAdherence,
      );
      
      final summaryData = HealthSummaryData(
        patientOverview: patientOverview,
        symptomAnalysis: symptomAnalysis,
        nutritionInsights: nutritionInsights,
        activityWellness: activityWellness,
        medicationAdherence: medicationAdherence,
        healthScore: healthScore,
      );
      
      final summaryId = const Uuid().v4();
      final summary = EnhancedHealthSummary(
        id: summaryId,
        userId: userId,
        appointmentId: appointmentId,
        generatedAt: DateTime.now(),
        periodStart: periodStart,
        periodEnd: periodEnd,
        summaryData: summaryData,
        status: 'draft',
        sharedWith: [],
      );
      
      // Save to Firestore
      await _firestore
          .collection('health_summaries')
          .doc(summaryId)
          .set(summary.toJson());
      
      print('✅ Health summary generated: $summaryId');
      return summary;
      
    } catch (e) {
      print('❌ Error generating health summary: $e');
      rethrow;
    }
  }

  /// Fetch patient overview from profile
  Future<PatientOverview> _fetchPatientOverview(String userId) async {
    try {
      final profileDoc = await _firestore.collection('profiles').doc(userId).get();
      
      if (!profileDoc.exists) {
        return PatientOverview(
          name: 'Unknown',
          age: 0,
          gender: 'Not specified',
        );
      }
      
      final data = profileDoc.data()!;
      return PatientOverview(
        name: data['name'] ?? 'Unknown',
        age: data['age'] ?? 0,
        gender: data['gender'] ?? 'Not specified',
        bmi: data['bmi']?.toDouble(),
        bmiCategory: data['bmiCategory'],
        bloodGroup: data['bloodGroup'],
        allergies: data['allergies'],
        chronicConditions: data['chronicConditions'],
        currentMedications: data['currentMedications'],
      );
    } catch (e) {
      print('⚠️ Error fetching patient overview: $e');
      return PatientOverview(name: 'Unknown', age: 0, gender: 'Not specified');
    }
  }

  /// Analyze symptoms from the period
  Future<SymptomAnalysis> _fetchSymptomAnalysis(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      // ✅ FIXED: Changed 'date' to 'onsetDate'
      final symptomsSnapshot = await _firestore
          .collection('symptoms')
          .where('userId', isEqualTo: userId)
          .where('onsetDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('onsetDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      
      if (symptomsSnapshot.docs.isEmpty) {
        return SymptomAnalysis(
          totalSymptoms: 0,
          topSymptoms: [],
          redFlags: [],
          severityTrend: 'stable',
        );
      }
      
      // Group symptoms by name
      final Map<String, List<Map<String, dynamic>>> symptomGroups = {};
      final List<Map<String, dynamic>> allSymptoms = [];
      
      for (var doc in symptomsSnapshot.docs) {
        final data = doc.data();
        // ✅ FIXED: Changed 'symptom' to 'symptomName' with null safety
        final symptomName = data['symptomName'] as String? ?? 'Unknown';
        allSymptoms.add(data);
        
        if (!symptomGroups.containsKey(symptomName)) {
          symptomGroups[symptomName] = [];
        }
        symptomGroups[symptomName]!.add(data);
      }
      
      // Create symptom patterns
      final List<SymptomPattern> patterns = [];
      
      for (var entry in symptomGroups.entries) {
        final symptomName = entry.key;
        final occurrences = entry.value;
        
        // ✅ FIXED: Added null safety for severity
        final severities = occurrences
            .map((s) => s['severity'] as String? ?? 'mild')
            .toList();
        final avgSeverity = _calculateAverageSeverity(severities);
        
        // ✅ FIXED: Changed 'date' to 'onsetDate'
        final dates = occurrences
            .map((s) => (s['onsetDate'] as Timestamp).toDate())
            .toList()
          ..sort();
        
        patterns.add(SymptomPattern(
          symptomName: symptomName,
          frequency: occurrences.length,
          averageSeverity: avgSeverity,
          firstOccurrence: dates.first,
          lastOccurrence: dates.last,
        ));
      }
      
      // Sort by frequency
      patterns.sort((a, b) => b.frequency.compareTo(a.frequency));
      
      // Detect red flags
      final redFlags = _detectRedFlags(allSymptoms);
      
      // Determine severity trend
      final severityTrend = _determineSeverityTrend(allSymptoms);
      
      return SymptomAnalysis(
        totalSymptoms: allSymptoms.length,
        topSymptoms: patterns.take(5).toList(),
        redFlags: redFlags,
        severityTrend: severityTrend,
      );
    } catch (e) {
      print('⚠️ Error fetching symptom analysis: $e');
      return SymptomAnalysis(
        totalSymptoms: 0,
        topSymptoms: [],
        redFlags: [],
        severityTrend: 'stable',
      );
    }
  }

  /// Analyze nutrition from health logs
  Future<NutritionInsights> _fetchNutritionInsights(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      // ✅ Health logs use 'date' field - this is correct!
      final logsSnapshot = await _firestore
          .collection('health_logs')
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      
      if (logsSnapshot.docs.isEmpty) {
        return NutritionInsights(
          averageCalories: 0,
          macroDistribution: {'carbs': 0, 'protein': 0, 'fat': 0},
          averageHydration: 0,
          dietaryPattern: 'No data',
          concerns: ['No nutrition data available'],
        );
      }
      
      double totalCalories = 0;
      double totalCarbs = 0;
      double totalProtein = 0;
      double totalFat = 0;
      double totalWater = 0;
      int daysWithData = 0;
      
      for (var doc in logsSnapshot.docs) {
        final data = doc.data();
        // ✅ FIXED: Using correct field names from health_logs
        totalCalories += (data['totalCalories'] as num?)?.toDouble() ?? 0;
        totalCarbs += (data['totalCarbs'] as num?)?.toDouble() ?? 0;
        totalProtein += (data['totalProtein'] as num?)?.toDouble() ?? 0;
        totalFat += (data['totalFat'] as num?)?.toDouble() ?? 0;
        totalWater += (data['waterIntake'] as num?)?.toDouble() ?? 0;
        daysWithData++;
      }
      
      final avgCalories = daysWithData > 0 ? totalCalories / daysWithData : 0;
      final avgWater = daysWithData > 0 ? totalWater / daysWithData : 0;
      
      // Calculate macro percentages
      final totalMacros = totalCarbs + totalProtein + totalFat;
      final macroDistribution = totalMacros > 0
          ? {
              'carbs': (totalCarbs / totalMacros * 100),
              'protein': (totalProtein / totalMacros * 100),
              'fat': (totalFat / totalMacros * 100),
            }
          : {'carbs': 0.0, 'protein': 0.0, 'fat': 0.0};
      
      // Determine dietary pattern
      final dietaryPattern = _determineDietaryPattern(macroDistribution);
      
      // Identify concerns
      final concerns = _identifyNutritionConcerns(
        avgCalories.toDouble(),
        macroDistribution,
        avgWater.toDouble(),
      );
      
      return NutritionInsights(
        averageCalories: avgCalories.toDouble(),
        macroDistribution: macroDistribution,
        averageHydration: avgWater.toDouble(),
        dietaryPattern: dietaryPattern,
        concerns: concerns,
      );
    } catch (e) {
      print('⚠️ Error fetching nutrition insights: $e');
      return NutritionInsights(
        averageCalories: 0,
        macroDistribution: {'carbs': 0, 'protein': 0, 'fat': 0},
        averageHydration: 0,
        dietaryPattern: 'Unknown',
        concerns: ['Error analyzing nutrition data'],
      );
    }
  }


  /// Analyze activity and wellness
  Future<ActivityWellness> _fetchActivityWellness(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final logsSnapshot = await _firestore
          .collection('health_logs')
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('date', descending: false)
          .get();
      
      if (logsSnapshot.docs.isEmpty) {
        return ActivityWellness(
          totalWorkoutDays: 0,
          averageWorkoutMinutes: 0,
          weightTrend: 'No data',
        );
      }
      
      int workoutDays = 0;
      double totalWorkoutMinutes = 0;
      final List<double> weights = [];
      final List<String> moods = [];
      
      for (var doc in logsSnapshot.docs) {
        final data = doc.data();
        
        // ✅ FIXED: Check if activityDetails exists and get duration
        final activityDetails = data['activityDetails'] as Map<String, dynamic>?;
        if (activityDetails != null) {
          final duration = (activityDetails['duration'] as num?)?.toDouble() ?? 0;
          if (duration > 0) {
            workoutDays++;
            totalWorkoutMinutes += duration;
          }
        }
        
        // ✅ Weight field
        final weight = (data['weight'] as num?)?.toDouble();
        if (weight != null && weight > 0) {
          weights.add(weight);
        }
        
        // ✅ Mood field
        final mood = data['mood'] as String?;
        if (mood != null && mood.isNotEmpty) {
          moods.add(mood);
        }
      }
      
      final avgWorkoutMinutes = workoutDays > 0 ? totalWorkoutMinutes / workoutDays : 0;
      
      // Calculate weight change and trend
      double? weightChange;
      String weightTrend = 'No data';
      
      if (weights.length >= 2) {
        weightChange = weights.last - weights.first;
        if (weightChange.abs() < 0.5) {
          weightTrend = 'Stable';
        } else if (weightChange > 0) {
          weightTrend = 'Gaining';
        } else {
          weightTrend = 'Losing';
        }
      }
      
      // Determine average mood
      String? averageMood;
      if (moods.isNotEmpty) {
        final moodCounts = <String, int>{};
        for (var mood in moods) {
          moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
        }
        averageMood = moodCounts.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }
      
      return ActivityWellness(
        totalWorkoutDays: workoutDays,
        averageWorkoutMinutes: avgWorkoutMinutes.toDouble(),
        weightChange: weightChange,
        weightTrend: weightTrend,
        averageMood: averageMood,
      );
    } catch (e) {
      print('⚠️ Error fetching activity wellness: $e');
      return ActivityWellness(
        totalWorkoutDays: 0,
        averageWorkoutMinutes: 0,
        weightTrend: 'Unknown',
      );
    }
  }

  /// Analyze medication adherence (if you have this feature)
  Future<MedicationAdherence?> _fetchMedicationAdherence(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    // If you don't have medication tracking yet, return null
    // This is for future implementation
    return null;
  }

  /// Calculate overall health score (0-100)
  double _calculateHealthScore(
    SymptomAnalysis symptoms,
    NutritionInsights nutrition,
    ActivityWellness activity,
    MedicationAdherence? medication,
  ) {
    double score = 100.0;
    
    // Deduct for symptoms
    if (symptoms.totalSymptoms > 0) {
      score -= (symptoms.totalSymptoms * 2).clamp(0, 30);
    }
    
    if (symptoms.redFlags.isNotEmpty) {
      score -= (symptoms.redFlags.length * 5).clamp(0, 20);
    }
    
    // Deduct for poor nutrition
    if (nutrition.concerns.isNotEmpty) {
      score -= (nutrition.concerns.length * 3).clamp(0, 15);
    }
    
    // Deduct for inactivity
    if (activity.totalWorkoutDays < 3) {
      score -= 10;
    }
    
    // Deduct for medication non-adherence
    if (medication != null && medication.adherenceRate < 80) {
      score -= 15;
    }
    
    return score.clamp(0, 100);
  }

  /// Helper: Calculate average severity
  String _calculateAverageSeverity(List<String> severities) {
    final severityScores = {
      'mild': 1,
      'moderate': 2,
      'severe': 3,
    };
    
    if (severities.isEmpty) return 'mild';
    
    double total = 0;
    for (var severity in severities) {
      total += severityScores[severity.toLowerCase()] ?? 1;
    }
    
    final avg = total / severities.length;
    
    if (avg < 1.5) return 'Mild';
    if (avg < 2.5) return 'Moderate';
    return 'Severe';
  }

  /// Helper: Detect red flags in symptoms
  List<String> _detectRedFlags(List<Map<String, dynamic>> symptoms) {
    final redFlags = <String>[];
    
    for (var symptom in symptoms) {
      // ✅ FIXED: Added null safety
      final severity = (symptom['severity'] as String? ?? 'mild').toLowerCase();
      final symptomName = symptom['symptomName'] as String? ?? 'Unknown';
      
      if (severity == 'severe') {
        redFlags.add('Severe $symptomName detected');
      }
      
      // Add more red flag logic as needed
    }
    
    return redFlags.toSet().toList();
  }

  /// Helper: Determine severity trend
  String _determineSeverityTrend(List<Map<String, dynamic>> symptoms) {
    if (symptoms.length < 3) return 'Stable';
    
    // ✅ FIXED: Changed 'date' to 'onsetDate'
    symptoms.sort((a, b) {
      final dateA = (a['onsetDate'] as Timestamp).toDate();
      final dateB = (b['onsetDate'] as Timestamp).toDate();
      return dateA.compareTo(dateB);
    });
    
    final severityScores = {'mild': 1, 'moderate': 2, 'severe': 3};
    
    // Compare first half vs second half
    final midpoint = symptoms.length ~/ 2;
    final firstHalf = symptoms.sublist(0, midpoint);
    final secondHalf = symptoms.sublist(midpoint);
    
    double firstAvg = firstHalf
        .map((s) => severityScores[(s['severity'] as String).toLowerCase()] ?? 1)
        .reduce((a, b) => a + b) / firstHalf.length;
    
    double secondAvg = secondHalf
        .map((s) => severityScores[(s['severity'] as String).toLowerCase()] ?? 1)
        .reduce((a, b) => a + b) / secondHalf.length;
    
    if ((secondAvg - firstAvg).abs() < 0.3) return 'Stable';
    if (secondAvg > firstAvg) return 'Worsening';
    return 'Improving';
  }

  /// Helper: Determine dietary pattern
  String _determineDietaryPattern(Map<String, double> macros) {
    if (macros['carbs']! > 50) return 'High-Carb';
    if (macros['protein']! > 30) return 'High-Protein';
    if (macros['fat']! > 35) return 'High-Fat';
    return 'Balanced';
  }

  /// Helper: Identify nutrition concerns
  List<String> _identifyNutritionConcerns(
    double avgCalories,
    Map<String, double> macros,
    double avgWater,
  ) {
    final concerns = <String>[];
    
    if (avgCalories < 1500) {
      concerns.add('Low calorie intake');
    } else if (avgCalories > 3000) {
      concerns.add('High calorie intake');
    }
    
    if (macros['protein']! < 15) {
      concerns.add('Insufficient protein');
    }
    
    if (avgWater < 2000) {
      concerns.add('Low hydration');
    }
    
    return concerns;
  }

  /// Get health summary by ID
  Future<EnhancedHealthSummary?> getHealthSummary(String summaryId) async {
    try {
      final doc = await _firestore
          .collection('health_summaries')
          .doc(summaryId)
          .get();
      
      if (!doc.exists) return null;
      
      return EnhancedHealthSummary.fromJson(doc.id, doc.data()!);
    } catch (e) {
      print('❌ Error fetching health summary: $e');
      return null;
    }
  }

  /// Share health summary with doctor
  Future<void> shareWithDoctor(String summaryId, String doctorId) async {
    try {
      await _firestore
          .collection('health_summaries')
          .doc(summaryId)
          .update({
        'sharedWith': FieldValue.arrayUnion([doctorId]),
        'status': 'final',
      });
      
      print('✅ Health summary shared with doctor: $doctorId');
    } catch (e) {
      print('❌ Error sharing health summary: $e');
      rethrow;
    }
  }
}