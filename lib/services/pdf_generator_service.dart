import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import '../models/enhanced_health_summary.dart';
import '../models/data_sharing_permission.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// import 'dart:html' as html;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';


class PdfGeneratorService {
  static final PdfGeneratorService instance = PdfGeneratorService._init();
  
  PdfGeneratorService._init();

  Future<String> generateHealthSummaryPdf({
    required EnhancedHealthSummary summary,
    required Map<String, bool> selectedCategories,
    required String userName,
  }) async {
    print('📄 Starting PDF generation...');
    print('🔍 DEBUG - Summary data check');
    print('   Health Score: ${summary.summaryData.healthScore}');
    print('   Symptoms: ${summary.summaryData.symptomAnalysis.totalSymptoms}');
    print('   Calories: ${summary.summaryData.nutritionInsights.averageCalories}');
    print('   Workout Days: ${summary.summaryData.activityWellness.totalWorkoutDays}');
    
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(userName, summary),
          pw.SizedBox(height: 20),
          
          if (selectedCategories[DataSharingPermission.HEALTH_SCORES] ?? false)
            ..._buildHealthScore(summary),
          
          if (selectedCategories[DataSharingPermission.BASIC_INFO] ?? false)
            ..._buildPatientOverview(summary.summaryData.patientOverview),
          
          if (selectedCategories[DataSharingPermission.SYMPTOM_HISTORY] ?? false)
            ..._buildSymptomAnalysis(summary.summaryData.symptomAnalysis),
          
          if (selectedCategories[DataSharingPermission.NUTRITION_LOGS] ?? false)
            ..._buildNutritionInsights(summary.summaryData.nutritionInsights),
          
          if (selectedCategories[DataSharingPermission.ACTIVITY_DATA] ?? false)
            ..._buildActivityWellness(summary.summaryData.activityWellness),
          
          if (summary.summaryData.medicationAdherence != null)
            ..._buildMedicationAdherence(summary.summaryData.medicationAdherence!),
          
          pw.SizedBox(height: 30),
          _buildFooter(summary),
        ],
      ),
    );

    if (kIsWeb) {
      return await _saveAndDownloadPdfWeb(pdf, userName);
    } else {
      return await _saveAndDownloadPdfMobile(pdf, userName);
    }
  }

  // Future<String> _saveAndDownloadPdfWeb(pw.Document pdf, String userName) async {
  //   try {
  //     final bytes = await pdf.save();
  //     final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  //     final fileName = 'Health_Summary_${userName.replaceAll(' ', '_')}_$timestamp.pdf';
      
  //     final blob = html.Blob([bytes], 'application/pdf');
  //     final url = html.Url.createObjectUrlFromBlob(blob);
  //     final anchor = html.AnchorElement(href: url)
  //       ..setAttribute('download', fileName)
  //       ..click();
      
  //     html.Url.revokeObjectUrl(url);
      
  //     print('✅ PDF downloaded: $fileName');
  //     return fileName;
  //   } catch (e) {
  //     print('❌ Error generating PDF for web: $e');
  //     rethrow;
  //   }
  // }

  Future<String> _saveAndDownloadPdfWeb(pw.Document pdf, String userName) async {
  try {
    final bytes = Uint8List.fromList(await pdf.save());
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Health_Summary_${userName.replaceAll(' ', '_')}_$timestamp';

    await FileSaver.instance.saveFile(
      name: fileName,
      ext: "pdf",
     mimeType: MimeType.other,
      bytes: bytes,
    );

    print('✅ PDF saved on web: $fileName.pdf');
    return "$fileName.pdf";

  } catch (e) {
    print('❌ Error generating PDF for web: $e');
    rethrow;
  }
}


  Future<String> _saveAndDownloadPdfMobile(pw.Document pdf, String userName) async {
    try {
      final output = await _getOutputFile(userName);
      final file = File(output);
      await file.writeAsBytes(await pdf.save());
      
      print('✅ PDF saved to: $output');
      return output;
    } catch (e) {
      print('❌ Error generating PDF for mobile: $e');
      rethrow;
    }
  }

  // ✅ FIXED HEADER - Dark teal background for Report Period box
  pw.Widget _buildHeader(String userName, EnhancedHealthSummary summary) {
    final startDate = DateFormat('MMM dd, yyyy').format(summary.periodStart);
    final endDate = DateFormat('MMM dd, yyyy').format(summary.periodEnd);
    final generatedDate = DateFormat('MMM dd, yyyy').format(summary.generatedAt);
    
    print('🔍 DEBUG - Header dates: $startDate to $endDate');
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Health Summary Report',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    userName,
                    style: pw.TextStyle(
                      fontSize: 18,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Generated:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    generatedDate,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          // ✅ FIXED: Dark background for visibility
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal700, // Dark teal background
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(
                color: PdfColors.teal900,
                width: 1,
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Report Period:',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  '$startDate - $endDate',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildHealthScore(EnhancedHealthSummary summary) {
    final score = summary.summaryData.healthScore;
    PdfColor scoreColor;
    String scoreLabel;
    
    if (score >= 80) {
      scoreColor = PdfColors.green;
      scoreLabel = 'Excellent';
    } else if (score >= 60) {
      scoreColor = PdfColors.blue;
      scoreLabel = 'Good';
    } else if (score >= 40) {
      scoreColor = PdfColors.orange;
      scoreLabel = 'Fair';
    } else {
      scoreColor = PdfColors.red;
      scoreLabel = 'Needs Attention';
    }
    
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Overall Health Score'),
      pw.Container(
        padding: const pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.Container(
                  width: 100,
                  height: 100,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: scoreColor,
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      '${score.toInt()}',
                      style: pw.TextStyle(
                        fontSize: 36,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  scoreLabel,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildScoreLegend('80-100', 'Excellent', PdfColors.green),
                _buildScoreLegend('60-79', 'Good', PdfColors.blue),
                _buildScoreLegend('40-59', 'Fair', PdfColors.orange),
                _buildScoreLegend('0-39', 'Needs Attention', PdfColors.red),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  pw.Widget _buildScoreLegend(String range, String label, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Container(
            width: 12,
            height: 12,
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            '$range - $label',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildPatientOverview(PatientOverview overview) {
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Patient Information'),
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard('Age', '${overview.age} years'),
                _buildInfoCard('Gender', overview.gender),
                if (overview.bloodGroup != null)
                  _buildInfoCard('Blood Group', overview.bloodGroup!),
                if (overview.bmi != null)
                  _buildInfoCard('BMI', '${overview.bmi!.toStringAsFixed(1)} (${overview.bmiCategory ?? 'N/A'})'),
              ],
            ),
            if (overview.allergies != null || overview.chronicConditions != null) ...[
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 12),
            ],
            if (overview.allergies != null && overview.allergies!.isNotEmpty)
              _buildInfoRow('Allergies', overview.allergies!),
            if (overview.chronicConditions != null && overview.chronicConditions!.isNotEmpty)
              _buildInfoRow('Chronic Conditions', overview.chronicConditions!),
            if (overview.currentMedications != null && overview.currentMedications!.isNotEmpty)
              _buildInfoRow('Current Medications', overview.currentMedications!),
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildSymptomAnalysis(SymptomAnalysis analysis) {
    print('🔍 DEBUG - Symptoms: ${analysis.totalSymptoms}, Trend: ${analysis.severityTrend}');
    
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Symptom Analysis'),
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Total Symptoms', '${analysis.totalSymptoms}', PdfColors.blue),
                _buildStatCard('Trend', analysis.severityTrend, 
                    analysis.severityTrend == 'Improving' ? PdfColors.green : 
                    analysis.severityTrend == 'Worsening' ? PdfColors.red : PdfColors.orange),
              ],
            ),
            
            if (analysis.topSymptoms.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Most Frequent Symptoms:',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              ...analysis.topSymptoms.take(5).map((symptom) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('- ${symptom.symptomName}', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(
                      'Frequency: ${symptom.frequency} | Severity: ${symptom.averageSeverity}',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              )),
            ],
            
            if (analysis.redFlags.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.red200),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'WARNING: Red Flags',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    ...analysis.redFlags.map((flag) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text('- $flag', style: const pw.TextStyle(fontSize: 10)),
                    )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildNutritionInsights(NutritionInsights insights) {
    print('🔍 DEBUG - Nutrition: ${insights.averageCalories}, ${insights.averageHydration}ml, ${insights.dietaryPattern}');
    
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Nutrition Insights'),
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Avg. Calories', '${insights.averageCalories.toInt()}', PdfColors.orange),
                _buildStatCard('Hydration', '${insights.averageHydration.toInt()}ml', PdfColors.blue),
                _buildStatCard('Pattern', insights.dietaryPattern, PdfColors.green),
              ],
            ),
            
            pw.SizedBox(height: 16),
            pw.Text(
              'Macronutrient Distribution:',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                _buildMacroBar('Carbs', insights.macroDistribution['carbs'] ?? 0, PdfColors.orange),
                pw.SizedBox(width: 10),
                _buildMacroBar('Protein', insights.macroDistribution['protein'] ?? 0, PdfColors.blue),
                pw.SizedBox(width: 10),
                _buildMacroBar('Fat', insights.macroDistribution['fat'] ?? 0, PdfColors.purple),
              ],
            ),
            
            if (insights.concerns.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Recommendations:',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    ...insights.concerns.map((concern) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text('- $concern', style: const pw.TextStyle(fontSize: 10)),
                    )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildActivityWellness(ActivityWellness wellness) {
    print('🔍 DEBUG - Activity: ${wellness.totalWorkoutDays} days, ${wellness.averageWorkoutMinutes}min, ${wellness.weightTrend}');
    
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Activity & Wellness'),
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Workout Days', '${wellness.totalWorkoutDays}', PdfColors.green),
                _buildStatCard('Avg. Duration', '${wellness.averageWorkoutMinutes.toInt()} min', PdfColors.blue),
                _buildStatCard('Weight Trend', wellness.weightTrend, PdfColors.orange),
              ],
            ),
            
            if (wellness.averageMood != null) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Average Mood: ',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      wellness.averageMood!,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
            
            if (wellness.weightChange != null) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'Weight Change: ${wellness.weightChange! >= 0 ? '+' : ''}${wellness.weightChange!.toStringAsFixed(1)} kg',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildMedicationAdherence(MedicationAdherence adherence) {
    return [
      pw.SizedBox(height: 20),
      _buildSectionTitle('Medication Adherence'),
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Total Doses', '${adherence.totalDoses}', PdfColors.blue),
                _buildStatCard('Missed Doses', '${adherence.missedDoses}', PdfColors.red),
                _buildStatCard('Adherence Rate', '${adherence.adherenceRate.toStringAsFixed(1)}%', 
                    adherence.adherenceRate >= 80 ? PdfColors.green : PdfColors.orange),
              ],
            ),
            
            if (adherence.medications.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'Current Medications:',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              ...adherence.medications.map((med) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text('- $med', style: const pw.TextStyle(fontSize: 10)),
              )),
            ],
          ],
        ),
      ),
    ];
  }

  pw.Widget _buildFooter(EnhancedHealthSummary summary) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(
            'Report ID: ${summary.id}',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated on ${DateFormat('MMM dd, yyyy \'at\' HH:mm').format(summary.generatedAt)}',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'WARNING: This report is for informational purposes only and should not replace professional medical advice.',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildInfoCard(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
  
  PdfColor pdfWithOpacity(PdfColor c, double opacity) {
    final a = opacity.clamp(0.0, 1.0);
    return PdfColor(c.red, c.green, c.blue, a);
  }

  // ✅ COMPLETELY FIXED STAT CARD - White background with colored border
  pw.Widget _buildStatCard(String label, String value, PdfColor color) {
    print('🔍 DEBUG - StatCard: label="$label", value="$value"');
    
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white, // White background for maximum contrast
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(
          color: color, // Solid colored border
          width: 2,
        ),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          // VALUE on top - Large, bold, colored
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: color, // Solid color will show clearly on white
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 6),
          // LABEL on bottom - Smaller, dark text
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey800,
              fontWeight: pw.FontWeight.normal,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMacroBar(String label, double percentage, PdfColor color) {
    return pw.Expanded(
      child: pw.Column(
        children: [
          pw.Container(
            height: 100,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Align(
              alignment: pw.Alignment.bottomCenter,
              child: pw.Container(
                height: percentage,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            '${percentage.toStringAsFixed(1)}%',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getOutputFile(String userName) async {
    Directory? directory;
    
    try {
      directory = await getExternalStorageDirectory();
    } catch (e) {
      print('⚠️ External storage not available, using app directory');
      directory = await getApplicationDocumentsDirectory();
    }
    
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Health_Summary_${userName.replaceAll(' ', '_')}_$timestamp.pdf';
    
    final filePath = '${directory!.path}/$fileName';
    
     print('📁 Saving PDF to: $filePath');
    return filePath;
  }

  Future<void> openPdf(String filePath) async {
    if (kIsWeb) {
      print('ℹ️ PDF auto-downloaded on web');
      return;
    }
    
    try {
      final result = await OpenFile.open(filePath);
      print('📄 Open PDF result: ${result.message}');
    } catch (e) {
      print('❌ Error opening PDF: $e');
    }
  }
}