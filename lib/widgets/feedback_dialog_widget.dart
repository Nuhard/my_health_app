import 'package:flutter/material.dart';
import '../services/consultation_feedback_service.dart';

/// Show consultation feedback dialog
Future<bool?> showFeedbackDialog({
  required BuildContext context,
  required String appointmentId,
  required String patientId,
  required String doctorId,
  required String doctorName,
}) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _FeedbackDialog(
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      doctorName: doctorName,
    ),
  );
}

class _FeedbackDialog extends StatefulWidget {
  final String appointmentId;
  final String patientId;
  final String doctorId;
  final String doctorName;

  const _FeedbackDialog({
    required this.appointmentId,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
  });

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _feedbackService = ConsultationFeedbackService.instance;
  final _commentsController = TextEditingController();

  int _rating = 0;
  String? _selectedType;
  bool _isAnonymous = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    // Validation
    if (_rating == 0) {
      _showError('Please select a rating');
      return;
    }
    if (_selectedType == null) {
      _showError('Please select feedback type');
      return;
    }
    if (_commentsController.text.trim().isEmpty) {
      _showError('Please provide feedback comments');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _feedbackService.submitFeedback(
        appointmentId: widget.appointmentId,
        patientId: widget.patientId,
        doctorId: widget.doctorId,
        doctorName: widget.doctorName,
        rating: _rating,
        feedbackType: _selectedType!,
        comments: _commentsController.text.trim(),
        isAnonymous: _isAnonymous,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Feedback submitted successfully!')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('Failed to submit feedback: $e');
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            const Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          Icon(Icons.feedback, color: Colors.teal.shade700, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Consultation Feedback',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'For ${widget.doctorName}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rating
            const Text(
              'How would you rate this consultation?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starValue = index + 1;
                  return IconButton(
                    onPressed: () => setState(() => _rating = starValue),
                    icon: Icon(
                      _rating >= starValue ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                  );
                }),
              ),
            ),
            if (_rating > 0)
              Center(
                child: Text(
                  _getRatingText(_rating),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Feedback Type
            const Text(
              'What type of feedback is this?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildFeedbackTypeOption(
              ConsultationFeedbackService.typeCompliment,
              'Compliment',
              Icons.thumb_up,
              Colors.green,
              '✨ Positive experience',
            ),
            const SizedBox(height: 8),
            _buildFeedbackTypeOption(
              ConsultationFeedbackService.typeComplaint,
              'Complaint',
              Icons.report_problem,
              Colors.red,
              '❗ Issue or concern',
            ),
            const SizedBox(height: 8),
            _buildFeedbackTypeOption(
              ConsultationFeedbackService.typeSuggestion,
              'Suggestion',
              Icons.lightbulb,
              Colors.orange,
              '💡 Improvement idea',
            ),

            const SizedBox(height: 24),

            // Comments
            const Text(
              'Your feedback',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentsController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 16),

            // Anonymous option
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.privacy_tip, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Submit Anonymously',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        Text(
                          'Your name will not be shared',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isAnonymous,
                    onChanged: (value) => setState(() => _isAnonymous = value),
                    activeColor: Colors.blue.shade700,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your feedback will be reviewed by admin first',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitFeedback,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send, size: 18),
          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Feedback'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackTypeOption(
    String value,
    String label,
    IconData icon,
    Color color,
    String description,
  ) {
    final isSelected = _selectedType == value;

    return InkWell(
      onTap: () => setState(() => _selectedType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5:
        return 'Excellent! 🌟';
      case 4:
        return 'Very Good! 👍';
      case 3:
        return 'Good 👌';
      case 2:
        return 'Fair 😐';
      case 1:
        return 'Poor 😞';
      default:
        return '';
    }
  }
}