import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/enhanced_health_summary_service.dart';
import '../services/pdf_generator_service.dart';
import '../models/data_sharing_permission.dart';

/// Health Summary Download Dialog
/// 
/// Allows patients to select data categories and generate a PDF health summary report
class HealthSummaryDownloadDialog extends StatefulWidget {
  final String userId;
  final String userName;

  const HealthSummaryDownloadDialog({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<HealthSummaryDownloadDialog> createState() => _HealthSummaryDownloadDialogState();
}

class _HealthSummaryDownloadDialogState extends State<HealthSummaryDownloadDialog> {
  final HealthSummaryService _summaryService = HealthSummaryService.instance;
  final PdfGeneratorService _pdfService = PdfGeneratorService.instance;

  // Selected data categories
  final Map<String, bool> _selectedCategories = {
    DataSharingPermission.BASIC_INFO: true, // Always selected by default
    DataSharingPermission.SYMPTOM_HISTORY: true,
    DataSharingPermission.NUTRITION_LOGS: true,
    DataSharingPermission.ACTIVITY_DATA: true,
    DataSharingPermission.HEALTH_SCORES: true,
    DataSharingPermission.MEDICAL_HISTORY: false,
    DataSharingPermission.LAB_REPORTS: false,
  };

  // Time period selection
  int _selectedPeriodDays = 30;
  final List<int> _periodOptions = [7, 14, 30, 60, 90];

  bool _isGenerating = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),
            
            const Divider(height: 1),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period selection
                    _buildPeriodSelection(),
                    
                    const SizedBox(height: 24),
                    
                    // Data categories selection
                    _buildCategoriesSelection(),
                    
                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorMessage(),
                    ],
                  ],
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // Actions
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// Build header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade400, Colors.purple.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.file_download, color: Colors.teal.shade700, size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download Health Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Generate a comprehensive PDF report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Build period selection
  Widget _buildPeriodSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_month, color: Colors.teal.shade700, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Select Time Period',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _periodOptions.map((days) {
            final isSelected = _selectedPeriodDays == days;
            return InkWell(
              onTap: () => setState(() => _selectedPeriodDays = days),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.teal.shade700 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.teal.shade700 : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  days == 7
                      ? 'Last Week'
                      : days == 14
                          ? 'Last 2 Weeks'
                          : days == 30
                              ? 'Last Month'
                              : days == 60
                                  ? 'Last 2 Months'
                                  : 'Last 3 Months',
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Report will include data from ${DateFormat('MMM dd, yyyy').format(DateTime.now().subtract(Duration(days: _selectedPeriodDays)))} to ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build categories selection
  Widget _buildCategoriesSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist, color: Colors.teal.shade700, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Select Data to Include',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose which information to include in your report',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        
        // Category checkboxes
        ..._selectedCategories.keys.map((category) {
          final isBasicInfo = category == DataSharingPermission.BASIC_INFO;
          return _buildCategoryCheckbox(
            category: category,
            isEnabled: !isBasicInfo, // Basic info always selected
          );
        }).toList(),
        
        const SizedBox(height: 12),
        
        // Select/Deselect all buttons
        Row(
          children: [
            TextButton.icon(
              onPressed: _selectAll,
              icon: const Icon(Icons.check_box, size: 18),
              label: const Text('Select All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.teal.shade700,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _deselectAll,
              icon: const Icon(Icons.check_box_outline_blank, size: 18),
              label: const Text('Deselect All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build category checkbox
  Widget _buildCategoryCheckbox({
    required String category,
    required bool isEnabled,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _selectedCategories[category]! 
            ? Colors.teal.shade50 
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedCategories[category]!
              ? Colors.teal.shade300
              : Colors.grey.shade300,
        ),
      ),
      child: CheckboxListTile(
        value: _selectedCategories[category],
        onChanged: isEnabled
            ? (value) {
                setState(() {
                  _selectedCategories[category] = value ?? false;
                });
              }
            : null,
        title: Row(
          children: [
            Text(
              DataSharingPermission.getCategoryIcon(category),
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                DataSharingPermission.getCategoryLabel(category),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: _selectedCategories[category]!
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
        subtitle: isEnabled
            ? null
            : const Text(
                'Always included',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
        activeColor: Colors.teal.shade700,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  /// Build error message
  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build actions
  Widget _buildActions() {
    final selectedCount = _selectedCategories.values.where((v) => v).length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected categories count
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  '$selectedCount categories selected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Generate PDF button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generatePdf,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download, size: 24),
              label: Text(
                _isGenerating ? 'Generating PDF...' : 'Generate & Download PDF',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Cancel button
          TextButton(
            onPressed: _isGenerating ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Select all categories
  void _selectAll() {
    setState(() {
      for (var key in _selectedCategories.keys) {
        _selectedCategories[key] = true;
      }
      _errorMessage = null;
    });
  }

  /// Deselect all categories (except basic info)
  void _deselectAll() {
    setState(() {
      for (var key in _selectedCategories.keys) {
        if (key != DataSharingPermission.BASIC_INFO) {
          _selectedCategories[key] = false;
        }
      }
      _errorMessage = null;
    });
  }

  /// Generate and download PDF
  Future<void> _generatePdf() async {
    // Validate selection
    final selectedCount = _selectedCategories.values.where((v) => v).length;
    if (selectedCount == 0) {
      setState(() {
        _errorMessage = 'Please select at least one category';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      print('📄 Generating health summary...');
      
      // Step 1: Generate health summary
      final summary = await _summaryService.generateHealthSummary(
        userId: widget.userId,
        periodDays: _selectedPeriodDays,
      );
      
      print('✅ Health summary generated: ${summary.id}');
      
      // Step 2: Generate PDF
      print('📄 Creating PDF document...');
      final pdfFilePath = await _pdfService.generateHealthSummaryPdf(
        summary: summary,
        selectedCategories: _selectedCategories,
        userName: widget.userName,
      );
      
      print('✅ PDF generated successfully: $pdfFilePath');
      
      if (mounted) {
        Navigator.pop(context);
        
        // Show success dialog
        _showSuccessDialog(pdfFilePath);
      }
    } catch (e) {
      print('❌ Error generating PDF: $e');
      setState(() {
        _errorMessage = 'Failed to generate PDF: ${e.toString()}';
        _isGenerating = false;
      });
    }
  }

  /// Show success dialog
  void _showSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'PDF Generated!',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✅ Your health summary has been generated successfully!',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'File Location',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    filePath,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '📱 The PDF has been saved to your device\'s Downloads folder.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _pdfService.openPdf(filePath);
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show the dialog
Future<void> showHealthSummaryDownloadDialog({
  required BuildContext context,
  required String userId,
  required String userName,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => HealthSummaryDownloadDialog(
      userId: userId,
      userName: userName,
    ),
  );
}