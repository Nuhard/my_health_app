import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/doctor_service.dart';
import '../services/doctor_auth_service.dart';
import '../services/data_sharing_service.dart';
import '../widgets/patient_data_view.dart';
import 'doctor_feedback_screen.dart';





class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen>
    with SingleTickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  final DoctorService _doctorService = DoctorService.instance;
  final DoctorAuthService _authService = DoctorAuthService.instance;
  final DataSharingService _dataSharingService = DataSharingService.instance;

  late TabController _tabController;

  Map<String, dynamic>? _doctorProfile;
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _pendingAppointments = [];
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = []; 

  bool _isLoading = true;
  String? _errorMessage;


@override
void initState() {
  super.initState();
  _tabController = TabController(length: 4, vsync: this); 
  _loadDoctorData();
}

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


/// Helper to parse appointmentDate safely
DateTime parseAppointmentDate(dynamic appointmentDate) {
  if (appointmentDate == null) return DateTime.now();
  if (appointmentDate is Timestamp) return appointmentDate.toDate();
  if (appointmentDate is String) return DateTime.parse(appointmentDate);
  return DateTime.now();
}

// ✅ ADD THIS NEW METHOD RIGHT HERE:
/// Parse complete appointment date and time from appointment data
/// Combines appointmentDate (which is always midnight) with timeSlot string
DateTime _parseCompleteAppointmentDateTime(Map<String, dynamic> appointment) {
  // Get the base date (will be midnight: 12:00 AM)
  final appointmentDate = parseAppointmentDate(appointment['appointmentDate']);
  final timeSlot = appointment['timeSlot']?.toString() ?? '';
  
  print('🔧 Parsing appointment time...');
  print('   Base date: $appointmentDate');
  print('   Time slot: $timeSlot');
  
  // Extract hour and minute from timeSlot
  // Handles formats: "05:00 PM", "11:00 AM", "05:00 PM - 05:30 PM"
  if (timeSlot.isNotEmpty) {
    try {
      // Remove any end time if present (e.g., "05:00 PM - 05:30 PM" → "05:00 PM")
      String startTime = timeSlot;
      if (timeSlot.contains(' - ')) {
        startTime = timeSlot.split(' - ')[0].trim();
      }
      
      // Parse time string
      // Handle both "05:00 PM" and "5:00 PM" formats
      final parts = startTime.split(' '); // ["05:00", "PM"]
      if (parts.length < 2) {
        print('   ⚠️ Invalid time format, using midnight');
        return appointmentDate;
      }
      
      final timePart = parts[0]; // "05:00"
      final period = parts[1].toUpperCase(); // "PM"
      
      final hourMinute = timePart.split(':'); // ["05", "00"]
      if (hourMinute.length < 2) {
        print('   ⚠️ Invalid hour:minute format, using midnight');
        return appointmentDate;
      }
      
      int hour = int.parse(hourMinute[0]);
      final minute = int.parse(hourMinute[1]);
      
      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12; // 5 PM → 17
      } else if (period == 'AM' && hour == 12) {
        hour = 0; // 12 AM → 0
      }
      
      // Create complete DateTime with parsed time
      final completeDateTime = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
        hour,
        minute,
      );
      
      print('   ✅ Parsed complete time: $completeDateTime');
      return completeDateTime;
      
    } catch (e) {
      print('   ❌ Error parsing time slot: $e');
      print('   Using midnight as fallback');
      return appointmentDate;
    }
  }
  
  print('   ⚠️ No time slot found, using midnight');
  return appointmentDate;
}










  Future<void> _loadDoctorData() async {
    if (user == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _doctorProfile = await _authService.getDoctorProfile(user!.uid);
      _statistics = await _doctorService.getDoctorStats(user!.uid);

      // Load ONLY pending appointments (status = 'pending')
      _pendingAppointments = await _doctorService.getPendingAppointments(user!.uid);

      // Load today's appointments
      _todayAppointments = await _doctorService.getTodayAppointments(user!.uid);

      // Load upcoming APPROVED appointments only
      _upcomingAppointments = await _doctorService.getUpcomingAppointments(user!.uid);
 _pastAppointments = await _getPastAppointments(user!.uid);
      _pendingAppointments = _sortAppointmentsByPriority(_pendingAppointments);

      print('✅ Loaded: ${_pendingAppointments.length} pending, ${_todayAppointments.length} today, ${_upcomingAppointments.length} upcoming');
    } catch (e) {
      print('❌ Error loading data: $e');
      _errorMessage = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

// Add this method in doctor_dashboard_screen.dart
// Place it after the _loadDoctorData() method

/// Get past/completed appointments
Future<List<Map<String, dynamic>>> _getPastAppointments(String doctorUid) async {
  print('\n🔍 === FETCHING PAST APPOINTMENTS ===');
  
  try {
    // Get doctor's doctorId from profile
    final doctorDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(doctorUid)
        .get();
    
    if (!doctorDoc.exists) {
      print('❌ Doctor profile not found');
      return [];
    }
    
    final doctorId = doctorDoc.data()!['doctorId'] as String?;
    if (doctorId == null) {
      print('❌ No doctorId found');
      return [];
    }
    
    print('✅ Doctor has doctorId: $doctorId');
    
    // Get completed appointments
    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: 'completed')
        .orderBy('appointmentDate', descending: true) // Most recent first
        .limit(50) // Limit to last 50 completed appointments
        .get();
    
    print('📊 Found ${snapshot.docs.length} completed appointments');
    
    final List<Map<String, dynamic>> appointments = [];
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final userId = data['userId'] as String;
      
      print('👤 Fetching patient details for userId: $userId');
      
      // Fetch patient name (reuse existing method)
      String patientName = 'Patient';
      try {
        final profileDoc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(userId)
            .get();
        if (profileDoc.exists && profileDoc.data()?['name'] != null) {
          patientName = profileDoc.data()!['name'].toString();
        } else {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          if (userDoc.exists) {
            patientName = userDoc.data()?['name']?.toString() ?? 
                         userDoc.data()?['fullName']?.toString() ?? 
                         'Patient';
          }
        }
      } catch (e) {
        print('⚠️ Error fetching patient name: $e');
      }
      
      appointments.add({
        'id': doc.id,
        'userId': userId,
        'patientName': patientName,
        'doctorId': data['doctorId'],
        'doctorName': data['doctorName'],
        'specialization': data['specialization'],
        'appointmentDate': (data['appointmentDate'] as Timestamp)
            .toDate()
            .toIso8601String(),
        'timeSlot': data['timeSlot'],
        'status': data['status'],
        'reason': data['reason'] ?? '',
        'notes': data['notes'] ?? '',
        'doctorNotes': data['doctorNotes'] ?? '',
        'completedAt': data['completedAt'],
        'createdAt': data['createdAt'],
        'updatedAt': data['updatedAt'],
        'healthSummarySnapshot': data['healthSummarySnapshot'],
      });
    }
    
    print('✅ Returning ${appointments.length} past appointments\n');
    return appointments;
  } catch (e) {
    print('❌ Error fetching past appointments: $e');
    return [];
  }
}







  List<Map<String, dynamic>> _sortAppointmentsByPriority(List<Map<String, dynamic>> appointments) {
    return appointments..sort((a, b) {
      final aPriority = _getAppointmentPriority(a);
      final bPriority = _getAppointmentPriority(b);
      return bPriority.compareTo(aPriority);
    });
  }

  int _getAppointmentPriority(Map<String, dynamic> appointment) {
    final healthContext = appointment['healthSummarySnapshot'];
    if (healthContext == null) return 0;

    try {
      final Map<String, dynamic> summary = healthContext is String
          ? json.decode(healthContext)
          : healthContext;

      final criticalAlerts = summary['criticalAlerts'] as List<dynamic>? ?? [];
      final symptomPatterns = summary['symptomPatterns'] as List<dynamic>? ?? [];

      if (criticalAlerts.isNotEmpty) return 3; // Urgent
      if (symptomPatterns.length > 3) return 2; // High
      return 1; // Normal
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Please login as a doctor'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/doctor-login'),
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.teal.shade700,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Doctor Portal', style: TextStyle(fontSize: 20)),
            if (_doctorProfile != null && _doctorProfile!['specialization'] != null)
              Text(
                _doctorProfile!['specialization'].toString(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
              ),
          ],
        ),
        actions: [
              IconButton(
      icon: Badge(
        label: Text(_statistics != null ? _statistics!['completed'].toString() : '0'),
        isLabelVisible: (_statistics?['completed'] ?? 0) > 0,
        child: const Icon(Icons.star_rate),
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DoctorFeedbackScreen(),
          ),
        );
      },
      tooltip: 'My Feedback',
    ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDoctorData,
          ),
          PopupMenuButton(
            icon: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                _doctorProfile != null && _doctorProfile!['fullName'] != null
                    ? _doctorProfile!['fullName'].toString()[0].toUpperCase()
                    : 'D',
                style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.pop(context);
                    _showProfileDialog();
                  },
                ),
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _authService.signOut();
                    if (mounted) Navigator.pushReplacementNamed(context, '/doctor-login');
                  },
                ),
              ),
            ],
          ),
          
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildStatisticsCards(),
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: Colors.teal.shade700,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.teal.shade700,
                        tabs: [
                          Tab(
                            icon: Badge(
                              label: Text('${_pendingAppointments.length}'),
                              isLabelVisible: _pendingAppointments.isNotEmpty,
                              child: const Icon(Icons.schedule),
                            ),
                            text: 'Pending',
                          ),
                          Tab(
                            icon: Badge(
                              label: Text('${_todayAppointments.length}'),
                              isLabelVisible: _todayAppointments.isNotEmpty,
                              child: const Icon(Icons.today),
                            ),
                            text: 'Today',
                          ),
                          Tab(
                            icon: Badge(
                              label: Text('${_upcomingAppointments.length}'),
                              isLabelVisible: _upcomingAppointments.isNotEmpty,
                              child: const Icon(Icons.calendar_month),
                            ),
                            text: 'Upcoming',
                          ),
                          Tab(
        icon: Badge(
          label: Text('${_pastAppointments.length}'),
          isLabelVisible: _pastAppointments.isNotEmpty,
          child: const Icon(Icons.history),
        ),
        text: 'Past',
      ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAppointmentList(_pendingAppointments, isPending: true),
                          _buildAppointmentList(_todayAppointments),
                          _buildAppointmentList(_upcomingAppointments),
                           _buildAppointmentList(_pastAppointments, isPast: true),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildAppointmentList(List<Map<String, dynamic>> appointments, {bool isPending = false,bool isPast = false,}) {
  if (appointments.isEmpty) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isPast ? Icons.history : Icons.event_available, 
          size: 80, 
          color: Colors.grey.shade300
        ),
        const SizedBox(height: 16),
        Text(
          isPending 
              ? 'No Pending Appointments'
              : isPast
                  ? 'No Past Appointments' 
                  : 'No Appointments',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) => _buildAppointmentCard(appointments[index], isPending: isPending,isPast: isPast,),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment, {bool isPending = false, bool isPast = false,}) {
    final date = parseAppointmentDate(appointment['appointmentDate']);
    final formattedDate = DateFormat('MMM dd, yyyy').format(date);
    final timeSlot = appointment['timeSlot']?.toString() ?? 'N/A';
    
    final patientName = appointment['patientName']?.toString() ?? 'Patient';
    final userId = appointment['userId']?.toString() ?? '';
    final reason = appointment['reason']?.toString() ?? 'No reason provided';
    final doctorNotes = appointment['doctorNotes']?.toString() ?? '';
    final status = appointment['status']?.toString() ?? 'pending';
    final priority = _getAppointmentPriority(appointment);
    final priorityColor = priority == 3 ? Colors.red : priority == 2 ? Colors.orange : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isPending ? BorderSide(color: priorityColor.withOpacity(0.3), width: 2)
        : isPast
            ? BorderSide(color: Colors.green.withOpacity(0.2), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showAppointmentDetails(appointment),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row - Patient info, date, status
              Row(
                children: [
                  // Patient Avatar
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isPast ? Colors.green.shade100 : Colors.teal.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPast ? Icons.check_circle : Icons.person,
                      color: isPast ? Colors.green.shade700 : Colors.teal.shade700,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Patient Name & Date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: const TextStyle(
                            fontSize: 15, 
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              formattedDate,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time, size: 11, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              timeSlot,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Status Badge
                  if (isPending && priority > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        priority == 3 ? 'URGENT' : priority == 2 ? 'HIGH' : 'NORMAL',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    )
                  else if (isPast) 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'COMPLETED',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    )
                  else
                    _buildStatusBadge(status),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Reason Section - Compact
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.medical_services, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Doctor Notes - Only if past and has notes
              if (isPast && doctorNotes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.note_alt, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doctorNotes.length > 80 
                                  ? '${doctorNotes.substring(0, 80)}...' 
                                  : doctorNotes,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Health Context - Compact
              if (appointment['healthSummarySnapshot'] != null) ...[
                const SizedBox(height: 6),
                _buildHealthContextPreview(appointment['healthSummarySnapshot']),
              ],
              
              // Data Sharing Status
              if (status == 'approved') ...[
                const SizedBox(height: 6),
                _buildDataSharingStatusBadge(appointment),
              ],
              
              // Action Buttons - Compact for pending
              if (isPending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showRejectDialog(appointment),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Reject', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _approveAppointment(appointment),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


// Add this method to _DoctorDashboardScreenState in doctor_dashboard_screen.dart

/// Build data sharing status badge for appointment card
Widget _buildDataSharingStatusBadge(Map<String, dynamic> appointment) {
  final status = appointment['status']?.toString() ?? 'pending';
  
  // Only show for approved appointments
  if (status != 'approved') {
    return const SizedBox.shrink();
  }
  
  final appointmentId = appointment['id']?.toString() ?? '';
  final patientId = appointment['userId']?.toString() ?? '';
  
  if (appointmentId.isEmpty || patientId.isEmpty) {
    return const SizedBox.shrink();
  }
  
  return FutureBuilder<String>(
    future: _dataSharingService.getPermissionStatus(
      appointmentId: appointmentId,
      patientId: patientId,
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox.shrink();
      }
      
      final permissionStatus = snapshot.data!;
      
      Color statusColor;
      IconData statusIcon;
      String statusText;
      
      switch (permissionStatus) {
        case 'approved':
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          statusText = 'Data Shared';
          break;
        case 'rejected':
          statusColor = Colors.orange;
          statusIcon = Icons.folder_off;
          statusText = 'Manual Data';
          break;
        default:
          statusColor = Colors.blue;
          statusIcon = Icons.pending;
          statusText = 'Pending';
      }
      
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ),
      );
    },
  );
}



  Widget _buildHealthContextPreview(dynamic healthSnapshot) {
  try {
    final Map<String, dynamic> summary = healthSnapshot is String 
        ? json.decode(healthSnapshot) 
        : healthSnapshot as Map<String, dynamic>;

    final criticalAlerts = summary['criticalAlerts'] as List<dynamic>? ?? [];
    final symptomPatterns = summary['symptomPatterns'] as List<dynamic>? ?? [];
    final medicationAdherence = summary['medicationAdherence'] as Map<String, dynamic>? ?? {};

    if (criticalAlerts.isEmpty && symptomPatterns.isEmpty && medicationAdherence.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (criticalAlerts.isNotEmpty)
                  _buildHealthChip('${criticalAlerts.length} Alerts', Colors.red, Icons.warning_amber_rounded),
                if (symptomPatterns.isNotEmpty)
                  _buildHealthChip('${symptomPatterns.length} Symptoms', Colors.orange, Icons.sick),
                if (medicationAdherence['adherenceRate'] != null)
                  _buildHealthChip('${medicationAdherence['adherenceRate']}%', Colors.green, Icons.medication),
              ],
            ),
          ),
        ],
      ),
    );
  } catch (e) {
    print('❌ Error parsing health context: $e');
    return const SizedBox.shrink();
  }
}

  Widget _buildHealthChip(String label, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3), width: 0.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label, 
          style: TextStyle(
            fontSize: 10, 
            color: color, 
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'approved':
        color = Colors.green;
        break;
      case 'rejected':
        color = Colors.red;
        break;
      case 'completed':
        color = Colors.blue;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _approveAppointment(Map<String, dynamic> appointment) async {
    try {
      // Immediately update local state to remove from pending list
      setState(() {
        _pendingAppointments.removeWhere((app) => app['id'] == appointment['id']);
      });

      // ✅ FIXED: Use DoctorService with correct parameters
      await _doctorService.approveAppointment(
        appointment['id'].toString(),
        user!.uid, // Pass doctor ID
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Appointment approved!'), backgroundColor: Colors.green),
        );
        // Reload all data to get updated statistics and other tabs
        await _loadDoctorData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        // Reload data on error to restore consistent state
        await _loadDoctorData();
      }
    }
  }

void _showRejectDialog(Map<String, dynamic> appointment) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      // ✅ FIX: Use a named builder context so we can close THIS dialog specifically
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Appointment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please provide a reason for rejection:'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'E.g., Schedule conflict...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              // ✅ Use dialogContext to close only this dialog
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide a reason')),
                  );
                  return;
                }

                // ✅ FIX: Close the reject dialog FIRST before doing async work
                Navigator.of(dialogContext).pop();

                // Update local state immediately so UI feels responsive
                setState(() {
                  _pendingAppointments
                      .removeWhere((app) => app['id'] == appointment['id']);
                });

                try {
                  await _doctorService.rejectAppointment(
                    appointment['id'].toString(),
                    user!.uid,
                    reasonController.text.trim(),
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Appointment rejected'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    // ✅ Reload AFTER dialog is fully closed — no stale context issues
                    await _loadDoctorData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    await _loadDoctorData();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }


// Add this method to _DoctorDashboardScreenState in doctor_dashboard_screen.dart

/// Show dialog to confirm appointment completion
void _showCompleteAppointmentDialog(Map<String, dynamic> appointment) {
  final notesController = TextEditingController();
  
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Complete Appointment',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark this appointment as completed?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
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
                      Icon(Icons.person, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appointment['patientName']?.toString() ?? 'Patient',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        appointment['timeSlot']?.toString() ?? 'N/A',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Consultation Notes (Optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any consultation notes...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _completeAppointment(
                appointment,
                notesController.text.trim(),
              );
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Mark Complete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    },
  );
}

/// Complete the appointment
Future<void> _completeAppointment(
  Map<String, dynamic> appointment,
  String notes,
) async {
  try {
    // Show loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Completing appointment...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    // Call the service method
    await _doctorService.completeAppointment(
      appointment['id'].toString(),
      user!.uid,
    );
    
    // Add notes if provided
    if (notes.isNotEmpty) {
      await _doctorService.addDoctorNotes(
        appointment['id'].toString(),
        user!.uid,
        notes,
      );
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Appointment marked as completed!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Reload data to update UI
      await _loadDoctorData();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing appointment: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}







  void _showAppointmentDetails(Map<String, dynamic> appointment) async {
    final date = parseAppointmentDate(appointment['appointmentDate']);
    final patientName = appointment['patientName']?.toString() ?? 'Patient';
    final timeSlot = appointment['timeSlot']?.toString() ?? 'N/A';
    final reason = appointment['reason']?.toString() ?? 'No reason provided';
    final status = appointment['status']?.toString() ?? 'pending';
    final appointmentId = appointment['id']?.toString() ?? '';
    final patientId = appointment['userId']?.toString() ?? '';
    
    // Check data sharing permission status
    String permissionStatus = 'unknown';
    if (appointmentId.isNotEmpty && patientId.isNotEmpty) {
      try {
        permissionStatus = await _dataSharingService.getPermissionStatus(
          appointmentId: appointmentId,
          patientId: patientId,
        );
      } catch (e) {
        print('Error checking permission: $e');
      }
    }
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.teal.shade700),
              const SizedBox(width: 12),
              const Text('Appointment Details'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Patient', patientName),
                _buildDetailRow('Date', DateFormat('dd MMM yyyy').format(date)),
                _buildDetailRow('Time', timeSlot),
                _buildDetailRow('Status', status.toUpperCase()),
                _buildDetailRow('Reason', reason),
                if (appointment['notes'] != null && appointment['notes'].toString().isNotEmpty)
                  _buildDetailRow('Notes', appointment['notes'].toString()),
                
                // Data Sharing Status
                if (status == 'approved') ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        permissionStatus == 'approved' 
                            ? Icons.check_circle 
                            : Icons.pending,
                        color: permissionStatus == 'approved'
                            ? Colors.green
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Data Sharing: ${permissionStatus == 'approved' ? 'Approved' : 'Pending'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: permissionStatus == 'approved'
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      

actions: [
  // View Patient Data Button (only if data sharing approved)
  if (status == 'approved' && permissionStatus == 'approved')
    ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        _showPatientHealthData(appointment);
      },
      icon: const Icon(Icons.medical_information, size: 18),
      label: const Text('View Patient Data'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    ),
  
  // ✅ Complete Appointment Button with validation
  if (status == 'approved')
    _buildCompleteButton(appointment),
  
  TextButton(
    onPressed: () => Navigator.pop(context),
    child: const Text('Close'),
  ),
],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
/// Build complete button with validation
Widget _buildCompleteButton(Map<String, dynamic> appointment) {
  final canComplete = _canCompleteAppointment(appointment);
  
  if (canComplete) {
    // ✅ ENABLED: Can complete
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        _showCompleteAppointmentDialog(appointment);
      },
      icon: const Icon(Icons.check_circle_outline, size: 18),
      label: const Text('Mark Complete'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  } else {
    // ❌ DISABLED: Show reason
    final reason = _getCompletionDisabledReason(appointment);
    
    return Tooltip(
      message: reason,
      preferBelow: false,
      child: ElevatedButton.icon(
        onPressed: () {
          // Show dialog explaining why it's disabled
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  const Text('Cannot Complete Yet'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, 
                            color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can mark appointments as completed on the appointment day or within 24 hours after.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.schedule, size: 18),
        label: const Text('Not Available Yet'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade400,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

/// Check if appointment can be marked as completed
/// Option 2: Flexible approach with 24-hour grace period
/// Check if appointment can be marked as completed
/// HYBRID APPROACH: 30 minutes before appointment + 24 hours after
bool _canCompleteAppointment(Map<String, dynamic> appointment) {
  final appointmentDateTime = _parseCompleteAppointmentDateTime(appointment);
  final now = DateTime.now();
  
  // Allow completion 30 minutes before appointment time
  final earlyWindow = appointmentDateTime.subtract(const Duration(minutes: 30));
  
  // Allow completion up to 24 hours after
  final lateWindow = appointmentDateTime.add(const Duration(hours: 24));
  
  // 🔍 DEBUG
  print('═══════════════════════════════════════');
  print('🕒 Appointment Completion Check');
  print('═══════════════════════════════════════');
  print('Current Time: ${DateFormat('MMM dd, yyyy HH:mm').format(now)}');
  print('Appointment Time: ${DateFormat('MMM dd, yyyy HH:mm').format(appointmentDateTime)}');
  print('Time Slot: ${appointment['timeSlot']}');
  print('───────────────────────────────────────');
  print('Early Window (30 min before): ${DateFormat('HH:mm').format(earlyWindow)}');
  print('Late Window (24hr after): ${DateFormat('MMM dd HH:mm').format(lateWindow)}');
  print('───────────────────────────────────────');
  
  final canComplete = now.isAfter(earlyWindow) && now.isBefore(lateWindow);
  
  if (canComplete) {
    print('✅ CAN COMPLETE');
  } else if (now.isBefore(earlyWindow)) {
    final minutesUntil = earlyWindow.difference(now).inMinutes;
    print('❌ TOO EARLY - Wait $minutesUntil minutes');
  } else {
    print('❌ TOO LATE - Grace period expired');
  }
  print('═══════════════════════════════════════\n');
  
  return canComplete;
}

/// Get reason why completion is disabled
String _getCompletionDisabledReason(Map<String, dynamic> appointment) {
  final appointmentDateTime = _parseCompleteAppointmentDateTime(appointment);
  final now = DateTime.now();
  
  final earlyWindow = appointmentDateTime.subtract(const Duration(minutes: 30));
  final lateWindow = appointmentDateTime.add(const Duration(hours: 24));
  
  if (now.isBefore(earlyWindow)) {
    // Too early
    final minutesUntil = earlyWindow.difference(now).inMinutes;
    final hoursUntil = (minutesUntil / 60).floor();
    
    if (minutesUntil < 60) {
      return 'You can mark this appointment as completed in $minutesUntil minute${minutesUntil == 1 ? '' : 's'}.\n\nCompletion is available 30 minutes before the appointment time (${DateFormat('h:mm a').format(appointmentDateTime)}).';
    } else if (hoursUntil < 24) {
      return 'This appointment is at ${DateFormat('h:mm a').format(appointmentDateTime)} (in $hoursUntil hour${hoursUntil == 1 ? '' : 's'}).\n\nCompletion will be available at ${DateFormat('h:mm a').format(earlyWindow)} (30 minutes before).';
    } else {
      final daysUntil = (hoursUntil / 24).ceil();
      return 'This appointment is scheduled in $daysUntil day${daysUntil == 1 ? '' : 's'} at ${DateFormat('h:mm a').format(appointmentDateTime)}.\n\nCompletion will be available on ${DateFormat('MMM dd').format(appointmentDateTime)}.';
    }
  } else if (now.isAfter(lateWindow)) {
    // Too late
    final hoursLate = now.difference(lateWindow).inHours;
    final daysAgo = (hoursLate / 24).ceil() + 1;
    return 'This appointment was $daysAgo day${daysAgo == 1 ? '' : 's'} ago.\n\nThe 24-hour completion window has expired. Please contact support if you need to update this appointment.';
  }
  
  return 'Cannot complete at this time';
}


  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          const Text('Failed to load data'),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadDoctorData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

Widget _buildStatisticsCards() {
  if (_statistics == null) return const SizedBox.shrink();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: Colors.white,
    child: Row(
      children: [
        _buildCompactStatCard('Pending', _statistics!['pending'] ?? 0, Icons.schedule, Colors.orange),
        const SizedBox(width: 8),
        _buildCompactStatCard('Today', _statistics!['today'] ?? 0, Icons.today, Colors.blue),
        const SizedBox(width: 8),
        _buildCompactStatCard('Week', _statistics!['thisWeek'] ?? 0, Icons.calendar_month, Colors.purple),
        const SizedBox(width: 8),
        _buildCompactStatCard('Done', _statistics!['completed'] ?? 0, Icons.check_circle, Colors.green),
        const SizedBox(width: 8),
        _buildCompactStatCard('Total', _statistics!['total'] ?? 0, Icons.assessment, Colors.teal),
      ],
    ),
  );
}

 Widget _buildCompactStatCard(String label, int value, IconData icon, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold, 
              color: color,
            ),
          ),
          Text(
            label, 
            style: TextStyle(
              fontSize: 10, 
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

  void _showProfileDialog() {
    if (_doctorProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile data not available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Doctor Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.teal.shade100,
                  child: Text(
                    _doctorProfile!['fullName'] != null
                        ? _doctorProfile!['fullName'].toString().substring(0, 2).toUpperCase()
                        : 'DR',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildDetailRow('Name', _doctorProfile!['fullName']?.toString() ?? 'N/A'),
              _buildDetailRow('Email', _doctorProfile!['email']?.toString() ?? 'N/A'),
              _buildDetailRow('Specialization', _doctorProfile!['specialization']?.toString() ?? 'N/A'),
              _buildDetailRow('Hospital', _doctorProfile!['hospital']?.toString() ?? 'N/A'),
              if (_doctorProfile!['phone'] != null)
                _buildDetailRow('Phone', _doctorProfile!['phone'].toString()),
              if (_doctorProfile!['licenseNumber'] != null)
                _buildDetailRow('License', _doctorProfile!['licenseNumber'].toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Show patient health data in full-screen dialog
  /// Show patient health data in full-screen dialog
  Future<void> _showPatientHealthData(Map<String, dynamic> appointment) async {
    final patientId = appointment['userId']?.toString() ?? '';
    final patientName = appointment['patientName']?.toString() ?? 'Patient';
    final appointmentId = appointment['id']?.toString() ?? '';
    
    if (patientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID not found')),
      );
      return;
    }
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // Fetch patient profile from Firestore
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(patientId)
          .get();
      
      if (!mounted) return;
      
      if (!profileDoc.exists) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient profile not found')),
        );
        return;
      }
      
      final patientProfile = profileDoc.data()!;
      
      // Close loading dialog
      Navigator.pop(context);
      
      // Show patient data dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.medical_information, color: Colors.teal.shade700, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Patient Health Data',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            patientName,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 24),
                
                // Patient Data View Widget
                Expanded(
                  child: PatientDataView(
                    patientId: patientId,
                    appointmentId: appointmentId,
                    patientProfile: patientProfile,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        print('Error fetching patient profile: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading patient data: $e')),
        );
      }
    }
  }
}