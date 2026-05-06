import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/data_sharing_service.dart';
import '../services/enhanced_health_summary_service.dart';
import '../models/data_sharing_permission.dart';
import '../models/enhanced_health_summary.dart';

/// Patient Data View for Doctors
/// 
/// Displays patient health data based on approved permissions
/// Shows locked sections for data categories that patient hasn't approved
/// Fetches real-time data from Firestore collections
class PatientDataView extends StatefulWidget {
  final String appointmentId;
  final String patientId;
  final Map<String, dynamic> patientProfile;
  final Map<String, dynamic>? healthSummarySnapshot;

  const PatientDataView({
    super.key,
    required this.appointmentId,
    required this.patientId,
    required this.patientProfile,
    this.healthSummarySnapshot,
  });

  @override
  State<PatientDataView> createState() => _PatientDataViewState();
}

class _PatientDataViewState extends State<PatientDataView> {
  final DataSharingService _dataSharingService = DataSharingService.instance;
  final HealthSummaryService _healthSummaryService = HealthSummaryService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  DataSharingPermission? _permission;
  EnhancedHealthSummary? _healthSummary;
  List<Map<String, dynamic>> _recentSymptoms = [];
  List<Map<String, dynamic>> _recentNutrition = [];
  
  bool _isLoading = true;
  String _permissionStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      // Load permissions first
      final permission = await _dataSharingService.getPermission(
        appointmentId: widget.appointmentId,
        patientId: widget.patientId,
      );

      if (mounted) {
        setState(() {
          _permission = permission;
          _permissionStatus = permission?.status ?? 'pending';
        });
      }

      // If approved, load health data
      if (_permissionStatus == DataSharingPermission.STATUS_APPROVED) {
        await Future.wait([
          _loadHealthSummary(),
          _loadRecentSymptoms(),
          _loadRecentNutrition(),
        ]);
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadHealthSummary() async {
    try {
      // Try to get existing health summary or generate new one
      final summary = await _healthSummaryService.generateHealthSummary(
        userId: widget.patientId,
        appointmentId: widget.appointmentId,
        periodDays: 30,
      );
      
      if (mounted) {
        setState(() => _healthSummary = summary);
      }
    } catch (e) {
      print('Error loading health summary: $e');
    }
  }

  Future<void> _loadRecentSymptoms() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      
      final snapshot = await _firestore
          .collection('symptoms')
          .where('userId', isEqualTo: widget.patientId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .orderBy('date', descending: true)
          .limit(10)
          .get();
      
      if (mounted) {
        setState(() {
          _recentSymptoms = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading symptoms: $e');
    }
  }

  Future<void> _loadRecentNutrition() async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      
      final snapshot = await _firestore
          .collection('health_logs')
          .where('userId', isEqualTo: widget.patientId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
          .orderBy('date', descending: true)
          .limit(7)
          .get();
      
      if (mounted) {
        setState(() {
          _recentNutrition = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading nutrition: $e');
    }
  }

  bool _hasPermission(String category) {
    if (_permission == null) return false;
    return _permission!.isAllowed(category);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // If data sharing not approved yet
    if (_permissionStatus != DataSharingPermission.STATUS_APPROVED) {
      return _buildPendingPermissionView();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Permission Status Banner
          _buildPermissionBanner(),
          const SizedBox(height: 20),

          // Basic Information (Always visible if approved)
          if (_hasPermission(DataSharingPermission.BASIC_INFO))
            _buildBasicInfoSection()
          else
            _buildLockedSection('Basic Information', DataSharingPermission.BASIC_INFO),

          const SizedBox(height: 16),

          // Medical History
          if (_hasPermission(DataSharingPermission.MEDICAL_HISTORY))
            _buildMedicalHistorySection()
          else
            _buildLockedSection('Medical History', DataSharingPermission.MEDICAL_HISTORY),

          const SizedBox(height: 16),

          // Symptom History
          if (_hasPermission(DataSharingPermission.SYMPTOM_HISTORY))
            _buildSymptomHistorySection()
          else
            _buildLockedSection('Symptom History', DataSharingPermission.SYMPTOM_HISTORY),

          const SizedBox(height: 16),

          // Nutrition Logs
          if (_hasPermission(DataSharingPermission.NUTRITION_LOGS))
            _buildNutritionLogsSection()
          else
            _buildLockedSection('Nutrition & Food Logs', DataSharingPermission.NUTRITION_LOGS),

          const SizedBox(height: 16),

          // Activity Data
          if (_hasPermission(DataSharingPermission.ACTIVITY_DATA))
            _buildActivityDataSection()
          else
            _buildLockedSection('Activity & Exercise Data', DataSharingPermission.ACTIVITY_DATA),

          const SizedBox(height: 16),

          // Health Scores
          if (_hasPermission(DataSharingPermission.HEALTH_SCORES))
            _buildHealthScoresSection()
          else
            _buildLockedSection('Health Scores & Analysis', DataSharingPermission.HEALTH_SCORES),

          const SizedBox(height: 16),

          // Lab Reports
          if (_hasPermission(DataSharingPermission.LAB_REPORTS))
            _buildLabReportsSection()
          else
            _buildLockedSection('Lab Reports & Documents', DataSharingPermission.LAB_REPORTS),
        ],
      ),
    );
  }

  // Replace the _buildPendingPermissionView() method in patient_data_view.dart

Widget _buildPendingPermissionView() {
  return Container(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _permissionStatus == 'rejected' 
              ? Icons.folder_off 
              : Icons.hourglass_empty,
          size: 80,
          color: _permissionStatus == 'rejected' 
              ? Colors.orange.shade300 
              : Colors.blue.shade300,
        ),
        const SizedBox(height: 20),
        Text(
          _permissionStatus == 'rejected'
              ? '📋 Patient Will Bring Data'
              : '⏳ Waiting for Patient Approval',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _permissionStatus == 'rejected' 
                ? Colors.orange.shade700 
                : Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _permissionStatus == 'rejected'
              ? 'The patient has chosen not to share their digital health data. They will bring necessary documents during the consultation.'
              : 'The patient has not yet reviewed the data sharing request. They will be notified to approve which health data to share with you.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _permissionStatus == 'rejected' 
                ? Colors.orange.shade50 
                : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _permissionStatus == 'rejected'
                  ? Colors.orange.shade200
                  : Colors.blue.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _permissionStatus == 'rejected' 
                    ? Icons.info_outline 
                    : Icons.tips_and_updates,
                color: _permissionStatus == 'rejected'
                    ? Colors.orange.shade700
                    : Colors.blue.shade700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _permissionStatus == 'rejected'
                      ? 'Proceed with verbal consultation and patient-provided documents.'
                      : 'You can proceed with the consultation using basic patient information and verbal communication.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _permissionStatus == 'rejected'
                        ? Colors.orange.shade900
                        : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
  Widget _buildPermissionBanner() {
    final allowedCategories = _permission?.allowedCategories ?? [];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data Sharing Approved',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient approved ${allowedCategories.length} data ${allowedCategories.length == 1 ? "category" : "categories"}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${allowedCategories.length}/${DataSharingPermission.createDefaultPermissions().length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedSection(String title, String category) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, color: Colors.grey.shade400, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient has not granted access to this data',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return _buildDataSection(
      icon: Icons.person,
      title: 'Basic Information',
      color: Colors.blue,
      child: Column(
        children: [
          _buildInfoRow('Name', widget.patientProfile['name'] ?? 'N/A'),
          _buildInfoRow('Age', '${widget.patientProfile['age'] ?? 'N/A'} years'),
          _buildInfoRow('Gender', widget.patientProfile['gender'] ?? 'N/A'),
          _buildInfoRow('Blood Group', widget.patientProfile['bloodGroup'] ?? 'N/A'),
          if (widget.patientProfile['bmi'] != null && widget.patientProfile['bmi'] > 0)
            _buildInfoRow(
              'BMI',
              '${widget.patientProfile['bmi'].toStringAsFixed(1)} (${widget.patientProfile['bmiCategory'] ?? 'N/A'})',
            ),
        ],
      ),
    );
  }

  Widget _buildMedicalHistorySection() {
    return _buildDataSection(
      icon: Icons.medical_services,
      title: 'Medical History',
      color: Colors.red,
      child: Column(
        children: [
          if (widget.patientProfile['allergies'] != null && 
              widget.patientProfile['allergies'].toString().isNotEmpty)
            _buildInfoRow('Allergies', widget.patientProfile['allergies']),
          if (widget.patientProfile['chronicConditions'] != null && 
              widget.patientProfile['chronicConditions'].toString().isNotEmpty)
            _buildInfoRow('Chronic Conditions', widget.patientProfile['chronicConditions']),
          if (widget.patientProfile['currentMedications'] != null && 
              widget.patientProfile['currentMedications'].toString().isNotEmpty)
            _buildInfoRow('Current Medications', widget.patientProfile['currentMedications']),
          if (widget.patientProfile['allergies'] == null && 
              widget.patientProfile['chronicConditions'] == null &&
              widget.patientProfile['currentMedications'] == null)
            const Text('No medical history recorded', style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildSymptomHistorySection() {
    if (_recentSymptoms.isEmpty && _healthSummary == null) {
      return _buildDataSection(
        icon: Icons.sick,
        title: 'Symptom History',
        color: Colors.orange,
        child: const Text('No symptom data available', style: TextStyle(fontStyle: FontStyle.italic)),
      );
    }

    final symptomPatterns = _healthSummary?.summaryData.symptomAnalysis.topSymptoms ?? [];
    
    return _buildDataSection(
      icon: Icons.sick,
      title: 'Symptom History',
      color: Colors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Stats
          if (_healthSummary != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Symptoms',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Text(
                          '${_healthSummary!.summaryData.symptomAnalysis.totalSymptoms}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trend',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Text(
                          _healthSummary!.summaryData.symptomAnalysis.severityTrend,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (_healthSummary!.summaryData.symptomAnalysis.redFlags.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${_healthSummary!.summaryData.symptomAnalysis.redFlags.length} Alert${_healthSummary!.summaryData.symptomAnalysis.redFlags.length > 1 ? "s" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Red Flags
            if (_healthSummary!.summaryData.symptomAnalysis.redFlags.isNotEmpty) ...[
              Text(
                '⚠️ Critical Alerts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              ..._healthSummary!.summaryData.symptomAnalysis.redFlags.map((flag) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          flag,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
            ],
          ],
          
          // Top Symptom Patterns
          if (symptomPatterns.isNotEmpty) ...[
            const Text(
              'Top Symptom Patterns (30 days)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...symptomPatterns.map((pattern) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pattern.symptomName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getSeverityColor(pattern.averageSeverity),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            pattern.averageSeverity,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.repeat, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Frequency: ${pattern.frequency}x',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Last: ${_formatDate(pattern.lastOccurrence)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ] else if (_recentSymptoms.isEmpty) ...[
            const Text('No symptoms recorded in the last 30 days', style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'severe':
        return Colors.red.shade600;
      case 'moderate':
        return Colors.orange.shade600;
      case 'mild':
        return Colors.yellow.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat('MMM dd').format(date);
  }

  Widget _buildNutritionLogsSection() {
    if (_healthSummary == null && _recentNutrition.isEmpty) {
      return _buildDataSection(
        icon: Icons.restaurant,
        title: 'Nutrition Logs',
        color: Colors.green,
        child: const Text('No nutrition data available', style: TextStyle(fontStyle: FontStyle.italic)),
      );
    }

    final nutritionInsights = _healthSummary?.summaryData.nutritionInsights;
    
    return _buildDataSection(
      icon: Icons.restaurant,
      title: 'Nutrition Logs',
      color: Colors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nutritionInsights != null) ...[
            // Summary Stats
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Avg Daily Calories',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              '${nutritionInsights.averageCalories.round()} kcal',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dietary Pattern',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              nutritionInsights.dietaryPattern,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Avg Hydration',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              '${nutritionInsights.averageHydration.round()} ml',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Macro Distribution
            const Text(
              'Macronutrient Distribution',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildMacroBar('Carbs', nutritionInsights.macroDistribution['carbs'] ?? 0, Colors.orange),
                  const SizedBox(height: 8),
                  _buildMacroBar('Protein', nutritionInsights.macroDistribution['protein'] ?? 0, Colors.blue),
                  const SizedBox(height: 8),
                  _buildMacroBar('Fat', nutritionInsights.macroDistribution['fat'] ?? 0, Colors.purple),
                ],
              ),
            ),
            
            // Concerns
            if (nutritionInsights.concerns.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '⚠️ Nutrition Concerns',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              ...nutritionInsights.concerns.map((concern) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          concern,
                          style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ] else ...[
            const Text('No nutrition data available for the past 30 days', style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroBar(String label, double percentage, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (percentage / 100).clamp(0, 1),
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 45,
          child: Text(
            '${percentage.round()}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityDataSection() {
    if (_healthSummary == null) {
      return _buildDataSection(
        icon: Icons.fitness_center,
        title: 'Activity & Exercise',
        color: Colors.purple,
        child: const Text('No activity data available', style: TextStyle(fontStyle: FontStyle.italic)),
      );
    }

    final activityWellness = _healthSummary!.summaryData.activityWellness;
    
    return _buildDataSection(
      icon: Icons.fitness_center,
      title: 'Activity & Exercise',
      color: Colors.purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workout Days',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          Text(
                            '${activityWellness.totalWorkoutDays} days',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Avg Duration',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          Text(
                            '${activityWellness.averageWorkoutMinutes.round()} min',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weight Trend',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          Row(
                            children: [
                              Icon(
                                _getWeightTrendIcon(activityWellness.weightTrend),
                                size: 16,
                                color: _getWeightTrendColor(activityWellness.weightTrend),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                activityWellness.weightTrend,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _getWeightTrendColor(activityWellness.weightTrend),
                                ),
                              ),
                              if (activityWellness.weightChange != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(${activityWellness.weightChange! > 0 ? "+" : ""}${activityWellness.weightChange!.toStringAsFixed(1)} kg)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (activityWellness.averageMood != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Average Mood',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              _getMoodEmoji(activityWellness.averageMood!),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getWeightTrendIcon(String trend) {
    switch (trend.toLowerCase()) {
      case 'gaining':
        return Icons.trending_up;
      case 'losing':
        return Icons.trending_down;
      case 'stable':
        return Icons.trending_flat;
      default:
        return Icons.help_outline;
    }
  }

  Color _getWeightTrendColor(String trend) {
    switch (trend.toLowerCase()) {
      case 'gaining':
        return Colors.orange.shade700;
      case 'losing':
        return Colors.blue.shade700;
      case 'stable':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String _getMoodEmoji(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'neutral':
        return '😐';
      case 'sad':
        return '😢';
      case 'stressed':
        return '😰';
      case 'energetic':
        return '⚡';
      case 'tired':
        return '😴';
      default:
        return '😊';
    }
  }

  Widget _buildHealthScoresSection() {
    if (_healthSummary == null) {
      return _buildDataSection(
        icon: Icons.analytics,
        title: 'Health Scores',
        color: Colors.teal,
        child: const Text('No health scores available', style: TextStyle(fontStyle: FontStyle.italic)),
      );
    }

    final healthScore = _healthSummary!.summaryData.healthScore;
    final scoreColor = _getHealthScoreColor(healthScore);
    final scoreLabel = _getHealthScoreLabel(healthScore);
    
    return _buildDataSection(
      icon: Icons.analytics,
      title: 'Health Scores',
      color: Colors.teal,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scoreColor.withOpacity(0.1), scoreColor.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scoreColor.withOpacity(0.3), width: 2),
            ),
            child: Column(
              children: [
                Text(
                  'Overall Health Score',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${healthScore.round()}',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    scoreLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Progress Bar
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (healthScore / 100).clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [scoreColor, scoreColor.withOpacity(0.7)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Based on 30-day analysis of symptoms, nutrition, activity, and overall wellness',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getHealthScoreColor(double score) {
    if (score >= 80) return Colors.green.shade600;
    if (score >= 60) return Colors.blue.shade600;
    if (score >= 40) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  String _getHealthScoreLabel(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs Attention';
  }

  Widget _buildLabReportsSection() {
    return _buildDataSection(
      icon: Icons.description,
      title: 'Lab Reports & Documents',
      color: Colors.indigo,
      child: const Text('No lab reports available', style: TextStyle(fontStyle: FontStyle.italic)),
    );
  }

  Widget _buildDataSection({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}