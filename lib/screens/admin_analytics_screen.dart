import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;
  
  bool _isLoading = true;
  String _selectedTimeRange = 'all';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  
  // Statistics
  Map<String, int> _stats = {
    'totalPatients': 0,
    'totalDoctors': 0,
    'totalAppointments': 0,
    'pendingAppointments': 0,
    'approvedAppointments': 0,
    'completedAppointments': 0,
    'rejectedAppointments': 0,
    'cancelledAppointments': 0, // Added cancelled status
    'totalFeedback': 0,
    'newPatientsThisWeek': 0,
    'newPatientsThisMonth': 0,
  };
  
  List<Map<String, dynamic>> _patientsByGender = [];
  List<Map<String, dynamic>> _appointmentTrends = [];
  List<Map<String, dynamic>> _topDoctors = [];
  
  // Filtered data
  List<QueryDocumentSnapshot> _allProfiles = []; // Changed from _allPatients
  List<QueryDocumentSnapshot> _allAppointments = [];
  List<QueryDocumentSnapshot> _allFeedback = [];
  int _totalDoctorsCount = 0; // Store doctors count once
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAnalytics();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    
    try {
      await Future.wait([
        _loadAllData(),
      ]);
      _applyFilters();
    } catch (e) {
      print('Error loading analytics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _loadAllData() async {
    try {
      // Get patients from profiles collection
      final profiles = await _firestore
          .collection('profiles')
          .get();
      
      // Get doctors from users collection (filter by userType to exclude admin)
      final doctors = await _firestore
          .collection('users')
          .where('userType', isEqualTo: 'doctor')
          .get();
      
      final appointments = await _firestore
          .collection('appointments')
          .get();
      
      final feedback = await _firestore
          .collection('consultation_feedback')
          .get();
      
      if (mounted) {
        setState(() {
          _allProfiles = profiles.docs;
          _totalDoctorsCount = doctors.docs.length; // Only counts users with userType='doctor'
          _allAppointments = appointments.docs;
          _allFeedback = feedback.docs;
        });
      }
    } catch (e) {
      print('Error loading all data: $e');
    }
  }
  
  void _applyFilters() {
    DateTime? startDate;
    DateTime? endDate;
    
    final now = DateTime.now();
    
    switch (_selectedTimeRange) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'week':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        endDate = now;
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1);
        endDate = now;
        break;
      case 'custom':
        startDate = _customStartDate;
        endDate = _customEndDate;
        break;
      case 'all':
      default:
        startDate = null;
        endDate = null;
    }
    
    _calculateStats(startDate, endDate);
    _calculateDemographics(startDate, endDate);
    _calculateTrends(startDate, endDate);
    _calculateTopDoctors(startDate, endDate);
  }
  
  void _calculateStats(DateTime? startDate, DateTime? endDate) {
    final filteredAppointments = _filterByDate(_allAppointments, startDate, endDate);
    final filteredProfiles = _filterByDate(_allProfiles, startDate, endDate); // Use profiles
    final filteredFeedback = _filterByDate(_allFeedback, startDate, endDate);
    
    int pending = 0, approved = 0, completed = 0, rejected = 0, cancelled = 0;
    for (var doc in filteredAppointments) {
      final data = doc.data() as Map<String, dynamic>?;
      final status = data?['status'] ?? '';
      switch (status.toLowerCase()) {
        case 'pending': pending++; break;
        case 'approved': approved++; break;
        case 'completed': completed++; break;
        case 'rejected': rejected++; break;
        case 'cancelled': cancelled++; break;
      }
    }
    
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = DateTime(now.year, now.month, 1);
    
    int newThisWeek = 0, newThisMonth = 0;
    for (var doc in _allProfiles) { // Use profiles
      final data = doc.data() as Map<String, dynamic>?;
      final createdAt = data?['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final date = createdAt.toDate();
        if (date.isAfter(weekAgo)) newThisWeek++;
        if (date.isAfter(monthAgo)) newThisMonth++;
      }
    }
    
    if (mounted) {
      setState(() {
        _stats = {
          'totalPatients': filteredProfiles.length, // Use profiles count
          'totalDoctors': _totalDoctorsCount,
          'totalAppointments': filteredAppointments.length,
          'pendingAppointments': pending,
          'approvedAppointments': approved,
          'completedAppointments': completed,
          'rejectedAppointments': rejected,
          'cancelledAppointments': cancelled,
          'totalFeedback': filteredFeedback.length,
          'newPatientsThisWeek': newThisWeek,
          'newPatientsThisMonth': newThisMonth,
        };
      });
    }
  }
  
  void _calculateDemographics(DateTime? startDate, DateTime? endDate) async {
    // Use already loaded profiles instead of querying again
    final filteredProfiles = _filterByDate(_allProfiles, startDate, endDate);
    
    Map<String, int> genderCount = {'Male': 0, 'Female': 0, 'Other': 0};
    
    for (var doc in filteredProfiles) {
      final data = doc.data() as Map<String, dynamic>?;
      final gender = data?['gender'] as String? ?? 'Other';
      genderCount[gender] = (genderCount[gender] ?? 0) + 1;
    }
    
    setState(() {
      _patientsByGender = genderCount.entries
          .where((e) => e.value > 0)
          .map((e) => {'gender': e.key, 'count': e.value})
          .toList();
    });
  }
  
  void _calculateTrends(DateTime? startDate, DateTime? endDate) {
    final filteredAppointments = _filterByDate(_allAppointments, startDate, endDate);
    
    final now = DateTime.now();
    Map<String, int> dailyCount = {};
    
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateKey = DateFormat('MM/dd').format(date);
      dailyCount[dateKey] = 0;
    }
    
    for (var doc in filteredAppointments) {
      final data = doc.data() as Map<String, dynamic>?;
      final createdAt = data?['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final date = createdAt.toDate();
        final dateKey = DateFormat('MM/dd').format(date);
        
        if (dailyCount.containsKey(dateKey)) {
          dailyCount[dateKey] = (dailyCount[dateKey] ?? 0) + 1;
        }
      }
    }
    
    setState(() {
      _appointmentTrends = dailyCount.entries
          .map((e) => {'date': e.key, 'count': e.value})
          .toList();
    });
  }
  
  // void _calculateTopDoctors(DateTime? startDate, DateTime? endDate) async {
  //   final doctorProfiles = await _firestore.collection('doctor_profiles').get();
    
  //   List<Map<String, dynamic>> doctors = [];
    
  //   for (var doc in doctorProfiles.docs) {
  //     final data = doc.data();
  //     final appointmentCount = data['totalAppointments'] as int? ?? 0;
  //     final rating = data['rating'] as double? ?? 0.0;
      
  //     doctors.add({
  //       'name': data['fullName'] ?? 'Unknown',
  //       'specialization': data['specialization'] ?? '',
  //       'appointments': appointmentCount,
  //       'rating': rating,
  //     });
  //   }
    
  //   doctors.sort((a, b) => b['appointments'].compareTo(a['appointments']));
    
  //   setState(() {
  //     _topDoctors = doctors.take(5).toList();
  //   });
  // }
  
void _calculateTopDoctors(DateTime? startDate, DateTime? endDate) async {
  final doctorProfiles = await _firestore.collection('doctor_profiles').get();
  
  List<Map<String, dynamic>> doctors = [];
  
  for (var doc in doctorProfiles.docs) {
    final data = doc.data();
    final doctorId = data['doctorId'] as String?; // Get doctorId from the profile
    final uid = data['uid'] as String?; // Also get uid in case that's used instead
    
    if (doctorId == null && uid == null) continue;
    
    // Filter appointments for this doctor (case-insensitive comparison)
    final filteredAppointments = _filterByDate(_allAppointments, startDate, endDate);
    
    final appointmentCount = filteredAppointments.where((appt) {
      final apptData = appt.data() as Map<String, dynamic>?;
      final apptDoctorId = apptData?['doctorId'] as String?;
      
      if (apptDoctorId == null) return false;
      
      // Compare case-insensitively to handle DOC020 vs doc020
      return apptDoctorId.toLowerCase() == doctorId?.toLowerCase() ||
             apptDoctorId.toLowerCase() == uid?.toLowerCase();
    }).length;
    
    final rating = data['rating'] as double? ?? 0.0;
    
    doctors.add({
      'name': data['fullName'] ?? 'Unknown',
      'specialization': data['specialization'] ?? '',
      'appointments': appointmentCount,
      'rating': rating,
    });
  }
  
  // Sort by appointment count descending
  doctors.sort((a, b) => b['appointments'].compareTo(a['appointments']));
  
  setState(() {
    _topDoctors = doctors.take(5).toList();
  });
}








  List<QueryDocumentSnapshot> _filterByDate(
    List<QueryDocumentSnapshot> docs,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    if (startDate == null && endDate == null) return docs;
    
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final createdAt = data?['createdAt'] as Timestamp?;
      if (createdAt == null) return false;
      
      final date = createdAt.toDate();
      
      if (startDate != null && date.isBefore(startDate)) return false;
      if (endDate != null && date.isAfter(endDate)) return false;
      
      return true;
    }).toList();
  }
  
  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Analytics Report',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Generated: ${DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            if (_selectedTimeRange != 'all')
              pw.Text(
                'Period: ${_getFilterDescription()}',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
            pw.SizedBox(height: 30),
            
            // Overview Statistics
            pw.Header(level: 1, text: 'Overview Statistics'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Metric', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Value', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                ..._buildStatRows(),
              ],
            ),
            
            pw.SizedBox(height: 30),
            
            // Appointment Status
            pw.Header(level: 1, text: 'Appointment Status'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                _buildTableRow('Pending', _stats['pendingAppointments']?.toString() ?? '0'),
                _buildTableRow('Approved', _stats['approvedAppointments']?.toString() ?? '0'),
                _buildTableRow('Completed', _stats['completedAppointments']?.toString() ?? '0'),
                _buildTableRow('Rejected', _stats['rejectedAppointments']?.toString() ?? '0'),
                _buildTableRow('Cancelled', _stats['cancelledAppointments']?.toString() ?? '0'),
              ],
            ),
            
            pw.SizedBox(height: 30),
            
            // Top Doctors
            if (_topDoctors.isNotEmpty) ...[
              pw.Header(level: 1, text: 'Top Performing Doctors'),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Rank', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Specialization', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Appointments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Rating', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  ..._topDoctors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final doctor = entry.value;
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${index + 1}')),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(doctor['name'])),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(doctor['specialization'])),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${doctor['appointments']}')),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(doctor['rating'].toStringAsFixed(1))),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ],
          ];
        },
      ),
    );
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
  
  List<pw.TableRow> _buildStatRows() {
    return [
      _buildTableRow('Total Patients', _stats['totalPatients']?.toString() ?? '0'),
      _buildTableRow('Total Doctors', _stats['totalDoctors']?.toString() ?? '0'),
      _buildTableRow('Total Appointments', _stats['totalAppointments']?.toString() ?? '0'),
      _buildTableRow('Total Feedback', _stats['totalFeedback']?.toString() ?? '0'),
      _buildTableRow('New Patients (This Week)', _stats['newPatientsThisWeek']?.toString() ?? '0'),
      _buildTableRow('New Patients (This Month)', _stats['newPatientsThisMonth']?.toString() ?? '0'),
    ];
  }
  
  pw.TableRow _buildTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label)),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value)),
      ],
    );
  }
  
  String _getFilterDescription() {
    switch (_selectedTimeRange) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
        }
        return 'Custom Range';
      default:
        return 'All Time';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export PDF',
            onPressed: _isLoading ? null : _exportToPDF,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAnalytics,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              _buildCompactTimeFilter(),
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.dashboard, size: 20),
                    text: 'Overview',
                    iconMargin: EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    icon: Icon(Icons.show_chart, size: 20),
                    text: 'Trends',
                    iconMargin: EdgeInsets.only(bottom: 4),
                  ),
                  Tab(
                    icon: Icon(Icons.star, size: 20),
                    text: 'Top Doctors',
                    iconMargin: EdgeInsets.only(bottom: 4),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildTrendsTab(),
                _buildDoctorsTab(),
              ],
            ),
    );
  }
  
  Widget _buildCompactTimeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all'),
            _buildFilterChip('Today', 'today'),
            _buildFilterChip('Week', 'week'),
            _buildFilterChip('Month', 'month'),
            _buildFilterChip('Custom', 'custom'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedTimeRange == value;
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (selected) async {
          if (value == 'custom') {
            await _showCustomDatePicker();
          } else {
            setState(() => _selectedTimeRange = value);
            _applyFilters();
          }
        },
        selectedColor: Colors.white,
        checkmarkColor: Colors.deepPurple,
        backgroundColor: Colors.deepPurple.shade100,
        labelStyle: TextStyle(
          color: isSelected ? Colors.deepPurple : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
  
  Future<void> _showCustomDatePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedTimeRange = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _applyFilters();
    }
  }
  
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: [
              _buildCompactMetricCard('Patients', _stats['totalPatients']?.toString() ?? '0', Icons.people, Colors.blue),
              _buildCompactMetricCard('Doctors', _stats['totalDoctors']?.toString() ?? '0', Icons.medical_services, Colors.green),
              _buildCompactMetricCard('Appointments', _stats['totalAppointments']?.toString() ?? '0', Icons.calendar_today, Colors.orange),
              _buildCompactMetricCard('Feedback', _stats['totalFeedback']?.toString() ?? '0', Icons.feedback, Colors.purple),
            ],
          ),
          
          const SizedBox(height: 20),
          
          _buildAppointmentStatusCard(),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(child: _buildGrowthCard('New Patients\nThis Week', _stats['newPatientsThisWeek'] ?? 0, Icons.trending_up, Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _buildGrowthCard('New Patients\nThis Month', _stats['newPatientsThisMonth'] ?? 0, Icons.calendar_month, Colors.blue)),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAppointmentTrendsChart(),
          const SizedBox(height: 20),
          _buildGenderDistributionChart(),
        ],
      ),
    );
  }
  
  Widget _buildDoctorsTab() {
    if (_topDoctors.isEmpty) {
      return const Center(child: Text('No doctor data available'));
    }
    
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _topDoctors.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doctor = _topDoctors[index];
        return Card(
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade300, Colors.deepPurple.shade600],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            title: Text(doctor['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(doctor['specialization'], style: const TextStyle(fontSize: 13)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(doctor['rating'].toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Text('${doctor['appointments']} apps', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCompactMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAppointmentStatusCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Appointment Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('Pending', _stats['pendingAppointments'] ?? 0, Colors.orange),
                _buildStatusItem('Approved', _stats['approvedAppointments'] ?? 0, Colors.blue),
                _buildStatusItem('Completed', _stats['completedAppointments'] ?? 0, Colors.green),
                _buildStatusItem('Rejected', _stats['rejectedAppointments'] ?? 0, Colors.red),
                _buildStatusItem('Cancelled', _stats['cancelledAppointments'] ?? 0, Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }
  
  Widget _buildGrowthCard(String label, int value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAppointmentTrendsChart() {
    if (_appointmentTrends.isEmpty) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Appointment Trends (7 Days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tap on any point to see the exact count',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1)),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                      if (value.toInt() >= 0 && value.toInt() < _appointmentTrends.length) {
                        return Padding(padding: const EdgeInsets.only(top: 8), child: Text(_appointmentTrends[value.toInt()]['date'], style: const TextStyle(fontSize: 9)));
                      }
                      return const Text('');
                    })),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.deepPurple.withOpacity(0.9),
                      tooltipRoundedRadius: 8,
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final date = _appointmentTrends[spot.x.toInt()]['date'];
                          return LineTooltipItem(
                            '$date\n${spot.y.toInt()} appointments',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                    getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                      return spotIndexes.map((index) {
                        return TouchedSpotIndicatorData(
                          FlLine(color: Colors.deepPurple, strokeWidth: 2),
                          FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 6,
                              color: Colors.white,
                              strokeWidth: 3,
                              strokeColor: Colors.deepPurple,
                            ),
                          ),
                        );
                      }).toList();
                    },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _appointmentTrends.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['count'].toDouble())).toList(),
                      isCurved: true,
                      color: Colors.deepPurple,
                      barWidth: 3,
                      dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: Colors.deepPurple)),
                      belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.deepPurple.withOpacity(0.3), Colors.deepPurple.withOpacity(0.05)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGenderDistributionChart() {
    if (_patientsByGender.isEmpty) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Patient Demographics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: _patientsByGender.asMap().entries.map((e) {
                          final colors = [Colors.blue, Colors.pink, Colors.grey];
                          final total = _patientsByGender.fold<int>(0, (sum, item) => sum + (item['count'] as int));
                          final percentage = ((e.value['count'] / total) * 100).toStringAsFixed(1);
                          return PieChartSectionData(
                            value: e.value['count'].toDouble(),
                            title: '$percentage%',
                            color: colors[e.key % colors.length],
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _patientsByGender.asMap().entries.map((e) {
                        final colors = [Colors.blue, Colors.pink, Colors.grey];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: colors[e.key % colors.length], borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${e.value['gender']}: ${e.value['count']}', style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        );
                      }).toList(),
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