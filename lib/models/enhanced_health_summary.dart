import 'package:cloud_firestore/cloud_firestore.dart';

class EnhancedHealthSummary {
  final String id;
  final String userId;
  final String? appointmentId;
  final DateTime generatedAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final HealthSummaryData summaryData;
  final String? pdfUrl;
  final String status; 
  final List<String> sharedWith;

  EnhancedHealthSummary({
    required this.id,
    required this.userId,
    this.appointmentId,
    required this.generatedAt,
    required this.periodStart,
    required this.periodEnd,
    required this.summaryData,
    this.pdfUrl,
    required this.status,
    required this.sharedWith,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'appointmentId': appointmentId,
      'generatedAt': Timestamp.fromDate(generatedAt),
      'periodStart': Timestamp.fromDate(periodStart),
      'periodEnd': Timestamp.fromDate(periodEnd),
      'summaryData': summaryData.toJson(),
      'pdfUrl': pdfUrl,
      'status': status,
      'sharedWith': sharedWith,
    };
  }

  factory EnhancedHealthSummary.fromJson(String id, Map<String, dynamic> json) {
    return EnhancedHealthSummary(
      id: id,
      userId: json['userId'],
      appointmentId: json['appointmentId'],
      generatedAt: (json['generatedAt'] as Timestamp).toDate(),
      periodStart: (json['periodStart'] as Timestamp).toDate(),
      periodEnd: (json['periodEnd'] as Timestamp).toDate(),
      summaryData: HealthSummaryData.fromJson(json['summaryData']),
      pdfUrl: json['pdfUrl'],
      status: json['status'],
      sharedWith: List<String>.from(json['sharedWith'] ?? []),
    );
  }
}

class HealthSummaryData {
  final PatientOverview patientOverview;
  final SymptomAnalysis symptomAnalysis;
  final NutritionInsights nutritionInsights;
  final ActivityWellness activityWellness;
  final MedicationAdherence? medicationAdherence;
  final double healthScore;

  HealthSummaryData({
    required this.patientOverview,
    required this.symptomAnalysis,
    required this.nutritionInsights,
    required this.activityWellness,
    this.medicationAdherence,
    required this.healthScore,
  });

  Map<String, dynamic> toJson() {
    return {
      'patientOverview': patientOverview.toJson(),
      'symptomAnalysis': symptomAnalysis.toJson(),
      'nutritionInsights': nutritionInsights.toJson(),
      'activityWellness': activityWellness.toJson(),
      'medicationAdherence': medicationAdherence?.toJson(),
      'healthScore': healthScore,
    };
  }

  factory HealthSummaryData.fromJson(Map<String, dynamic> json) {
    return HealthSummaryData(
      patientOverview: PatientOverview.fromJson(json['patientOverview']),
      symptomAnalysis: SymptomAnalysis.fromJson(json['symptomAnalysis']),
      nutritionInsights: NutritionInsights.fromJson(json['nutritionInsights']),
      activityWellness: ActivityWellness.fromJson(json['activityWellness']),
      medicationAdherence: json['medicationAdherence'] != null
          ? MedicationAdherence.fromJson(json['medicationAdherence'])
          : null,
      healthScore: (json['healthScore'] as num).toDouble(),
    );
  }
}

// ========== SUB-MODELS ==========

class PatientOverview {
  final String name;
  final int age;
  final String gender;
  final double? bmi;
  final String? bmiCategory;
  final String? bloodGroup;
  final String? allergies;
  final String? chronicConditions;
  final String? currentMedications;

  PatientOverview({
    required this.name,
    required this.age,
    required this.gender,
    this.bmi,
    this.bmiCategory,
    this.bloodGroup,
    this.allergies,
    this.chronicConditions,
    this.currentMedications,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'gender': gender,
    'bmi': bmi,
    'bmiCategory': bmiCategory,
    'bloodGroup': bloodGroup,
    'allergies': allergies,
    'chronicConditions': chronicConditions,
    'currentMedications': currentMedications,
  };

  factory PatientOverview.fromJson(Map<String, dynamic> json) => PatientOverview(
    name: json['name'],
    age: json['age'],
    gender: json['gender'],
    bmi: json['bmi']?.toDouble(),
    bmiCategory: json['bmiCategory'],
    bloodGroup: json['bloodGroup'],
    allergies: json['allergies'],
    chronicConditions: json['chronicConditions'],
    currentMedications: json['currentMedications'],
  );
}

class SymptomAnalysis {
  final int totalSymptoms;
  final List<SymptomPattern> topSymptoms;
  final List<String> redFlags;
  final String severityTrend; // improving, worsening, stable

  SymptomAnalysis({
    required this.totalSymptoms,
    required this.topSymptoms,
    required this.redFlags,
    required this.severityTrend,
  });

  Map<String, dynamic> toJson() => {
    'totalSymptoms': totalSymptoms,
    'topSymptoms': topSymptoms.map((s) => s.toJson()).toList(),
    'redFlags': redFlags,
    'severityTrend': severityTrend,
  };

  factory SymptomAnalysis.fromJson(Map<String, dynamic> json) => SymptomAnalysis(
    totalSymptoms: json['totalSymptoms'],
    topSymptoms: (json['topSymptoms'] as List)
        .map((s) => SymptomPattern.fromJson(s))
        .toList(),
    redFlags: List<String>.from(json['redFlags'] ?? []),
    severityTrend: json['severityTrend'],
  );
}

class SymptomPattern {
  final String symptomName;
  final int frequency;
  final String averageSeverity;
  final DateTime? firstOccurrence;
  final DateTime? lastOccurrence;

  SymptomPattern({
    required this.symptomName,
    required this.frequency,
    required this.averageSeverity,
    this.firstOccurrence,
    this.lastOccurrence,
  });

  Map<String, dynamic> toJson() => {
    'symptomName': symptomName,
    'frequency': frequency,
    'averageSeverity': averageSeverity,
    'firstOccurrence': firstOccurrence?.toIso8601String(),
    'lastOccurrence': lastOccurrence?.toIso8601String(),
  };

  factory SymptomPattern.fromJson(Map<String, dynamic> json) => SymptomPattern(
    symptomName: json['symptomName'],
    frequency: json['frequency'],
    averageSeverity: json['averageSeverity'],
    firstOccurrence: json['firstOccurrence'] != null 
        ? DateTime.parse(json['firstOccurrence']) 
        : null,
    lastOccurrence: json['lastOccurrence'] != null 
        ? DateTime.parse(json['lastOccurrence']) 
        : null,
  );
}

class NutritionInsights {
  final double averageCalories;
  final Map<String, double> macroDistribution; // carbs, protein, fat percentages
  final double averageHydration;
  final String dietaryPattern; // balanced, high-carb, high-protein, etc.
  final List<String> concerns; // e.g., "Low protein intake", "Insufficient water"

  NutritionInsights({
    required this.averageCalories,
    required this.macroDistribution,
    required this.averageHydration,
    required this.dietaryPattern,
    required this.concerns,
  });

  Map<String, dynamic> toJson() => {
    'averageCalories': averageCalories,
    'macroDistribution': macroDistribution,
    'averageHydration': averageHydration,
    'dietaryPattern': dietaryPattern,
    'concerns': concerns,
  };

  factory NutritionInsights.fromJson(Map<String, dynamic> json) => NutritionInsights(
    averageCalories: (json['averageCalories'] as num).toDouble(),
    macroDistribution: Map<String, double>.from(json['macroDistribution']),
    averageHydration: (json['averageHydration'] as num).toDouble(),
    dietaryPattern: json['dietaryPattern'],
    concerns: List<String>.from(json['concerns'] ?? []),
  );
}

class ActivityWellness {
  final int totalWorkoutDays;
  final double averageWorkoutMinutes;
  final double? weightChange; // kg (positive = gained, negative = lost)
  final String weightTrend; // gaining, losing, stable
  final String? averageMood; // happy, neutral, sad, stressed

  ActivityWellness({
    required this.totalWorkoutDays,
    required this.averageWorkoutMinutes,
    this.weightChange,
    required this.weightTrend,
    this.averageMood,
  });

  Map<String, dynamic> toJson() => {
    'totalWorkoutDays': totalWorkoutDays,
    'averageWorkoutMinutes': averageWorkoutMinutes,
    'weightChange': weightChange,
    'weightTrend': weightTrend,
    'averageMood': averageMood,
  };

  factory ActivityWellness.fromJson(Map<String, dynamic> json) => ActivityWellness(
    totalWorkoutDays: json['totalWorkoutDays'],
    averageWorkoutMinutes: (json['averageWorkoutMinutes'] as num).toDouble(),
    weightChange: json['weightChange']?.toDouble(),
    weightTrend: json['weightTrend'],
    averageMood: json['averageMood'],
  );
}

class MedicationAdherence {
  final int totalDoses;
  final int missedDoses;
  final double adherenceRate; // percentage
  final List<String> medications;

  MedicationAdherence({
    required this.totalDoses,
    required this.missedDoses,
    required this.adherenceRate,
    required this.medications,
  });

  Map<String, dynamic> toJson() => {
    'totalDoses': totalDoses,
    'missedDoses': missedDoses,
    'adherenceRate': adherenceRate,
    'medications': medications,
  };

  factory MedicationAdherence.fromJson(Map<String, dynamic> json) => MedicationAdherence(
    totalDoses: json['totalDoses'],
    missedDoses: json['missedDoses'],
    adherenceRate: (json['adherenceRate'] as num).toDouble(),
    medications: List<String>.from(json['medications'] ?? []),
  );
}