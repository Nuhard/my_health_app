import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/consultation_feedback_service.dart';

/// Show detailed feedback review dialog for admin
Future<void> showFeedbackReviewDialog({
  required BuildContext context,
  required Map<String, dynamic> feedback,
  required String adminId,
  required VoidCallback onActionComplete,
}) async {
  await showDialog(
    context: context,
    builder: (context) => _FeedbackReviewDialog(
      feedback: feedback,
      adminId: adminId,
      onActionComplete: onActionComplete,
    ),
  );
}

class _FeedbackReviewDialog extends StatefulWidget {
  final Map<String, dynamic> feedback;
  final String adminId;
  final VoidCallback onActionComplete;

  const _FeedbackReviewDialog({
    required this.feedback,
    required this.adminId,
    required this.onActionComplete,
  });

  @override
  State<_FeedbackReviewDialog> createState() => _FeedbackReviewDialogState();
}

class _FeedbackReviewDialogState extends State<_FeedbackReviewDialog> {
  final _feedbackService = ConsultationFeedbackService.instance;
  final _adminNotesController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  
  bool _shareWithDoctor = true;
  bool _isProcessing = false;
  
  // Additional context data
  Map<String, dynamic>? _appointmentDetails;
  Map<String, dynamic>? _doctorStats;
  bool _isLoadingContext = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill admin notes if they exist
    if (widget.feedback['adminNotes'] != null) {
      _adminNotesController.text = widget.feedback['adminNotes'];
    }
    _loadAdditionalContext();
  }

  @override
  void dispose() {
    _adminNotesController.dispose();
    super.dispose();
  }

  /// Load appointment details and doctor stats
  Future<void> _loadAdditionalContext() async {
    try {
      final appointmentId = widget.feedback['appointmentId'];
      final doctorId = widget.feedback['doctorId'];

      // Fetch appointment details
      if (appointmentId != null) {
        final appointmentDoc = await _firestore
            .collection('appointments')
            .doc(appointmentId)
            .get();
        
        if (appointmentDoc.exists) {
          _appointmentDetails = appointmentDoc.data();
        }
      }

      // Fetch doctor stats
      if (doctorId != null) {
        _doctorStats = await _feedbackService.getDoctorFeedbackStats(doctorId);
      }

      setState(() => _isLoadingContext = false);
    } catch (e) {
      print('⚠️ Error loading additional context: $e');
      setState(() => _isLoadingContext = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedback = widget.feedback;
    final rating = feedback['rating'] as int;
    final type = feedback['feedbackType'] as String;
    final status = feedback['status'] as String;
    final isAnonymous = feedback['isAnonymous'] as bool? ?? false;
    final sharedWithDoctor = feedback['sharedWithDoctor'] as bool? ?? false;
    final isPending = status == ConsultationFeedbackService.statusPending;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getTypeIcon(type),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Feedback Review',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          type.toUpperCase(),
                          style: const TextStyle(
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
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    _buildStatusBadge(status, sharedWithDoctor),
                    
                    const SizedBox(height: 20),
                    
                    // ✅ ENHANCED: Consultation Details with Appointment Info
                    _buildConsultationDetails(feedback, isAnonymous),
                    
                    const SizedBox(height: 20),
                    
                    // Rating
                    _buildInfoSection(
                      'Rating',
                      Icons.star,
                      [
                        Row(
                          children: [
                            ...List.generate(5, (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 28,
                            )),
                            const SizedBox(width: 12),
                            Text(
                              '$rating/5',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Feedback Comments
                    _buildInfoSection(
                      'Patient\'s Feedback',
                      Icons.comment,
                      [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            feedback['comments'],
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Admin Notes Section
                    _buildInfoSection(
                      'Admin Notes',
                      Icons.admin_panel_settings,
                      [
                        TextField(
                          controller: _adminNotesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Add internal notes about this feedback...',
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.blue.shade50,
                          ),
                          enabled: !_isProcessing,
                        ),
                      ],
                    ),
                    
                    // Share with doctor option (only for pending/approved)
                    if (isPending || status == ConsultationFeedbackService.statusApproved) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.share, color: Colors.teal.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Doctor Visibility',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: _shareWithDoctor,
                              onChanged: _isProcessing ? null : (value) {
                                setState(() => _shareWithDoctor = value);
                              },
                              title: Text(
                                'Share this feedback with doctor',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                              subtitle: Text(
                                _shareWithDoctor
                                    ? 'Doctor will be able to see this feedback'
                                    : 'Feedback will remain private',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                              activeColor: Colors.teal.shade700,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // ✅ NEW: Related Appointment Details
                    if (_appointmentDetails != null) ...[
                      const SizedBox(height: 20),
                      _buildAppointmentDetailsSection(),
                    ],
                    
                    // Review history (if already reviewed)
                    if (feedback['reviewedAt'] != null) ...[
                      const SizedBox(height: 20),
                      _buildInfoSection(
                        'Review History',
                        Icons.history,
                        [
                          _buildInfoRow(
                            'Reviewed At',
                            _formatDate(feedback['reviewedAt']),
                          ),
                          if (feedback['reviewedBy'] != null)
                            _buildInfoRow(
                              'Reviewed By',
                              feedback['reviewedBy'],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action buttons
            if (isPending) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _handleReject,
                        icon: const Icon(Icons.cancel_outlined, size: 20),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _handleApprove,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle, size: 20),
                        label: Text(_isProcessing ? 'Processing...' : 'Approve Feedback'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (type == ConsultationFeedbackService.typeComplaint &&
                  status != ConsultationFeedbackService.statusResolved) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _handleResolve,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Mark as Resolved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// ✅ NEW: Enhanced consultation details with doctor stats
  Widget _buildConsultationDetails(Map<String, dynamic> feedback, bool isAnonymous) {
    final doctorName = feedback['doctorName'];
    final patientName = feedback['patientName'];
    
    return _buildInfoSection(
      'Consultation Details',
      Icons.medical_services,
      [
        // Doctor with stats
        Row(
          children: [
            Expanded(
              child: _buildInfoRow('Doctor', doctorName),
            ),
            if (_doctorStats != null && !_isLoadingContext) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${_doctorStats!['averageRating']} (${_doctorStats!['totalFeedback']} reviews)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        
        _buildInfoRow(
          'Patient',
          patientName,
          icon: isAnonymous ? Icons.privacy_tip : Icons.person,
        ),
        
        // ✅ NEW: Appointment Date vs Feedback Date
        if (_appointmentDetails != null) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _buildDateComparison(),
        ] else ...[
          _buildInfoRow('Feedback Date', _formatDate(feedback['createdAt'])),
        ],
      ],
    );
  }

  /// ✅ NEW: Date comparison widget
  Widget _buildDateComparison() {
    if (_appointmentDetails == null) return const SizedBox.shrink();
    
    final appointmentDate = (_appointmentDetails!['appointmentDate'] as Timestamp).toDate();
    final feedbackDateStr = widget.feedback['createdAt'];
    final feedbackDate = feedbackDateStr != null ? DateTime.parse(feedbackDateStr) : null;
    
    final timeGap = feedbackDate != null 
        ? feedbackDate.difference(appointmentDate)
        : null;
    
    String timeGapText = '';
    Color timeGapColor = Colors.grey;
    
    if (timeGap != null) {
      final hours = timeGap.inHours;
      final days = timeGap.inDays;
      
      if (hours < 1) {
        timeGapText = '${timeGap.inMinutes} minutes after';
        timeGapColor = Colors.orange;
      } else if (hours < 24) {
        timeGapText = '$hours hours after';
        timeGapColor = Colors.green;
      } else {
        timeGapText = '$days days after';
        timeGapColor = days > 7 ? Colors.blue : Colors.green;
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Appointment: ',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                DateFormat('MMM dd, yyyy h:mm a').format(appointmentDate),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.feedback, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Feedback: ',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(
                feedbackDate != null 
                    ? DateFormat('MMM dd, yyyy h:mm a').format(feedbackDate)
                    : 'Unknown',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (timeGapText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: timeGapColor),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: timeGapColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    timeGapText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: timeGapColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ NEW: Detailed appointment section
  Widget _buildAppointmentDetailsSection() {
    if (_appointmentDetails == null) return const SizedBox.shrink();
    
    final reason = _appointmentDetails!['reason'] ?? 'Not specified';
    final status = _appointmentDetails!['status'] ?? 'unknown';
    final timeSlot = _appointmentDetails!['timeSlot'] ?? 'Not specified';
    
    return _buildInfoSection(
      'Related Appointment',
      Icons.event,
      [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medical_services, size: 14, color: Colors.purple.shade700),
                  const SizedBox(width: 6),
                  const Text(
                    'Reason for Visit:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                reason,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Time Slot: $timeSlot',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.info, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Status: ${status.toUpperCase()}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ID: ${widget.feedback['appointmentId']}',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status, bool sharedWithDoctor) {
    Color color = _getStatusColor(status);
    IconData icon = _getStatusIcon(status);

    return Wrap(
      spacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (sharedWithDoctor)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share, color: Colors.blue, size: 16),
                const SizedBox(width: 6),
                Text(
                  'SHARED WITH DOCTOR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.deepOrange),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case ConsultationFeedbackService.typeCompliment:
        return Icons.thumb_up;
      case ConsultationFeedbackService.typeComplaint:
        return Icons.report_problem;
      case ConsultationFeedbackService.typeSuggestion:
        return Icons.lightbulb;
      default:
        return Icons.feedback;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case ConsultationFeedbackService.statusPending:
        return Colors.orange;
      case ConsultationFeedbackService.statusApproved:
        return Colors.green;
      case ConsultationFeedbackService.statusRejected:
        return Colors.red;
      case ConsultationFeedbackService.statusResolved:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case ConsultationFeedbackService.statusPending:
        return Icons.schedule;
      case ConsultationFeedbackService.statusApproved:
        return Icons.check_circle;
      case ConsultationFeedbackService.statusRejected:
        return Icons.cancel;
      case ConsultationFeedbackService.statusResolved:
        return Icons.done_all;
      default:
        return Icons.help;
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return 'Unknown';
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('MMM dd, yyyy h:mm a').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _handleApprove() async {
    setState(() => _isProcessing = true);

    try {
      await _feedbackService.approveFeedback(
        feedbackId: widget.feedback['id'],
        adminId: widget.adminId,
        shareWithDoctor: _shareWithDoctor,
        adminNotes: _adminNotesController.text.trim().isEmpty
            ? null
            : _adminNotesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _shareWithDoctor
                  ? '✅ Feedback approved and shared with doctor'
                  : '✅ Feedback approved (kept private)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      widget.onActionComplete();
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReject() async {
    setState(() => _isProcessing = true);

    try {
      await _feedbackService.rejectFeedback(
        feedbackId: widget.feedback['id'],
        adminId: widget.adminId,
        adminNotes: _adminNotesController.text.trim().isEmpty
            ? 'Rejected by admin'
            : _adminNotesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      widget.onActionComplete();
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleResolve() async {
    setState(() => _isProcessing = true);

    try {
      await _feedbackService.resolveFeedback(
        feedbackId: widget.feedback['id'],
        adminId: widget.adminId,
        resolutionNotes: _adminNotesController.text.trim().isEmpty
            ? 'Marked as resolved'
            : _adminNotesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Complaint marked as resolved'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      widget.onActionComplete();
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}