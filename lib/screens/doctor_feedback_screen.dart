import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/consultation_feedback_service.dart';

class DoctorFeedbackScreen extends StatefulWidget {
  const DoctorFeedbackScreen({super.key});

  @override
  State<DoctorFeedbackScreen> createState() => _DoctorFeedbackScreenState();
}

class _DoctorFeedbackScreenState extends State<DoctorFeedbackScreen> {
  final _feedbackService = ConsultationFeedbackService.instance;
  final _user = FirebaseAuth.instance.currentUser;

  List<Map<String, dynamic>> _feedback = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _selectedFilter; // 'all', 'compliment', 'complaint', 'suggestion'

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    if (_user == null) return;

    setState(() => _isLoading = true);

    try {
      // Get doctor's doctorId from profile
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('Doctor profile not found');
      }

      final doctorId = userDoc.data()!['doctorId'] as String?;
      if (doctorId == null) {
        throw Exception('Doctor ID not found');
      }

      // Load feedback and stats
      final feedback = await _feedbackService.getDoctorFeedback(doctorId);
      final stats = await _feedbackService.getDoctorFeedbackStats(doctorId);

      setState(() {
        _feedback = feedback;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading feedback: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredFeedback {
    if (_selectedFilter == null || _selectedFilter == 'all') {
      return _feedback;
    }
    return _feedback
        .where((f) => f['feedbackType'] == _selectedFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Feedback'),
        backgroundColor: Colors.teal.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFeedback,
          ),
          PopupMenuButton<String>(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
                if (_selectedFilter != null && _selectedFilter != 'all')
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
            onSelected: (value) {
              setState(() => _selectedFilter = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.list, size: 20),
                    SizedBox(width: 8),
                    Text('All Feedback'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: ConsultationFeedbackService.typeCompliment,
                child: Row(
                  children: [
                    Icon(Icons.thumb_up, size: 20, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text('Compliments'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ConsultationFeedbackService.typeComplaint,
                child: Row(
                  children: [
                    Icon(Icons.report_problem, size: 20, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Complaints'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ConsultationFeedbackService.typeSuggestion,
                child: Row(
                  children: [
                    Icon(Icons.lightbulb, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text('Suggestions'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _feedback.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildStatsOverview(),
                    if (_selectedFilter != null && _selectedFilter != 'all')
                      _buildFilterChip(),
                    Expanded(
                      child: _buildFeedbackList(),
                    ),
                  ],
                ),
    );
  }

Widget _buildStatsOverview() {
  if (_stats == null) return const SizedBox.shrink();

  final avgRating = _stats!['averageRating'] as double;
  final total = _stats!['totalFeedback'] as int;
  final ratingDist = _stats!['ratingDistribution'] as Map<int, int>;

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    decoration: BoxDecoration(
      color: Colors.teal.shade700,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
    ),
    child: Column(
      children: [
        // TOP ROW: Rating + Star Bars side-by-side
        Row(
          children: [
            // Left Side: Big Rating
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Text(
                    avgRating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Icon(Icons.star, color: Colors.amber, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    '$total reviews',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            
            // Middle: Small divider
            Container(height: 80, width: 1, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 12)),

            // Right Side: The Star Visualization Bars (Compact version)
            Expanded(
              flex: 3,
              child: Column(
                children: List.generate(5, (index) {
                  final stars = 5 - index;
                  final count = ratingDist[stars] ?? 0;
                  final percentage = total > 0 ? (count / total) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Text('$stars', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation(Colors.amber),
                              minHeight: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),

        // BOTTOM ROW: Feedback Type Breakdown (Original style, just smaller)
        Row(
          children: [
            Expanded(child: _buildTypeCard('👍', _stats!['compliments'], 'Compliments', Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _buildTypeCard('⚠️', _stats!['complaints'], 'Complaints', Colors.red)),
            const SizedBox(width: 8),
            Expanded(child: _buildTypeCard('💡', _stats!['suggestions'], 'Suggestions', Colors.orange)),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildTypeCard(String emoji, int count, String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              count.toString(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white60),
        ),
      ],
    ),
  );
}

  Widget _buildFilterChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.teal.shade50,
      child: Row(
        children: [
          Chip(
            avatar: Icon(
              _getTypeIcon(_selectedFilter!),
              size: 16,
              color: _getTypeColor(_selectedFilter!),
            ),
            label: Text(_selectedFilter!.toUpperCase()),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => setState(() => _selectedFilter = 'all'),
            backgroundColor: _getTypeColor(_selectedFilter!).withOpacity(0.1),
            side: BorderSide(
              color: _getTypeColor(_selectedFilter!).withOpacity(0.3),
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredFeedback.length} result${_filteredFeedback.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackList() {
    final filtered = _filteredFeedback;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildFeedbackCard(filtered[index]),
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> feedback) {
    final rating = feedback['rating'] as int;
    final type = feedback['feedbackType'] as String;
    final comments = feedback['comments'] as String;
    final patientName = feedback['patientName'] as String;
    final isAnonymous = feedback['isAnonymous'] as bool? ?? false;
    final createdAt = feedback['createdAt'] as String?;

    final typeColor = _getTypeColor(type);
    final typeIcon = _getTypeIcon(type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: typeColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isAnonymous ? Icons.privacy_tip : Icons.person,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            patientName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Type Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: typeColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(typeIcon, size: 14, color: typeColor),
                  const SizedBox(width: 6),
                  Text(
                    type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Comments
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                comments,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),

            // Admin note if exists
            if (feedback['adminNotes'] != null &&
                feedback['adminNotes'].toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.admin_panel_settings,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin Note',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            feedback['adminNotes'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.feedback_outlined,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No Feedback Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Patient feedback will appear here once\nadmin reviews and shares them with you',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case ConsultationFeedbackService.typeCompliment:
        return Colors.green;
      case ConsultationFeedbackService.typeComplaint:
        return Colors.red;
      case ConsultationFeedbackService.typeSuggestion:
        return Colors.orange;
      default:
        return Colors.grey;
    }
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

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('MMM dd, yyyy h:mm a').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }
}