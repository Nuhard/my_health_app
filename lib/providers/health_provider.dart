import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

class HealthProvider with ChangeNotifier {
  final DatabaseService _localDb = DatabaseService.instance;
  final SyncService _syncService = SyncService.instance;

  List<Map<String, dynamic>> _healthLogs = [];
  List<Map<String, dynamic>> _symptoms = [];
  bool _isLoading = false;
  String? _userId;

  List<Map<String, dynamic>> get healthLogs => _healthLogs;
  List<Map<String, dynamic>> get symptoms => _symptoms;
  bool get isLoading => _isLoading;

  // Initialize provider with user ID
  Future<void> initialize(String userId) async {
    _userId = userId;
    await loadHealthLogs();
    await loadSymptoms();
  }

  // Load health logs from local DB
  Future<void> loadHealthLogs() async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _healthLogs = await _localDb.getHealthLogs(_userId!);
      _healthLogs.sort((a, b) => b['date'].compareTo(a['date']));
    } catch (e) {
      print('Error loading health logs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load symptoms from local DB
  Future<void> loadSymptoms() async {
    if (_userId == null) return;

    try {
      _symptoms = await _localDb.getSymptoms(_userId!);
      _symptoms.sort((a, b) => b['createdAt'].compareTo(a['createdAt']));
      notifyListeners();
    } catch (e) {
      print('Error loading symptoms: $e');
    }
  }

  // Add health log
  Future<void> addHealthLog({
    required String meal,
    required String physicalActivity,
    required double weight,
    required String mood,
    required DateTime date,
    String? notes,
  }) async {
    if (_userId == null) return;

    final logId = const Uuid().v4();
    final log = {
      'id': logId,
      'userId': _userId!,
      'date': date.toIso8601String(),
      'meal': meal,
      'physicalActivity': physicalActivity,
      'weight': weight,
      'mood': mood,
      'notes': notes ?? '',
      'isSynced': 0,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    await _localDb.createHealthLog(log);
    await loadHealthLogs();

    // Try to sync if online
    _syncService.syncAll();
  }

  // Update health log
  Future<void> updateHealthLog(String logId, Map<String, dynamic> updates) async {
    final existingLog = _healthLogs.firstWhere((log) => log['id'] == logId);
    final updatedLog = {
      ...existingLog,
      ...updates,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    await _localDb.updateHealthLog(logId, updatedLog);
    await loadHealthLogs();

    _syncService.syncAll();
  }

  // Delete health log
  Future<void> deleteHealthLog(String logId) async {
    await _localDb.deleteHealthLog(logId);
    await loadHealthLogs();

    _syncService.syncAll();
  }

  // Add symptom
  Future<void> addSymptom({
    required String symptomName,
    required String severity,
    required DateTime onsetDate,
  }) async {
    if (_userId == null) return;

    final symptomId = const Uuid().v4();
    final symptom = {
      'id': symptomId,
      'userId': _userId!,
      'symptomName': symptomName,
      'severity': severity,
      'onsetDate': onsetDate.toIso8601String(),
      'isSynced': 0,
      'createdAt': DateTime.now().toIso8601String(),
    };

    await _localDb.createSymptom(symptom);
    await loadSymptoms();

    _syncService.syncAll();
  }

  // Delete symptom
  Future<void> deleteSymptom(String symptomId) async {
    await _localDb.deleteSymptom(symptomId);
    await loadSymptoms();

    _syncService.syncAll();
  }

  // Get analytics data
  Map<String, dynamic> getAnalytics() {
    if (_healthLogs.isEmpty) {
      return {
        'totalLogs': 0,
        'averageWeight': 0.0,
        'moodDistribution': {},
        'activityCount': 0,
      };
    }

    // Total logs
    final totalLogs = _healthLogs.length;

    // Average weight
    final weights = _healthLogs
        .map((log) => log['weight'] as double)
        .where((w) => w > 0);
    final averageWeight = weights.isNotEmpty
        ? weights.reduce((a, b) => a + b) / weights.length
        : 0.0;

    // Mood distribution
    final moodDistribution = <String, int>{};
    for (var log in _healthLogs) {
      final mood = log['mood'] as String;
      moodDistribution[mood] = (moodDistribution[mood] ?? 0) + 1;
    }

    // Activity count
    final activityCount = _healthLogs
        .where((log) => (log['physicalActivity'] as String).isNotEmpty)
        .length;

    // Recent logs (last 7 days)
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentLogs = _healthLogs.where((log) {
      final date = DateTime.parse(log['date']);
      return date.isAfter(sevenDaysAgo);
    }).toList();

    return {
      'totalLogs': totalLogs,
      'averageWeight': averageWeight,
      'moodDistribution': moodDistribution,
      'activityCount': activityCount,
      'recentLogs': recentLogs.length,
      'weeklyData': _getWeeklyData(),
    };
  }

  // Get weekly data for charts
  List<Map<String, dynamic>> _getWeeklyData() {
    final now = DateTime.now();
    final weeklyData = <Map<String, dynamic>>[];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayLogs = _healthLogs.where((log) {
        final logDate = DateTime.parse(log['date']);
        return logDate.year == date.year &&
            logDate.month == date.month &&
            logDate.day == date.day;
      }).toList();

      final avgWeight = dayLogs.isNotEmpty
          ? dayLogs.map((l) => l['weight'] as double).reduce((a, b) => a + b) /
              dayLogs.length
          : 0.0;

      weeklyData.add({
        'date': date,
        'day': _getDayName(date.weekday),
        'weight': avgWeight,
        'logs': dayLogs.length,
      });
    }

    return weeklyData;
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // Clear all data (on logout)
  Future<void> clearData() async {
    _healthLogs = [];
    _symptoms = [];
    _userId = null;
    notifyListeners();
  }
}