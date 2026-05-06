import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/feedback_review_dialog.dart';
import '../services/consultation_feedback_service.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen>
    with SingleTickerProviderStateMixin {
  final _feedbackService = ConsultationFeedbackService.instance;
  final _adminId = FirebaseAuth.instance.currentUser?.uid ?? '';

  late TabController _tabController;
  List<Map<String, dynamic>> _allFeedback = [];
  List<Map<String, dynamic>> _pendingFeedback = [];
  bool _isLoading = true;
  String? _selectedTypeFilter;
  String? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFeedback();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    try {
      final all = await _feedbackService.getAllFeedback();
      final pending = await _feedbackService.getPendingFeedback();
      
      setState(() {
        _allFeedback = all;
        _pendingFeedback = pending;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading feedback: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredAllFeedback {
    var filtered = _allFeedback;
    
    if (_selectedTypeFilter != null) {
      filtered = filtered.where((f) => f['feedbackType'] == _selectedTypeFilter).toList();
    }
    
    if (_selectedStatusFilter != null) {
      filtered = filtered.where((f) => f['status'] == _selectedStatusFilter).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback Management'),
        backgroundColor: Colors.deepOrange,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFeedback,
            tooltip: 'Refresh',
          ),
          
          // Filter menu (for All tab)
          if (_tabController.index == 1)
            PopupMenuButton<String>(
              icon: Stack(
                children: [
                  const Icon(Icons.filter_list),
                  if (_selectedTypeFilter != null || _selectedStatusFilter != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Filter',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    'Filter by Type',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                PopupMenuItem(
                  value: 'type_all',
                  child: const Text('All Types'),
                  onTap: () => setState(() => _selectedTypeFilter = null),
                ),
                PopupMenuItem(
                  value: 'type_compliment',
                  child: const Text('Compliments'),
                  onTap: () => setState(() => _selectedTypeFilter = ConsultationFeedbackService.typeCompliment),
                ),
                PopupMenuItem(
                  value: 'type_complaint',
                  child: const Text('Complaints'),
                  onTap: () => setState(() => _selectedTypeFilter = ConsultationFeedbackService.typeComplaint),
                ),
                PopupMenuItem(
                  value: 'type_suggestion',
                  child: const Text('Suggestions'),
                  onTap: () => setState(() => _selectedTypeFilter = ConsultationFeedbackService.typeSuggestion),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    'Filter by Status',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                PopupMenuItem(
                  value: 'status_all',
                  child: const Text('All Statuses'),
                  onTap: () => setState(() => _selectedStatusFilter = null),
                ),
                PopupMenuItem(
                  value: 'status_pending',
                  child: const Text('Pending'),
                  onTap: () => setState(() => _selectedStatusFilter = ConsultationFeedbackService.statusPending),
                ),
                PopupMenuItem(
                  value: 'status_approved',
                  child: const Text('Approved'),
                  onTap: () => setState(() => _selectedStatusFilter = ConsultationFeedbackService.statusApproved),
                ),
                PopupMenuItem(
                  value: 'status_rejected',
                  child: const Text('Rejected'),
                  onTap: () => setState(() => _selectedStatusFilter = ConsultationFeedbackService.statusRejected),
                ),
                PopupMenuItem(
                  value: 'status_resolved',
                  child: const Text('Resolved'),
                  onTap: () => setState(() => _selectedStatusFilter = ConsultationFeedbackService.statusResolved),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Badge(
                label: Text(_pendingFeedback.length.toString()),
                isLabelVisible: _pendingFeedback.isNotEmpty,
                child: const Icon(Icons.notifications_active),
              ),
              text: 'Pending Review',
            ),
            Tab(
              icon: const Icon(Icons.list),
              text: 'All Feedback',
            ),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Statistics summary
                _buildStatisticsSummary(),
                
                // Active filters display
                if (_selectedTypeFilter != null || _selectedStatusFilter != null)
                  _buildActiveFilters(),
                
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Pending tab
                      _pendingFeedback.isEmpty
                          ? _buildEmptyState('No pending feedback', Icons.check_circle_outline)
                          : _buildFeedbackList(_pendingFeedback, isPending: true),
                      
                      // All feedback tab
                      _filteredAllFeedback.isEmpty
                          ? _buildEmptyState('No feedback found', Icons.feedback_outlined)
                          : _buildFeedbackList(_filteredAllFeedback),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatisticsSummary() {
    final total = _allFeedback.length;
    final pending = _pendingFeedback.length;
    final compliments = _allFeedback.where((f) => f['feedbackType'] == ConsultationFeedbackService.typeCompliment).length;
    final complaints = _allFeedback.where((f) => f['feedbackType'] == ConsultationFeedbackService.typeComplaint).length;
    final suggestions = _allFeedback.where((f) => f['feedbackType'] == ConsultationFeedbackService.typeSuggestion).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('Total', total.toString(), Icons.feedback, Colors.white),
          _buildStatCard('Pending', pending.toString(), Icons.schedule, Colors.orange.shade100),
          _buildStatCard('👍', compliments.toString(), Icons.thumb_up, Colors.green.shade100),
          _buildStatCard('❗', complaints.toString(), Icons.report_problem, Colors.red.shade100),
          _buildStatCard('💡', suggestions.toString(), Icons.lightbulb, Colors.blue.shade100),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 16, color: Colors.deepOrange),
          const SizedBox(width: 8),
          const Text('Filters:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (_selectedTypeFilter != null)
            Chip(
              label: Text(_selectedTypeFilter!.toUpperCase(), style: const TextStyle(fontSize: 10)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => setState(() => _selectedTypeFilter = null),
              backgroundColor: Colors.deepOrange.shade100,
            ),
          const SizedBox(width: 4),
          if (_selectedStatusFilter != null)
            Chip(
              label: Text(_selectedStatusFilter!.toUpperCase(), style: const TextStyle(fontSize: 10)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => setState(() => _selectedStatusFilter = null),
              backgroundColor: Colors.deepOrange.shade100,
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedTypeFilter = null;
                _selectedStatusFilter = null;
              });
            },
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('Clear All', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackList(List<Map<String, dynamic>> feedbackList, {bool isPending = false}) {
    return RefreshIndicator(
      onRefresh: _loadFeedback,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: feedbackList.length,
        itemBuilder: (context, index) {
          final feedback = feedbackList[index];
          return _buildFeedbackCard(feedback, isPending);
        },
      ),
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> feedback, bool isPending) {
    final rating = feedback['rating'] as int;
    final type = feedback['feedbackType'] as String;
    final status = feedback['status'] as String;
    final isAnonymous = feedback['isAnonymous'] as bool? ?? false;
    final sharedWithDoctor = feedback['sharedWithDoctor'] as bool? ?? false;

    Color typeColor;
    IconData typeIcon;
    switch (type) {
      case ConsultationFeedbackService.typeCompliment:
        typeColor = Colors.green;
        typeIcon = Icons.thumb_up;
        break;
      case ConsultationFeedbackService.typeComplaint:
        typeColor = Colors.red;
        typeIcon = Icons.report_problem;
        break;
      case ConsultationFeedbackService.typeSuggestion:
        typeColor = Colors.orange;
        typeIcon = Icons.lightbulb;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.feedback;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPending
            ? BorderSide(color: Colors.orange.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showFeedbackDetailsDialog(feedback),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  
                  // Doctor and patient info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${feedback['doctorName']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              isAnonymous ? Icons.privacy_tip : Icons.person,
                              size: 12,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              feedback['patientName'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Rating stars
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 16,
                    )),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Feedback type and status badges
              Row(
                children: [
                  _buildBadge(
                    type.toUpperCase(),
                    typeColor,
                    typeIcon,
                  ),
                  const SizedBox(width: 8),
                  _buildBadge(
                    status.toUpperCase(),
                    _getStatusColor(status),
                    _getStatusIcon(status),
                  ),
                  if (sharedWithDoctor && status == ConsultationFeedbackService.statusApproved) ...[
                    const SizedBox(width: 8),
                    _buildBadge(
                      'SHARED',
                      Colors.blue,
                      Icons.share,
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Comments preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  feedback['comments'],
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Footer with date and actions
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(feedback['createdAt']),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  
                  // Quick actions for pending feedback
                  if (isPending) ...[
                    TextButton.icon(
                      onPressed: () => _quickReject(feedback['id']),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: () => _quickApprove(feedback['id']),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                  
                  // View details button
                  if (!isPending)
                    TextButton.icon(
                      onPressed: () => _showFeedbackDetailsDialog(feedback),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('Details', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.deepOrange,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
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

  // Quick approve action
  Future<void> _quickApprove(String feedbackId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick Approve'),
        content: const Text('Approve this feedback and share with doctor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve & Share'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _feedbackService.approveFeedback(
          feedbackId: feedbackId,
          adminId: _adminId,
          shareWithDoctor: true,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Feedback approved and shared with doctor'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        await _loadFeedback();
      } catch (e) {
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

  // Quick reject action
  Future<void> _quickReject(String feedbackId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick Reject'),
        content: const Text('Reject this feedback? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _feedbackService.rejectFeedback(
          feedbackId: feedbackId,
          adminId: _adminId,
          adminNotes: 'Quick rejected by admin',
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Feedback rejected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        await _loadFeedback();
      } catch (e) {
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

  // Show detailed feedback dialog (next artifact will have this)
  Future<void> _showFeedbackDetailsDialog(Map<String, dynamic> feedback) async {
    await showFeedbackReviewDialog(
      context: context,
      feedback: feedback,
      adminId: _adminId,
      onActionComplete: _loadFeedback,
    );
  }
}

