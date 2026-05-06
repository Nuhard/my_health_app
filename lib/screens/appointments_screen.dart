import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/appointment_service.dart';
import '../services/data_sharing_service.dart';
import '../widgets/data_sharing_review_dialog.dart';
import '../widgets/doctor_details_dialog.dart';
import '../services/consultation_feedback_service.dart';
import '../widgets/feedback_dialog_widget.dart';

class AppointmentsScreen extends StatefulWidget {
  final String? preFilledReason;
  final String? suggestedSpecialization;
  final String? symptomSeverity;

  const AppointmentsScreen({
    super.key,
    this.preFilledReason,
    this.suggestedSpecialization,
    this.symptomSeverity,
  });

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final User? user = FirebaseAuth.instance.currentUser;
  final AppointmentService _appointmentService = AppointmentService.instance;
  final DataSharingService _dataSharingService = DataSharingService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ✅ FIX: ValueNotifier for search — updates filter WITHOUT triggering StreamBuilder rebuild
  // This prevents the TextField from losing focus on every keystroke
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');

  late TabController _tabController;
  List<Map<String, dynamic>> _recommendations = [];
  Map<String, dynamic>? _statistics;

  bool _isGracePeriodActive = false;
  Duration? _gracePeriodRemaining;
  String? _errorMessage;

  // _searchQuery is kept in sync via ValueListenableBuilder, used by _getFilteredAppointments
  String _searchQuery = '';
  String? _selectedSpecialization;
  String? _selectedStatus;
  List<String> _specializations = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _initializeScreen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadGracePeriodAndStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _searchNotifier.dispose(); // ✅ dispose ValueNotifier
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadGracePeriodAndStats();
    if (widget.preFilledReason != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBookAppointmentDialog());
    }
  }

  Stream<List<Map<String, dynamic>>> _appointmentsStream() {
    if (user == null) return Stream.value([]);
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('userId', isEqualTo: user!.uid)
        .orderBy('appointmentDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'userId': data['userId'],
                'doctorId': data['doctorId'],
                'doctorName': data['doctorName'],
                'specialization': data['specialization'],
                'appointmentDate':
                    (data['appointmentDate'] as Timestamp).toDate().toIso8601String(),
                'timeSlot': data['timeSlot'],
                'status': data['status'],
                'reason': data['reason'] ?? '',
                'notes': data['notes'] ?? '',
                'rejectionReason': data['rejectionReason'] ?? '',
                'doctorNotes': data['doctorNotes'] ?? '',
              };
            }).toList());
  }

  void _loadSpecializationsFromAppointments(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) {
      _specializations = [];
      return;
    }
    final specs = appointments.map((apt) => apt['specialization'] as String).toSet().toList();
    specs.sort();
    _specializations = specs;
  }

  Future<void> _loadGracePeriodAndStats() async {
    if (user == null) return;
    try {
      _isGracePeriodActive = await _appointmentService.isGracePeriodActive(user!.uid);
      if (_isGracePeriodActive) {
        _recommendations = await _appointmentService.getActiveRecommendations(user!.uid);
        _gracePeriodRemaining = await _appointmentService.getGracePeriodRemaining(user!.uid);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showGracePeriodAlert();
        });
      }
    } catch (e) {
      _errorMessage = e.toString();
    }
  }

  Future<void> _showBookAppointmentDialog() async {
    try {
      List<Map<String, dynamic>> doctors = await _appointmentService.getAllDoctors();
      if (widget.suggestedSpecialization != null) {
        doctors = doctors
            .where((doc) => doc['specialization'] == widget.suggestedSpecialization)
            .toList();
      }
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _BookingDialog(
          doctors: doctors,
          preFilledReason: widget.preFilledReason,
          symptomSeverity: widget.symptomSeverity,
          suggestedSpecialization: widget.suggestedSpecialization,
          onBooked: () => Navigator.pop(context),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading doctors: $e'), backgroundColor: Colors.red));
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAppointments(List<Map<String, dynamic>> appointments) {
    var filtered = appointments;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((apt) {
        final q = _searchQuery.toLowerCase();
        return apt['doctorName'].toString().toLowerCase().contains(q) ||
            apt['specialization'].toString().toLowerCase().contains(q) ||
            apt['reason'].toString().toLowerCase().contains(q) ||
            apt['timeSlot'].toString().toLowerCase().contains(q) ||
            DateFormat('dd MMM yyyy')
                .format(DateTime.parse(apt['appointmentDate']))
                .toLowerCase()
                .contains(q);
      }).toList();
    }
    if (_selectedSpecialization != null) {
      filtered =
          filtered.where((apt) => apt['specialization'] == _selectedSpecialization).toList();
    }
    if (_selectedStatus != null) {
      filtered = filtered.where((apt) => apt['status'] == _selectedStatus).toList();
    }
    return filtered;
  }

  void _clearFilters() {
    _searchController.clear();
    _searchNotifier.value = ''; // ✅ clear notifier too
    setState(() {
      _searchQuery = '';
      _selectedSpecialization = null;
      _selectedStatus = null;
    });
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty || _selectedSpecialization != null || _selectedStatus != null;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Please login first', style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ),
      );
    }

    // ✅ KEY FIX: Scaffold lives OUTSIDE StreamBuilder.
    // The TextField (search bar) is rendered as a stable sibling of the StreamBuilder,
    // so Firestore snapshots never cause it to remount or lose focus/keyboard.
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.teal.shade400, Colors.purple.shade300],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Column(
          children: [
            // Header and search bar are OUTSIDE StreamBuilder — they never rebuild from Firestore
            _buildHeader(),
            if (_isGracePeriodActive) _buildGracePeriodBanner(),
            _buildSearchBar(), // ← stable, never remounted
            // Only this Expanded section rebuilds when Firestore data changes
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _appointmentsStream(),
                builder: (context, snapshot) {
                  // Loading state — show spinner only inside the list area
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.white));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        const Text('Error loading appointments',
                            style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 8),
                        Text(snapshot.error.toString(),
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Retry')),
                      ]),
                    );
                  }

                  final appointments = snapshot.data ?? [];

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _loadSpecializationsFromAppointments(appointments);
                  });

                  final pending =
                      appointments.where((a) => a['status'] == 'pending').length;
                  final approved =
                      appointments.where((a) => a['status'] == 'approved').length;

                  // Update stats without calling setState (avoids rebuild loop)
                  _statistics = {
                    'total': appointments.length,
                    'pending': pending,
                    'approved': approved
                  };

                  // ValueListenableBuilder reacts to search typing
                  // StreamBuilder reacts to Firestore data changes
                  // Neither causes the other to remount the TextField
                  return ValueListenableBuilder<String>(
                    valueListenable: _searchNotifier,
                    builder: (context, searchQuery, _) {
                      _searchQuery = searchQuery;
                      final filteredAppointments =
                          _getFilteredAppointments(appointments);
                      return Column(
                        children: [
                          _buildTabBar(appointments),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20)),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: _buildTabContent(
                                    appointments, filteredAppointments),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildBookButton(),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Fully custom header — back button, title, action icons all in one controlled row
  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(4, topPad + 4, 4, 14),
      child: Column(
        children: [
          // ── Top nav row ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => Navigator.maybePop(context),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
              ),
              // Title
              const Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'My Appointments',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              // Action icons — compact row
              _buildActionIcons(),
            ],
          ),
          const SizedBox(height: 12),
          // ── Stats row ────────────────────────────────────────────────────
          if (_statistics != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildStatCard('Total', _statistics!['total'], Icons.calendar_today),
                  Container(width: 1, height: 36, color: Colors.white30),
                  _buildStatCard('Pending', _statistics!['pending'], Icons.schedule),
                  Container(width: 1, height: 36, color: Colors.white30),
                  _buildStatCard('Approved', _statistics!['approved'], Icons.check_circle),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Compact action icons that fit neatly beside the title
  Widget _buildActionIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Real-time indicator
        _CompactIconBtn(
          icon: Icons.wifi,
          dot: false,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('🔄 Real-time updates active!'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green),
          ),
        ),
        // Status filter
        PopupMenuButton<String>(
          tooltip: 'Filter by status',
          onSelected: (v) => setState(() => _selectedStatus = v == 'all' ? null : v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Row(children: [Icon(Icons.clear_all, size: 18), SizedBox(width: 8), Text('All Statuses')])),
            const PopupMenuDivider(),
            PopupMenuItem(value: AppointmentService.statusPending,   child: Row(children: [Icon(Icons.schedule,     size: 18, color: Colors.orange), const SizedBox(width: 8), const Text('Pending')])),
            PopupMenuItem(value: AppointmentService.statusApproved,  child: Row(children: [Icon(Icons.check_circle, size: 18, color: Colors.green),  const SizedBox(width: 8), const Text('Approved')])),
            PopupMenuItem(value: AppointmentService.statusRejected,  child: Row(children: [Icon(Icons.cancel,       size: 18, color: Colors.red),     const SizedBox(width: 8), const Text('Rejected')])),
            PopupMenuItem(value: AppointmentService.statusCompleted, child: Row(children: [Icon(Icons.done_all,     size: 18, color: Colors.blue),    const SizedBox(width: 8), const Text('Completed')])),
            PopupMenuItem(value: AppointmentService.statusCancelled, child: Row(children: [Icon(Icons.block,        size: 18, color: Colors.grey),    const SizedBox(width: 8), const Text('Cancelled')])),
          ],
          child: _CompactIconBtn(
            icon: Icons.filter_alt,
            dot: _selectedStatus != null,
            onTap: null,
          ),
        ),
        // Specialization filter
        if (_specializations.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Filter by specialization',
            onSelected: (v) => setState(() => _selectedSpecialization = v == 'all' ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all', child: Row(children: [Icon(Icons.clear_all, size: 18), SizedBox(width: 8), Text('All Specializations')])),
              const PopupMenuDivider(),
              ..._specializations.map((s) => PopupMenuItem(
                    value: s,
                    child: Row(children: [Icon(Icons.local_hospital, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8), Expanded(child: Text(s))]),
                  )),
            ],
            child: _CompactIconBtn(
              icon: Icons.medical_services,
              dot: _selectedSpecialization != null,
              onTap: null,
            ),
          ),
        // Clear filters
        if (_hasActiveFilters)
          _CompactIconBtn(
            icon: Icons.filter_alt_off,
            dot: false,
            onTap: _clearFilters,
          ),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, IconData icon) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(height: 3),
          Text('$value',
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildGracePeriodBanner() {
    final hours = _gracePeriodRemaining?.inHours ?? 0;
    final minutes = (_gracePeriodRemaining?.inMinutes ?? 0) % 60;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.red.shade400]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.access_time, color: Colors.orange.shade700, size: 20)),
        const SizedBox(width: 10),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⏰ Grace Period Active',
              style:
                  TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(
              '${hours}h ${minutes}m remaining • ${_recommendations.length} doctors available',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ])),
        ElevatedButton(
          onPressed: _showRecommendationsSheet,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.orange.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('View', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ]),
    );
  }

  // ✅ FIX: onChanged now updates ValueNotifier only — NO setState — TextField never loses focus
  Widget _buildSearchBar() {
    return Column(children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (value) {
            // ✅ KEY FIX: Only update ValueNotifier — does NOT call setState
            // This means the TextField widget is never rebuilt, so focus is preserved
            _searchNotifier.value = value;
          },
          decoration: InputDecoration(
            hintText: 'Search by doctor, date, time, or reason...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            prefixIcon: Icon(Icons.search, color: Colors.teal.shade700),
            suffixIcon: ValueListenableBuilder<String>(
              valueListenable: _searchNotifier,
              builder: (context, value, _) => value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchNotifier.value = '';
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
      // Active filter chips also need to react to specialization/status changes (those still use setState)
      if (_hasActiveFilters) _buildActiveFiltersChips(),
    ]);
  }

  Widget _buildActiveFiltersChips() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (_selectedSpecialization != null)
          Chip(
            avatar: Icon(Icons.medical_services, size: 16, color: Colors.teal.shade700),
            label: Text(_selectedSpecialization!),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => setState(() => _selectedSpecialization = null),
            backgroundColor: Colors.teal.shade50,
            labelStyle: TextStyle(fontSize: 12, color: Colors.teal.shade700),
          ),
        if (_selectedStatus != null)
          Chip(
            avatar: Icon(_getStatusIcon(_selectedStatus!), size: 16,
                color: _getStatusColor(_selectedStatus!)),
            label: Text(_selectedStatus!.toUpperCase()),
            deleteIcon: const Icon(Icons.close, size: 18),
            onDeleted: () => setState(() => _selectedStatus = null),
            backgroundColor: _getStatusColor(_selectedStatus!).withOpacity(0.1),
            labelStyle: TextStyle(
                fontSize: 12,
                color: _getStatusColor(_selectedStatus!),
                fontWeight: FontWeight.bold),
          ),
        ActionChip(
          avatar: const Icon(Icons.filter_alt_off, size: 16),
          label: const Text('Clear All'),
          onPressed: _clearFilters,
          backgroundColor: Colors.grey.shade100,
          labelStyle: const TextStyle(fontSize: 12),
        ),
      ]),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case AppointmentService.statusPending:
        return Icons.schedule;
      case AppointmentService.statusApproved:
        return Icons.check_circle;
      case AppointmentService.statusRejected:
        return Icons.cancel;
      case AppointmentService.statusCompleted:
        return Icons.done_all;
      case AppointmentService.statusCancelled:
        return Icons.block;
      default:
        return Icons.help;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case AppointmentService.statusPending:
        return Colors.orange;
      case AppointmentService.statusApproved:
        return Colors.green;
      case AppointmentService.statusRejected:
        return Colors.red;
      case AppointmentService.statusCompleted:
        return Colors.blue;
      case AppointmentService.statusCancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTabBar(List<Map<String, dynamic>> appointments) {
    final all = appointments.length;
    final upcoming = appointments
        .where((a) => [
              AppointmentService.statusPending,
              AppointmentService.statusApproved
            ].contains(a['status']))
        .length;
    final past = appointments
        .where((a) => [
              AppointmentService.statusCompleted,
              AppointmentService.statusRejected,
              AppointmentService.statusCancelled
            ].contains(a['status']))
        .length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: Colors.teal.shade700,
        labelColor: Colors.teal.shade700,
        unselectedLabelColor: Colors.grey,
        indicator:
            BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(16)),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
              icon: Badge(
                  label: Text('$all'),
                  isLabelVisible: all > 0,
                  child: const Icon(Icons.list)),
              text: 'All'),
          Tab(
              icon: Badge(
                  label: Text('$upcoming'),
                  isLabelVisible: upcoming > 0,
                  child: const Icon(Icons.upcoming)),
              text: 'Upcoming'),
          Tab(
              icon: Badge(
                  label: Text('$past'),
                  isLabelVisible: past > 0,
                  child: const Icon(Icons.history)),
              text: 'Past'),
        ],
      ),
    );
  }

  Widget _buildTabContent(
      List<Map<String, dynamic>> allAppointments,
      List<Map<String, dynamic>> filteredAppointments) {
    if (allAppointments.isEmpty && !_hasActiveFilters) return _buildEmptyState();
    return TabBarView(
      controller: _tabController,
      children: [
        _buildAppointmentsList(filteredAppointments),
        _buildAppointmentsList(filteredAppointments
            .where((a) => [
                  AppointmentService.statusPending,
                  AppointmentService.statusApproved
                ].contains(a['status']))
            .toList()),
        _buildAppointmentsList(filteredAppointments
            .where((a) => [
                  AppointmentService.statusCompleted,
                  AppointmentService.statusRejected,
                  AppointmentService.statusCancelled
                ].contains(a['status']))
            .toList()),
      ],
    );
  }

  Widget _buildAppointmentsList(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) return _buildEmptyState();
    return RefreshIndicator(
      onRefresh: () async => await _loadGracePeriodAndStats(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: appointments.length,
        itemBuilder: (ctx, index) => _buildAppointmentCard(appointments[index]),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final status = appointment['status'];
    final date = DateTime.parse(appointment['appointmentDate']);
    final isUpcoming = date.isAfter(DateTime.now());

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case AppointmentService.statusPending:
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        statusLabel = 'PENDING';
        break;
      case AppointmentService.statusApproved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusLabel = 'APPROVED';
        break;
      case AppointmentService.statusRejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusLabel = 'REJECTED';
        break;
      case AppointmentService.statusCompleted:
        statusColor = Colors.blue;
        statusIcon = Icons.done_all;
        statusLabel = 'COMPLETED';
        break;
      case AppointmentService.statusCancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.block;
        statusLabel = 'CANCELLED';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusLabel = 'UNKNOWN';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showAppointmentDetails(appointment),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [statusColor.withOpacity(0.05), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.teal.shade100,
                  child: Text(
                    appointment['doctorName'].toString().split(' ').length > 1
                        ? appointment['doctorName'].toString().split(' ')[1][0]
                        : appointment['doctorName'].toString()[0],
                    style: TextStyle(
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appointment['doctorName'],
                      style:
                          const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(appointment['specialization'],
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration:
                      BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, color: Colors.white, size: 11),
                    const SizedBox(width: 3),
                    Text(statusLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(DateFormat('dd MMM yyyy').format(date),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(width: 10),
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(appointment['timeSlot'],
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                if (isUpcoming && status == AppointmentService.statusApproved) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Upcoming',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.medical_services, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(appointment['reason'],
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
              if (status == AppointmentService.statusRejected &&
                  appointment['rejectionReason'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200)),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('Rejected: ${appointment['rejectionReason']}',
                            style: TextStyle(color: Colors.red.shade900, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],
              if (status == AppointmentService.statusCompleted) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.done_all, color: Colors.blue.shade700, size: 14),
                      const SizedBox(width: 6),
                      Text('Consultation Completed',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900)),
                    ]),
                    if (appointment['doctorNotes'] != null &&
                        appointment['doctorNotes'].toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('📋 ${appointment['doctorNotes']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 6),
                    FutureBuilder<bool>(
                      future: ConsultationFeedbackService.instance
                          .hasFeedbackForAppointment(appointment['id']),
                      builder: (context, snapshot) {
                        final hasFeedback = snapshot.data ?? false;
                        if (hasFeedback) {
                          return Row(children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 14),
                            const SizedBox(width: 6),
                            Text('Feedback submitted',
                                style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                            const Spacer(),
                            TextButton(
                              onPressed: () async {
                                final feedback = await ConsultationFeedbackService.instance
                                    .getFeedbackForAppointment(appointment['id']);
                                if (feedback != null && context.mounted) {
                                  _showFeedbackDetails(context, feedback);
                                }
                              },
                              style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              child: const Text('View', style: TextStyle(fontSize: 11)),
                            ),
                          ]);
                        }
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await showFeedbackDialog(
                                context: context,
                                appointmentId: appointment['id'],
                                patientId: user!.uid,
                                doctorId: appointment['doctorId'],
                                doctorName: appointment['doctorName'],
                              );
                              if (result == true && context.mounted) setState(() {});
                            },
                            icon: const Icon(Icons.rate_review, size: 14),
                            label: const Text('Give Feedback', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
              ],
              if (status == AppointmentService.statusPending) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelAppointment(appointment['id']),
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ] else if (status == AppointmentService.statusApproved) ...[
                const SizedBox(height: 6),
                FutureBuilder<String>(
                  future: _dataSharingService.getPermissionStatus(
                      appointmentId: appointment['id'], patientId: user!.uid),
                  builder: (context, snapshot) {
                    final permissionStatus = snapshot.data ?? 'pending';
                    if (permissionStatus == 'pending') {
                      return SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton.icon(
                          onPressed: () => _showDataSharingReview(appointment),
                          icon: const Icon(Icons.privacy_tip, size: 14),
                          label: const Text('Review Data Sharing',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      );
                    }
                    return Row(children: [
                      Icon(
                          permissionStatus == 'approved'
                              ? Icons.check_circle
                              : Icons.info,
                          color: permissionStatus == 'approved'
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          size: 14),
                      const SizedBox(width: 6),
                      Text(
                          'Data Sharing: ${permissionStatus == 'approved' ? 'Approved' : 'Not Approved'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: permissionStatus == 'approved'
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700)),
                    ]);
                  },
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.calendar_today_outlined, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
            _searchQuery.isNotEmpty ? 'No appointments found' : 'No appointments yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text(
            _searchQuery.isNotEmpty
                ? 'Try adjusting your search'
                : 'Book your first appointment',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        if (_searchQuery.isEmpty) ...[
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showBookAppointmentDialog,
            icon: const Icon(Icons.add),
            label: const Text('Book Appointment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildBookButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _showBookAppointmentDialog,
          icon: const Icon(Icons.add_circle_outline, size: 24),
          label: const Text('Book New Appointment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            shadowColor: Colors.teal.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  void _showAppointmentDetails(Map<String, dynamic> appointment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.info_outline, color: Colors.teal.shade700),
          const SizedBox(width: 12),
          const Text('Appointment Details')
        ]),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Doctor', appointment['doctorName']),
                _buildDetailRow('Specialization', appointment['specialization']),
                _buildDetailRow('Date',
                    DateFormat('dd MMM yyyy').format(DateTime.parse(appointment['appointmentDate']))),
                _buildDetailRow('Time', appointment['timeSlot']),
                _buildDetailRow('Status', appointment['status'].toString().toUpperCase()),
                _buildDetailRow('Reason', appointment['reason']),
                if (appointment['notes'].toString().isNotEmpty)
                  _buildDetailRow('Notes', appointment['notes']),
                if (appointment['rejectionReason'].toString().isNotEmpty)
                  _buildDetailRow('Rejection Reason', appointment['rejectionReason'],
                      isError: true),
                if (appointment['status'] == AppointmentService.statusCompleted &&
                    appointment['doctorNotes'] != null &&
                    appointment['doctorNotes'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.medical_information, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text("Doctor's Consultation Notes",
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900)),
                      ]),
                      const SizedBox(height: 8),
                      Text(appointment['doctorNotes'].toString(),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade800, height: 1.5)),
                    ]),
                  ),
                ],
              ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isError ? Colors.red.shade700 : Colors.grey.shade900)),
      ]),
    );
  }

  void _showRecommendationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.recommend, color: Colors.amber.shade700)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('✨ Recommended Doctors',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Based on your previous selection',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
              ]),
            ),
            Expanded(
                child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recommendations.length,
              itemBuilder: (ctx, index) =>
                  _buildRecommendationCard(_recommendations[index]),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(Map<String, dynamic> doctor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.amber.shade50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.teal.shade700,
              child: Text(
                doctor['name'].toString().split(' ').length > 1
                    ? doctor['name'].toString().split(' ')[1][0].toUpperCase()
                    : doctor['name'].toString()[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doctor['name'],
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(doctor['specialization'],
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text('${doctor['rating']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(doctor['location'],
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
              ]),
            ])),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Consultation Fee',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text('Rs.${doctor['consultationFee']}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700)),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Future.delayed(
                    const Duration(milliseconds: 300), _showBookAppointmentDialog);
              },
              icon: const Icon(Icons.calendar_month),
              label: const Text('Book with this Doctor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          const Text('Cancel Appointment?')
        ]),
        content: const Text(
            'Are you sure you want to cancel this appointment? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, Keep It')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _appointmentService.cancelAppointment(appointmentId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Appointment cancelled successfully')
            ]),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to cancel appointment: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
  }

  void _showGracePeriodAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 32),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Appointment Update', style: TextStyle(fontSize: 20))),
        ]),
        content:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('❌ Your appointment request was not accepted.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.access_time, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Text('⏰ 24-Hour Grace Period Active',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              ]),
              const SizedBox(height: 8),
              Text(
                  'We found ${_recommendations.length} alternative doctors with similar specialization for you.',
                  style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('View Later')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showRecommendationsSheet();
            },
            icon: const Icon(Icons.recommend),
            label: const Text('View Alternatives'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Color _getFeedbackTypeColor(String type) {
    switch (type) {
      case 'compliment':
        return Colors.green;
      case 'complaint':
        return Colors.red;
      case 'suggestion':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColorForFeedback(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'resolved':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showFeedbackDetails(BuildContext context, Map<String, dynamic> feedback) {
    final rating = feedback['rating'] as int;
    final type = feedback['feedbackType'] as String;
    final comments = feedback['comments'] as String;
    final isAnonymous = feedback['isAnonymous'] as bool;
    final status = feedback['status'] as String;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.feedback, color: Colors.teal.shade700),
          const SizedBox(width: 12),
          const Text('Your Feedback')
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Rating: ', style: TextStyle(fontWeight: FontWeight.bold)),
                ...List.generate(
                    5,
                    (index) => Icon(index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber, size: 20)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Type: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(
                    label: Text(type.toUpperCase()),
                    backgroundColor: _getFeedbackTypeColor(type).withOpacity(0.2),
                    labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getFeedbackTypeColor(type))),
              ]),
              const SizedBox(height: 12),
              const Text('Comments:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Text(comments, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(
                    label: Text(status.toUpperCase()),
                    backgroundColor: _getStatusColorForFeedback(status).withOpacity(0.2),
                    labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColorForFeedback(status))),
              ]),
              if (isAnonymous) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.privacy_tip, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text('Submitted anonymously',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                ]),
              ],
            ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _showDataSharingReview(Map<String, dynamic> appointment) async {
    final result = await showDataSharingReviewDialog(
      context: context,
      appointmentId: appointment['id'],
      patientId: user!.uid,
      doctorName: appointment['doctorName'] ?? 'Doctor',
      appointmentDate: DateFormat('MMM dd, yyyy')
          .format(DateTime.parse(appointment['appointmentDate'])),
      onComplete: () {},
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Data sharing approved successfully!'),
          backgroundColor: Colors.green));
    } else if (result == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Data sharing rejected'), backgroundColor: Colors.orange));
    }
  }
}

// ==================== COMPACT ICON BUTTON ====================

/// A small icon button with an optional orange dot indicator.
/// Used in the top nav row — sized to fit 3–4 icons without crowding.
class _CompactIconBtn extends StatelessWidget {
  final IconData icon;
  final bool dot;
  final VoidCallback? onTap;

  const _CompactIconBtn({required this.icon, required this.dot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 17),
            if (dot)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== BOOKING DIALOG ====================

class _BookingDialog extends StatefulWidget {
  final List<Map<String, dynamic>> doctors;
  final String? preFilledReason;
  final String? symptomSeverity;
  final String? suggestedSpecialization;
  final VoidCallback onBooked;

  const _BookingDialog({
    required this.doctors,
    this.preFilledReason,
    this.symptomSeverity,
    this.suggestedSpecialization,
    required this.onBooked,
  });

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final _appointmentService = AppointmentService.instance;
  final _user = FirebaseAuth.instance.currentUser;

  Map<String, dynamic>? _selectedDoctor;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTimeSlot;
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isBooking = false;
  String? _selectedSpecialization;
  List<Map<String, dynamic>> _filteredDoctors = [];

  @override
  void initState() {
    super.initState();
    if (widget.preFilledReason != null) _reasonController.text = widget.preFilledReason!;
    if (widget.suggestedSpecialization != null) {
      _selectedSpecialization = widget.suggestedSpecialization!;
      _filteredDoctors = widget.doctors
          .where((d) => d['specialization'] == widget.suggestedSpecialization)
          .toList();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _bookAppointment() async {
    if (_selectedDoctor == null) {
      _showError('Please select a doctor');
      return;
    }
    if (_selectedTimeSlot == null) {
      _showError('Please select a time slot');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _showError('Please provide a reason for visit');
      return;
    }
    setState(() => _isBooking = true);
    try {
      await _appointmentService.bookAppointment(
        userId: _user!.uid,
        doctorId: _selectedDoctor!['id'],
        appointmentDate: _selectedDate,
        timeSlot: _selectedTimeSlot!,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text('Appointment booked successfully!'))
          ]),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        widget.onBooked();
      }
    } catch (e) {
      if (mounted) _showError('Failed to book appointment: $e');
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 32),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Booking Failed',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        ]),
        content:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(message,
                      style: TextStyle(fontSize: 14, color: Colors.red.shade900))),
            ]),
          ),
          const SizedBox(height: 16),
          Text('💡 Tip: Try selecting a different time slot or date',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white),
              child: const Text('Try Again')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Column(children: [
          Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.teal.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.calendar_month, color: Colors.teal.shade700, size: 28)),
              const SizedBox(width: 12),
              const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Book Appointment',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Select a doctor and time slot',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
              IconButton(
                  onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.symptomSeverity != null) _buildUrgencyBanner(),
                _buildSpecializationDropdown(),
                const SizedBox(height: 16),
                const Text('Select Doctor',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                _buildDoctorsList(),
                if (_selectedDoctor != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200)),
                      child: Row(children: [
                        Icon(Icons.info_outline, color: Colors.teal.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                                'Available Days: ${(_selectedDoctor!['available_days'] as List<String>).join(', ')}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal.shade900))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 16),
                _buildDatePicker(),
                const SizedBox(height: 24),
                if (_selectedDoctor != null) _buildTimeSlotSelection(),
                const SizedBox(height: 24),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for Visit *',
                    hintText: 'Describe your symptoms or reason',
                    prefixIcon: Icon(Icons.medical_services, color: Colors.teal.shade700),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    hintText: 'Any additional information',
                    prefixIcon: Icon(Icons.note, color: Colors.teal.shade700),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isBooking ? null : _bookAppointment,
                    icon: _isBooking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white)))
                        : const Icon(Icons.check_circle, size: 24),
                    label: Text(_isBooking ? 'Booking...' : 'Confirm Booking',
                        style:
                            const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildUrgencyBanner() {
    Color bannerColor;
    IconData bannerIcon;
    String bannerText;
    switch (widget.symptomSeverity) {
      case 'severe':
        bannerColor = Colors.red.shade700;
        bannerIcon = Icons.warning;
        bannerText = '🚨 Urgent consultation recommended';
        break;
      case 'moderate':
        bannerColor = Colors.orange.shade700;
        bannerIcon = Icons.info;
        bannerText = '⚠️ Consultation advised within 2-3 days';
        break;
      default:
        bannerColor = Colors.green.shade700;
        bannerIcon = Icons.check_circle;
        bannerText = '✓ Routine consultation';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
          color: bannerColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bannerColor.withOpacity(0.3))),
      child: Row(children: [
        Icon(bannerIcon, color: bannerColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
            child: Text(bannerText,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: bannerColor))),
      ]),
    );
  }

  Map<String, String> _getSpecializationSymptoms() {
    Map<String, Set<String>> tempMap = {};
    for (var doctor in widget.doctors) {
      String spec = doctor['specialization'];
      List<String> expertise = List<String>.from(doctor['expertise'] ?? []);
      if (!tempMap.containsKey(spec)) tempMap[spec] = {};
      tempMap[spec]!.addAll(expertise);
    }
    return tempMap.map((key, value) => MapEntry(key, value.join(", ")));
  }

  Widget _buildSpecializationDropdown() {
    final symptomsMap = _getSpecializationSymptoms();
    final specializations = symptomsMap.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('What is your health concern?',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
      const SizedBox(height: 10),
      PopupMenuButton<String>(
        offset: const Offset(0, 55),
        constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32,
            maxWidth: MediaQuery.of(context).size.width - 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (String value) {
          setState(() {
            _selectedSpecialization = value;
            _selectedDoctor = null;
            _filteredDoctors =
                widget.doctors.where((d) => d['specialization'] == value).toList();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.teal.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(children: [
            Icon(Icons.search, color: Colors.teal.shade700),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    _selectedSpecialization ??
                        'Search by symptom (Fever, Diet, etc.)',
                    style: TextStyle(
                        color: _selectedSpecialization != null
                            ? Colors.black87
                            : Colors.grey.shade600))),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
        itemBuilder: (context) => specializations.map((spec) {
          final isSelected = _selectedSpecialization == spec;
          final expertiseList = symptomsMap[spec] ?? "";
          return PopupMenuItem<String>(
            value: spec,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: isSelected ? Colors.teal : Colors.teal.shade50,
                  child: Icon(_getIconForSpecialization(spec),
                      color: isSelected ? Colors.white : Colors.teal.shade700, size: 20),
                ),
                const SizedBox(width: 15),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(spec,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.teal : Colors.black87)),
                  const SizedBox(height: 2),
                  Text("Treats: $expertiseList",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ])),
              ]),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 20),
    ]);
  }

  IconData _getIconForSpecialization(String spec) {
    switch (spec) {
      case 'General Physician':
        return Icons.medical_services;
      case 'Nutritionist':
        return Icons.apple;
      case 'Cardiologist':
        return Icons.favorite;
      case 'Dermatologist':
        return Icons.face;
      case 'Pediatrician':
        return Icons.child_care;
      case 'Gastroenterologist':
        return Icons.restaurant_menu;
      case 'Neurologist':
        return Icons.psychology;
      case 'Psychiatrist':
        return Icons.volunteer_activism;
      default:
        return Icons.person;
    }
  }

  Widget _buildDoctorsList() {
    if (_selectedSpecialization == null)
      return Container(
          height: 60,
          alignment: Alignment.center,
          child: const Text('Please select a specialization first',
              style: TextStyle(color: Colors.grey)));
    if (_filteredDoctors.isEmpty)
      return Container(
          height: 60,
          alignment: Alignment.center,
          child: const Text('No doctors available for this specialization',
              style: TextStyle(color: Colors.grey)));
    return Container(
      height: 250,
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12)),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _filteredDoctors.length,
        itemBuilder: (context, index) {
          final doctor = _filteredDoctors[index];
          final isSelected = _selectedDoctor == doctor;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.teal.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isSelected ? Colors.teal.shade400 : Colors.grey.shade200,
                  width: isSelected ? 2 : 1),
            ),
            child: ListTile(
              onTap: () async {
                final selected = await showDoctorDetailsDialog(context, doctor);
                if (selected != null && mounted) {
                  setState(() {
                    _selectedDoctor = selected;
                    _selectedTimeSlot = null;
                  });
                }
              },
              leading: CircleAvatar(
                backgroundColor: Colors.teal.shade700,
                child: Text(
                    doctor['name'].toString().split(' ').length > 1
                        ? doctor['name'].toString().split(' ')[1][0]
                        : doctor['name'].toString()[0],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(doctor['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doctor['specialization'],
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text('${doctor['rating']}', style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(doctor['location'],
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis)),
                ]),
              ]),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('Rs.${doctor['consultation_fee']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 90)),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(primary: Colors.teal.shade700)),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() {
            _selectedDate = picked;
            _selectedTimeSlot = null;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.calendar_today, color: Colors.teal.shade700),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Appointment Date',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ])),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }

  Widget _buildTimeSlotSelection() {
    final slots = List<String>.from(_selectedDoctor!['available_time_slots'] ?? []);
    if (slots.isEmpty) return const Text('No time slots available');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Time Slot',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: slots.map((slot) {
          final isSelected = _selectedTimeSlot == slot;
          return InkWell(
            onTap: () => setState(() => _selectedTimeSlot = slot),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.teal.shade700 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? Colors.teal.shade700 : Colors.grey.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time,
                    size: 16, color: isSelected ? Colors.white : Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(slot,
                    style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.grey.shade800,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}