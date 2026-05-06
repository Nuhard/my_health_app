import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'health_summary_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Master's Level PDF Report Generation Service
/// 
/// Features:
/// - Comprehensive health reports with all user data
/// - Professional formatting with charts and tables
/// - Export to PDF with download/share capabilities
/// - Multiple report types (full, summary, appointment-specific)
/// - Branding and customization
class PdfReportService {
  final HealthSummaryService _healthSummaryService = HealthSummaryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate comprehensive health report for a user
  Future<File> generateComprehensiveHealthReport({
    required String userId,
    required String userName,
    required String userEmail,
    int days = 30,
  }) async {
    try {
      // Fetch health summary
      final healthSummary = await _healthSummaryService.generateHealthSummary(
        userId,
        days: days,
      );

      // Fetch user profile
      final userProfile = await _fetchUserProfile(userId);

      // Create PDF document
      final pdf = pw.Document();

      // Add pages
      _addCoverPage(pdf, userName, userEmail, days);
      _addHealthSummaryPage(pdf, healthSummary);
      _addCriticalAlertsPage(pdf, healthSummary);
      _addSymptomsPage(pdf, healthSummary);
      _addMedicationPage(pdf, healthSummary);
      _addNutritionPage(pdf, healthSummary);
      _addVitalsPage(pdf, healthSummary);
      _addRecommendationsPage(pdf, healthSummary);

      // Save PDF
      final file = await _savePdf(pdf, 'Health_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      
      print('✅ PDF report generated: ${file.path}');
      return file;
    } catch (e) {
      print('❌ Error generating PDF report: $e');
      throw Exception('Failed to generate PDF report: $e');
    }
  }

  /// Generate appointment-specific report
  Future<File> generateAppointmentReport({
    required String userId,
    required String userName,
    required String appointmentId,
  }) async {
    try {
      // Fetch appointment details
      final appointmentDoc = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();

      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }

      final appointment = appointmentDoc.data()!;

      // Create PDF
      final pdf = pw.Document();

      // Add appointment details page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader('Appointment Report'),
              pw.SizedBox(height: 30),
              _buildInfoSection('Patient Information', [
                ['Name:', userName],
                ['Appointment ID:', appointmentId],
                ['Date:', _formatDate(appointment['appointmentDate'])],
                ['Time:', appointment['timeSlot'] ?? 'N/A'],
                ['Doctor:', appointment['doctorName'] ?? 'N/A'],
                ['Specialization:', appointment['specialization'] ?? 'N/A'],
              ]),
              pw.SizedBox(height: 20),
              _buildInfoSection('Appointment Details', [
                ['Status:', appointment['status']?.toString().toUpperCase() ?? 'N/A'],
                ['Reason:', appointment['reason'] ?? 'No reason provided'],
                if (appointment['notes'] != null && appointment['notes'].toString().isNotEmpty)
                  ['Notes:', appointment['notes']],
              ]),
              // Health summary if available
              if (appointment['healthSummarySnapshot'] != null) ...[
                pw.SizedBox(height: 20),
                _buildHealthContextSection(appointment['healthSummarySnapshot']),
              ],
            ],
          ),
        ),
      );

      final file = await _savePdf(pdf, 'Appointment_Report_$appointmentId.pdf');
      return file;
    } catch (e) {
      print('❌ Error generating appointment report: $e');
      throw Exception('Failed to generate appointment report: $e');
    }
  }

  /// Generate quick summary report (1-page)
  Future<File> generateQuickSummaryReport({
    required String userId,
    required String userName,
  }) async {
    try {
      final healthSummary = await _healthSummaryService.generateHealthSummary(userId, days: 7);

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader('Health Summary (7 Days)'),
              pw.SizedBox(height: 20),
              pw.Text(
                userName,
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
              pw.SizedBox(height: 20),
              _buildQuickStats(healthSummary),
              pw.SizedBox(height: 15),
              if (healthSummary['criticalAlerts'] != null && 
                  (healthSummary['criticalAlerts'] as List).isNotEmpty)
                _buildAlertBox(healthSummary['criticalAlerts'] as List),
              pw.SizedBox(height: 15),
              _buildTopSymptoms(healthSummary['symptomPatterns'] as List? ?? []),
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                'This is a computer-generated report. For medical advice, please consult your healthcare provider.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      );

      final file = await _savePdf(pdf, 'Quick_Summary_${DateTime.now().millisecondsSinceEpoch}.pdf');
      return file;
    } catch (e) {
      throw Exception('Failed to generate quick summary: $e');
    }
  }

  // ========== PDF PAGE BUILDERS ==========

  void _addCoverPage(pw.Document pdf, String userName, String userEmail, int days) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'NUTRITRACK',
                      style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Health & Nutrition Monitoring',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 50),
              pw.Text(
                'Comprehensive Health Report',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 30),
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Patient Name:', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text(userName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 10),
                    pw.Text('Email:', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text(userEmail, style: const pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(height: 10),
                    pw.Text('Report Period:', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text('Last $days days', style: const pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(height: 10),
                    pw.Text('Generated On:', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    pw.Text(
                      DateFormat('dd MMMM yyyy, HH:mm').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Text(
                'Confidential Medical Document',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addHealthSummaryPage(pw.Document pdf, Map<String, dynamic> summary) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Health Overview'),
            pw.SizedBox(height: 20),
            _buildScoreCard(summary['overallHealthScore'] ?? 'N/A'),
            pw.SizedBox(height: 20),
            _buildKeyMetrics(summary),
            pw.SizedBox(height: 20),
            _buildRecentActivity(summary['recentActivities'] as List? ?? []),
          ],
        ),
      ),
    );
  }

  void _addCriticalAlertsPage(pw.Document pdf, Map<String, dynamic> summary) {
    final alerts = summary['criticalAlerts'] as List? ?? [];
    if (alerts.isEmpty) return;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('⚠️ Critical Alerts'),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                border: pw.Border.all(color: PdfColors.red, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'IMMEDIATE ATTENTION REQUIRED',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  ...alerts.take(10).map((alert) {
                    final alertMap = alert as Map<String, dynamic>;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 10),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 8,
                            height: 8,
                            margin: const pw.EdgeInsets.only(top: 5, right: 10),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.red,
                              shape: pw.BoxShape.circle,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  alertMap['message'] ?? 'Alert',
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (alertMap['timestamp'] != null)
                                  pw.Text(
                                    'Detected: ${_formatDate(alertMap['timestamp'])}',
                                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSymptomsPage(pw.Document pdf, Map<String, dynamic> summary) {
    final symptoms = summary['symptomPatterns'] as List? ?? [];
    if (symptoms.isEmpty) return;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Symptom Patterns'),
            pw.SizedBox(height: 20),
            pw.Text(
              'Reported symptoms in the selected period:',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 15),
            _buildSymptomTable(symptoms),
          ],
        ),
      ),
    );
  }

  void _addMedicationPage(pw.Document pdf, Map<String, dynamic> summary) {
    final medication = summary['medicationAdherence'] as Map<String, dynamic>? ?? {};
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Medication Adherence'),
            pw.SizedBox(height: 20),
            _buildMedicationStats(medication),
            pw.SizedBox(height: 20),
            if (medication['medications'] != null)
              _buildMedicationList(medication['medications'] as List),
          ],
        ),
      ),
    );
  }

  void _addNutritionPage(pw.Document pdf, Map<String, dynamic> summary) {
    final nutrition = summary['nutritionInsights'] as Map<String, dynamic>? ?? {};
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Nutrition Summary'),
            pw.SizedBox(height: 20),
            _buildNutritionStats(nutrition),
            pw.SizedBox(height: 20),
            if (nutrition['macroDistribution'] != null)
              _buildMacroDistribution(nutrition['macroDistribution'] as Map<String, dynamic>),
          ],
        ),
      ),
    );
  }

  void _addVitalsPage(pw.Document pdf, Map<String, dynamic> summary) {
    final vitals = summary['vitalsTrends'] as Map<String, dynamic>? ?? {};
    if (vitals.isEmpty) return;
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Vital Signs Trends'),
            pw.SizedBox(height: 20),
            _buildVitalsTable(vitals),
          ],
        ),
      ),
    );
  }

  void _addRecommendationsPage(pw.Document pdf, Map<String, dynamic> summary) {
    final recommendations = summary['recommendations'] as List<dynamic>? ?? [];
    if (recommendations.isEmpty) return;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader('Health Recommendations'),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Personalized Recommendations',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.SizedBox(height: 15),
                  ...recommendations.map((rec) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 12),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 20,
                            height: 20,
                            margin: const pw.EdgeInsets.only(right: 10),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.blue,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                '✓',
                                style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              rec.toString(),
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Note: These recommendations are based on your tracked data. Always consult with a healthcare professional before making significant health changes.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ========== HELPER WIDGETS ==========

  pw.Widget _buildHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.teal, width: 3),
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.teal,
        ),
      ),
    );
  }

  pw.Widget _buildScoreCard(String score) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: [PdfColors.teal, PdfColors.teal700],
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(15)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Overall Health Score',
                  style: const pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  score,
                  style: pw.TextStyle(
                    fontSize: 48,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: 80,
            height: 80,
            decoration: pw.BoxDecoration(
              color: PdfColors.white.withOpacity(0.2),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                '❤️',
                style: const pw.TextStyle(fontSize: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildKeyMetrics(Map<String, dynamic> summary) {
    return pw.Row(
      children: [
        pw.Expanded(child: _buildMetricCard('Symptoms', (summary['symptomPatterns'] as List? ?? []).length.toString(), PdfColors.orange)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _buildMetricCard('Alerts', (summary['criticalAlerts'] as List? ?? []).length.toString(), PdfColors.red)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _buildMetricCard('Activities', (summary['recentActivities'] as List? ?? []).length.toString(), PdfColors.green)),
      ],
    );
  }

  pw.Widget _buildMetricCard(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: color.withOpacity(0.3)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSymptomTable(List symptoms) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableCell('Symptom', isHeader: true),
            _buildTableCell('Frequency', isHeader: true),
            _buildTableCell('Severity', isHeader: true),
            _buildTableCell('Last Reported', isHeader: true),
          ],
        ),
        // Rows
        ...symptoms.take(15).map((symptom) {
          final s = symptom as Map<String, dynamic>;
          return pw.TableRow(
            children: [
              _buildTableCell(s['symptomName'] ?? 'N/A'),
              _buildTableCell(s['frequency']?.toString() ?? '0'),
              _buildTableCell(s['avgSeverity']?.toString() ?? 'N/A'),
              _buildTableCell(_formatDate(s['lastReported'])),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildMedicationStats(Map<String, dynamic> medication) {
    final adherenceRate = medication['adherenceRate'] ?? 0;
    final totalDoses = medication['totalDoses'] ?? 0;
    final missedDoses = medication['missedDoses'] ?? 0;
    final takenDoses = totalDoses - missedDoses;

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn('Adherence Rate', '$adherenceRate%'),
              _buildStatColumn('Total Doses', totalDoses.toString()),
              _buildStatColumn('Taken', takenDoses.toString()),
              _buildStatColumn('Missed', missedDoses.toString()),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatColumn(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.green900,
          ),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _buildMedicationList(List medications) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Current Medications:',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        ...medications.map((med) {
          final m = med as Map<String, dynamic>;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  margin: const pw.EdgeInsets.only(right: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.green,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    '${m['name']} - ${m['dosage']} (${m['frequency']})',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildNutritionStats(Map<String, dynamic> nutrition) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _buildNutritionCard(
            'Avg Calories',
            '${nutrition['averageCalories'] ?? 0} kcal',
            PdfColors.orange,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _buildNutritionCard(
            'Protein',
            '${nutrition['protein'] ?? 0}g',
            PdfColors.red,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _buildNutritionCard(
            'Carbs',
            '${nutrition['carbs'] ?? 0}g',
            PdfColors.blue,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _buildNutritionCard(
            'Fats',
            '${nutrition['fats'] ?? 0}g',
            PdfColors.yellow,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildNutritionCard(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 10, color: color),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMacroDistribution(Map<String, dynamic> macros) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Macronutrient Distribution',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _buildProgressBar('Protein', macros['proteinPercent'] ?? 0, PdfColors.red),
          pw.SizedBox(height: 8),
          _buildProgressBar('Carbs', macros['carbsPercent'] ?? 0, PdfColors.blue),
          pw.SizedBox(height: 8),
          _buildProgressBar('Fats', macros['fatsPercent'] ?? 0, PdfColors.yellow),
        ],
      ),
    );
  }

  pw.Widget _buildProgressBar(String label, num percent, PdfColor color) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.Expanded(
          child: pw.Stack(
            children: [
              pw.Container(
                height: 20,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey300,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
              ),
              pw.Container(
                width: percent * 3, // Scale for visualization
                height: 20,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 40,
          child: pw.Text(
            '${percent.toStringAsFixed(1)}%',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildVitalsTable(Map<String, dynamic> vitals) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableCell('Vital Sign', isHeader: true),
            _buildTableCell('Average', isHeader: true),
            _buildTableCell('Min', isHeader: true),
            _buildTableCell('Max', isHeader: true),
            _buildTableCell('Status', isHeader: true),
          ],
        ),
        ...vitals.entries.map((entry) {
          final vital = entry.value as Map<String, dynamic>;
          return pw.TableRow(
            children: [
              _buildTableCell(entry.key),
              _buildTableCell(vital['average']?.toString() ?? 'N/A'),
              _buildTableCell(vital['min']?.toString() ?? 'N/A'),
              _buildTableCell(vital['max']?.toString() ?? 'N/A'),
              _buildTableCell(vital['status'] ?? 'N/A'),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildRecentActivity(List activities) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Recent Activities',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        ...activities.take(5).map((activity) {
          final a = activity as Map<String, dynamic>;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 8,
                  height: 8,
                  margin: const pw.EdgeInsets.only(right: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.teal,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    '${a['type']}: ${a['description']}',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
                pw.Text(
                  _formatDate(a['timestamp']),
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildQuickStats(Map<String, dynamic> summary) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _buildQuickStat('Health Score', summary['overallHealthScore'] ?? 'N/A', PdfColors.teal),
        _buildQuickStat('Symptoms', (summary['symptomPatterns'] as List? ?? []).length.toString(), PdfColors.orange),
        _buildQuickStat('Alerts', (summary['criticalAlerts'] as List? ?? []).length.toString(), PdfColors.red),
      ],
    );
  }

  pw.Widget _buildQuickStat(String label, String value, PdfColor color) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: color),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAlertBox(List alerts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        border: pw.Border.all(color: PdfColors.red, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '⚠️ ${alerts.length} Critical Alert(s)',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.SizedBox(height: 8),
          ...alerts.take(3).map((alert) {
            final a = alert as Map<String, dynamic>;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '• ${a['message'] ?? 'Alert'}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  pw.Widget _buildTopSymptoms(List symptoms) {
    if (symptoms.isEmpty) return pw.SizedBox();
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Top Symptoms',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        ...symptoms.take(5).map((symptom) {
          final s = symptom as Map<String, dynamic>;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    s['symptomName'] ?? 'N/A',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
                pw.Text(
                  '${s['frequency']}x',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildInfoSection(String title, List<List<String>> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal,
          ),
        ),
        pw.SizedBox(height: 10),
        ...items.map((item) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 140,
                  child: pw.Text(
                    item[0],
                    style: const pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    item[1],
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildHealthContextSection(dynamic healthSnapshot) {
    try {
      final Map<String, dynamic> summary = healthSnapshot is String
          ? Map<String, dynamic>.from(healthSnapshot as Map)
          : healthSnapshot;

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Health Context at Time of Appointment',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildContextRow('Critical Alerts', (summary['criticalAlerts'] as List? ?? []).length.toString()),
                _buildContextRow('Symptoms Reported', (summary['symptomPatterns'] as List? ?? []).length.toString()),
                _buildContextRow('Health Score', summary['overallHealthScore'] ?? 'N/A'),
              ],
            ),
          ),
        ],
      );
    } catch (e) {
      return pw.SizedBox();
    }
  }

  pw.Widget _buildContextRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ========== HELPER METHODS ==========

  Future<Map<String, dynamic>> _fetchUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('profiles').doc(userId).get();
      return doc.data() ?? {};
    } catch (e) {
      return {};
    }
  }

  String _formatDate(dynamic date) {
    try {
      if (date == null) return 'N/A';
      
      DateTime dateTime;
      if (date is Timestamp) {
        dateTime = date.toDate();
      } else if (date is String) {
        dateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        dateTime = date;
      } else {
        return 'N/A';
      }
      
      return DateFormat('dd MMM yyyy').format(dateTime);
    } catch (e) {
      return 'N/A';
    }
  }

  Future<File> _savePdf(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Print/Share PDF
  Future<void> printPdf(File pdfFile) async {
    await Printing.layoutPdf(
      onLayout: (format) => pdfFile.readAsBytes(),
    );
  }

  /// Share PDF
  Future<void> sharePdf(File pdfFile) async {
    await Printing.sharePdf(
      bytes: await pdfFile.readAsBytes(),
      filename: pdfFile.path.split('/').last,
    );
  }
}