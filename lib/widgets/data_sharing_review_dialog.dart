import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/data_sharing_service.dart';
import '../models/data_sharing_permission.dart';

/// Data Sharing Review Dialog
/// 
/// Shown to patients after doctor approves their appointment
/// Allows patients to select which health data categories to share
class DataSharingReviewDialog extends StatefulWidget {
  final String appointmentId;
  final String patientId;
  final String doctorName;
  final String appointmentDate;
  final VoidCallback? onComplete;

  const DataSharingReviewDialog({
    super.key,
    required this.appointmentId,
    required this.patientId,
    required this.doctorName,
    required this.appointmentDate,
    this.onComplete,
  });

  @override
  State<DataSharingReviewDialog> createState() => _DataSharingReviewDialogState();
}

class _DataSharingReviewDialogState extends State<DataSharingReviewDialog> {
  final DataSharingService _dataSharingService = DataSharingService.instance;
  
  // Permission checkboxes state
  final Map<String, bool> _permissions = DataSharingPermission.createDefaultPermissions();
  
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;
  bool _selectAll = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      _permissions.updateAll((key, _) => _selectAll);
    });
  }

  void _togglePermission(String category, bool? value) {
    setState(() {
      _permissions[category] = value ?? false;
      // Update select all state
      _selectAll = _permissions.values.every((v) => v == true);
    });
  }

  Future<void> _approveSharing() async {
    // Check if at least one permission is selected
    if (!_permissions.values.any((v) => v == true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select at least one data category to share'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _dataSharingService.approveDataSharing(
        appointmentId: widget.appointmentId,
        patientId: widget.patientId,
        permissions: _permissions,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate approval
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Data sharing approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectSharing() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Data Sharing?'),
        content: const Text(
          'Are you sure you want to reject data sharing? The doctor will have limited access to your health information during the consultation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _dataSharingService.rejectDataSharing(
        appointmentId: widget.appointmentId,
        patientId: widget.patientId,
        notes: 'Patient declined data sharing',
      );

      if (mounted) {
        Navigator.of(context).pop(false); // Return false to indicate rejection
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data sharing rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        widget.onComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _permissions.values.where((v) => v == true).length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade500],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [  // ✅ FIXED: Changed from </Widget>[ to children: [
                  const Icon(
                    Icons.privacy_tip_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Review Data Sharing',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Appointment with ${widget.doctorName}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    widget.appointmentDate,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Explanation
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Select the health data you want to share with your doctor for this appointment.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),

                    // Select All
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CheckboxListTile(
                        value: _selectAll,
                        onChanged: _toggleSelectAll,
                        title: const Text(
                          'Select All Categories',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          '$selectedCount of ${_permissions.length} selected',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        activeColor: Colors.blue.shade700,
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Data Categories',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Permission Checkboxes
                    ..._permissions.keys.map((category) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _permissions[category]! 
                                ? Colors.blue.shade300 
                                : Colors.grey.shade300,
                            width: _permissions[category]! ? 2 : 1,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: _permissions[category],
                          onChanged: (value) => _togglePermission(category, value),
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          activeColor: Colors.blue.shade700,
                          dense: true,
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),

                    // Optional Notes
                    const Text(
                      'Additional Notes (Optional)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Any specific concerns or instructions...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Approve Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _approveSharing,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Approve & Share Selected Data',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Reject Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _rejectSharing,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cancel, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Reject Data Sharing',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Cancel Button
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Decide Later',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show the dialog
Future<bool?> showDataSharingReviewDialog({
  required BuildContext context,
  required String appointmentId,
  required String patientId,
  required String doctorName,
  required String appointmentDate,
  VoidCallback? onComplete,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DataSharingReviewDialog(
      appointmentId: appointmentId,
      patientId: patientId,
      doctorName: doctorName,
      appointmentDate: appointmentDate,
      onComplete: onComplete,
    ),
  );
}