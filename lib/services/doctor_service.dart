import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'appointment_service.dart';

class DoctorService {
  static final DoctorService instance = DoctorService._init();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService.instance;
  final AppointmentService _appointmentService = AppointmentService.instance;
  
  DoctorService._init();
  
  /// Get patient name from profiles collection - FULLY FIXED
  Future<String> _getPatientName(String userId) async {
    try {
      print('🔍 Fetching patient name for userId: $userId');
      
      // PRIMARY: Try profiles collection (YOUR MAIN PATIENT COLLECTION)
      final profileDoc = await _firestore.collection('profiles').doc(userId).get();
      if (profileDoc.exists) {
        final data = profileDoc.data();
        print('   📄 Profile doc exists. Data keys: ${data?.keys}');
        
        if (data?['name'] != null) {
          final name = data!['name'].toString();
          print('   ✅ Found name in profiles: $name');
          return name;
        }
      } else {
        print('   ❌ Profile doc does NOT exist');
      }
      
      // Fallback: Try users collection (handles both 'name' and 'fullName' fields)
      print('   🔄 Trying users collection...');
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        print('   📄 User doc exists. Data keys: ${data?.keys}');
        
        // ✅ FIX: Check for BOTH 'name' AND 'fullName' fields
        if (data?['name'] != null) {
          final name = data!['name'].toString();
          print('   ✅ Found name in users: $name');
          return name;
        } else if (data?['fullName'] != null) {
          final name = data!['fullName'].toString();
          print('   ✅ Found fullName in users: $name');
          return name;
        }
        
        // Check if this is a doctor account
        if (data?['userType'] == 'doctor') {
          print('   ⚠️ WARNING: This is a DOCTOR account, not a patient!');
          print('   ⚠️ Doctor accounts should not be booking appointments as patients');
          // Still return the doctor's name for display
          if (data?['fullName'] != null) {
            return data!['fullName'].toString() + ' (Doctor)';
          }
        }
      } else {
        print('   ❌ User doc does NOT exist');
      }
      
      // Last resort: Try patient_profiles collection
      print('   🔄 Trying patient_profiles collection...');
      final patientDoc = await _firestore.collection('patient_profiles').doc(userId).get();
      if (patientDoc.exists) {
        final data = patientDoc.data();
        print('   📄 Patient profile doc exists. Data keys: ${data?.keys}');
        
        if (data?['name'] != null) {
          final name = data!['name'].toString();
          print('   ✅ Found name in patient_profiles: $name');
          return name;
        } else if (data?['fullName'] != null) {
          final name = data!['fullName'].toString();
          print('   ✅ Found fullName in patient_profiles: $name');
          return name;
        }
      } else {
        print('   ❌ Patient profile doc does NOT exist');
      }
      
      print('   ⚠️ No patient name found in any collection for userId: $userId');
      return 'Unknown User'; // Better default than 'Patient'
    } catch (e) {
      print('   ❌ ERROR fetching patient name for $userId: $e');
      return 'Error Loading Name';
    }
  }
  
  /// Get all appointments for a specific doctor WITH patient names
  /// doctorId parameter should be the doctor's UID (we'll fetch the doctorId from their profile)
  Future<List<Map<String, dynamic>>> getDoctorAppointments(
    String doctorUid, {
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // First, get the doctor's doctorId from their profile
      print('🔍 Fetching doctor profile for UID: $doctorUid');
      final doctorDoc = await _firestore.collection('users').doc(doctorUid).get();
      
      if (!doctorDoc.exists) {
        print('❌ Doctor profile not found for UID: $doctorUid');
        return [];
      }
      
      final doctorData = doctorDoc.data()!;
      final doctorId = doctorData['doctorId'] as String?;
      
      if (doctorId == null) {
        print('❌ No doctorId found in doctor profile');
        return [];
      }
      
      print('✅ Found doctorId: $doctorId for UID: $doctorUid');
      
      // Now query appointments using the doctorId
      Query<Map<String, dynamic>> query = _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId);
      
      // Apply status filter
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      
      final snapshot = await query.get();
      
      print('📊 Query returned ${snapshot.docs.length} appointments with doctorId: $doctorId, status: ${status ?? "any"}');
      
      // Fetch appointments with patient names
      final List<Map<String, dynamic>> appointments = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String;
        final aptDate = (data['appointmentDate'] as Timestamp).toDate();
        
        print('   📅 Appointment: ${doc.id}');
        print('      Date: $aptDate');
        print('      Status: ${data['status']}');
        print('      UserId: $userId');
        
        // Apply date filters in memory if provided
        if (startDate != null && aptDate.isBefore(startDate)) {
          print('      ❌ Skipped: Before startDate');
          continue;
        }
        if (endDate != null && aptDate.isAfter(endDate)) {
          print('      ❌ Skipped: After endDate');
          continue;
        }
        
        // Fetch patient name
        final patientName = await _getPatientName(userId);
        
        appointments.add({
          'id': doc.id,
          'userId': userId,
          'patientName': patientName,
          'doctorId': data['doctorId'],
          'doctorName': data['doctorName'],
          'specialization': data['specialization'],
          'appointmentDate': aptDate.toIso8601String(),
          'timeSlot': data['timeSlot'],
          'status': data['status'],
          'reason': data['reason'] ?? '',
          'notes': data['notes'] ?? '',
          'rejectionReason': data['rejectionReason'] ?? '',
          'createdAt': data['createdAt'],
          'updatedAt': data['updatedAt'],
          'healthSummarySnapshot': data['healthSummarySnapshot'],
        });
        
        print('      ✅ Added to list with patient name: $patientName');
      }
      
      // Sort by appointment date
      appointments.sort((a, b) {
        final dateA = DateTime.parse(a['appointmentDate']);
        final dateB = DateTime.parse(b['appointmentDate']);
        return dateA.compareTo(dateB);
      });
      
      print('📊 Returning ${appointments.length} appointments after filtering\n');
      return appointments;
    } catch (e) {
      print('❌ Error fetching doctor appointments: $e');
      return [];
    }
  }
  
  /// Get pending appointments (waiting for doctor approval) - ONLY PENDING STATUS
  Future<List<Map<String, dynamic>>> getPendingAppointments(String doctorId) async {
    print('\n🔍 === FETCHING PENDING APPOINTMENTS ===');
    final pendingAppts = await getDoctorAppointments(
      doctorId,
      status: 'pending',
    );
    
    print('✅ Found ${pendingAppts.length} PENDING appointments');
    if (pendingAppts.isEmpty) {
      print('   ℹ️ No pending appointments - all have been approved or rejected');
      print('   💡 TIP: Book a NEW appointment from patient side to test approval flow');
    } else {
      for (var apt in pendingAppts) {
        print('   - ${apt['patientName']} on ${apt['appointmentDate']} at ${apt['timeSlot']}');
      }
    }
    print('');
    
    return pendingAppts;
  }
  
  /// Get today's appointments - ALL STATUSES FOR TODAY
  Future<List<Map<String, dynamic>>> getTodayAppointments(String doctorId) async {
    print('\n🔍 === FETCHING TODAY APPOINTMENTS ===');
    
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    print('📅 Today is: ${DateFormat('EEEE, MMMM d, yyyy').format(now)}');
    print('📅 Current time: ${now.toString()}');
    print('📅 Looking for appointments between:');
    print('   Start: $startOfDay');
    print('   End: $endOfDay');
    
    // Get ALL appointments (no status filter, no date filter in query)
    final allAppts = await getDoctorAppointments(doctorId);
    
    // Filter in memory for today only
    final todayAppts = allAppts.where((apt) {
      final aptDate = DateTime.parse(apt['appointmentDate']);
      final isTodayDate = aptDate.year == now.year && 
                          aptDate.month == now.month && 
                          aptDate.day == now.day;
      return isTodayDate;
    }).toList();
    
    print('✅ Found ${todayAppts.length} appointments for TODAY');
    if (todayAppts.isEmpty) {
      print('   ℹ️ No appointments scheduled for today (${DateFormat('MMM d').format(now)})');
      print('   💡 Your appointments are from:');
      for (var apt in allAppts) {
        final aptDate = DateTime.parse(apt['appointmentDate']);
        print('      - ${apt['patientName']}: ${DateFormat('MMM d, yyyy').format(aptDate)}');
      }
    } else {
      for (var apt in todayAppts) {
        print('   - ${apt['patientName']} at ${apt['timeSlot']} (Status: ${apt['status']})');
      }
    }
    print('');
    
    return todayAppts;
  }
  
  /// Get upcoming appointments (future dates, not today) - ONLY APPROVED
  Future<List<Map<String, dynamic>>> getUpcomingAppointments(String doctorId) async {
    print('\n🔍 === FETCHING UPCOMING APPOINTMENTS ===');
    
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
    final futureLimit = now.add(const Duration(days: 90)); // Next 90 days
    
    print('📅 Current date: ${DateFormat('MMM d, yyyy').format(now)}');
    print('📅 Looking for APPROVED appointments from tomorrow onwards:');
    print('   Start: ${DateFormat('MMM d, yyyy').format(tomorrow)}');
    print('   End: ${DateFormat('MMM d, yyyy').format(futureLimit)}');
    
    // Get ALL approved appointments
    final allApprovedAppts = await getDoctorAppointments(
      doctorId,
      status: 'approved',
    );
    
    print('📊 Total approved appointments: ${allApprovedAppts.length}');
    
    // Filter for future dates (tomorrow onwards)
    final upcomingAppts = allApprovedAppts.where((apt) {
      final aptDate = DateTime.parse(apt['appointmentDate']);
      // Must be after today (tomorrow or later) and within 90 days
      return aptDate.isAfter(DateTime(now.year, now.month, now.day, 23, 59, 59)) &&
             aptDate.isBefore(futureLimit);
    }).toList();
    
    print('✅ Found ${upcomingAppts.length} UPCOMING approved appointments');
    if (upcomingAppts.isEmpty) {
      print('   ℹ️ No upcoming approved appointments in the next 90 days');
      if (allApprovedAppts.isNotEmpty) {
        print('   💡 All approved appointments are in the past:');
        for (var apt in allApprovedAppts) {
          final aptDate = DateTime.parse(apt['appointmentDate']);
          final daysAgo = now.difference(aptDate).inDays;
          print('      - ${apt['patientName']}: ${DateFormat('MMM d, yyyy').format(aptDate)} ($daysAgo days ago)');
        }
      }
    } else {
      for (var apt in upcomingAppts) {
        final aptDate = DateTime.parse(apt['appointmentDate']);
        final daysAway = aptDate.difference(now).inDays;
        print('   - ${apt['patientName']} on ${DateFormat('MMM d, yyyy').format(aptDate)} (in $daysAway days) at ${apt['timeSlot']}');
      }
    }
    print('');
    
    return upcomingAppts;
  }
  
  /// Approve appointment
  Future<void> approveAppointment(String appointmentId, String doctorUid) async {
    try {
      print('🔍 Approving appointment: $appointmentId for doctor UID: $doctorUid');
      
      // Get doctor's doctorId from their profile
      final doctorDoc = await _firestore.collection('users').doc(doctorUid).get();
      if (!doctorDoc.exists) {
        throw Exception('Doctor profile not found');
      }
      
      final doctorId = doctorDoc.data()!['doctorId'] as String?;
      if (doctorId == null) {
        throw Exception('Doctor ID not found in profile');
      }
      
      print('✅ Doctor has doctorId: $doctorId');
      
      final appointmentDoc = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();
      
      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }
      
      final data = appointmentDoc.data()!;
      
      print('📋 Appointment doctorId: ${data['doctorId']}');
      
      // Verify this is the correct doctor (compare doctorId, not UID)
      if (data['doctorId'] != doctorId) {
        throw Exception('Unauthorized: This appointment is not assigned to you');
      }
      
      // Update status to approved
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Appointment approved: $appointmentId - Status changed to "approved"');
      
      // ========== SEND NOTIFICATIONS (SAFELY) ==========
      try {
        final doctorName = data['doctorName'] ?? 'Doctor';
        final appointmentDate = (data['appointmentDate'] as Timestamp).toDate();
        final timeSlot = data['timeSlot'] ?? '';

        // Send instant confirmation notification
        await _notificationService.showNotification(
          title: '✅ Appointment Confirmed',
          body: '$doctorName approved your appointment for ${appointmentDate.day}/${appointmentDate.month} at $timeSlot',
        );

        // Schedule reminders (24h before + 2h before)
        await _notificationService.scheduleAppointmentReminder(
          appointmentId: appointmentId,
          doctorName: doctorName,
          appointmentDate: appointmentDate,
        );

        print('📲 Notifications sent and scheduled for appointment: $appointmentId');
      } catch (notificationError) {
        // Don't fail the approval if notifications fail
        print('⚠️ Notification error (non-critical): $notificationError');
        print('   Appointment was approved successfully despite notification failure');
      }
      // ==================================================
      
    } catch (e) {
      print('❌ Error approving appointment: $e');
      rethrow;
    }
  }
  
  /// Reject appointment with reason
  Future<void> rejectAppointment(
    String appointmentId,
    String doctorUid,
    String rejectionReason,
  ) async {
    if (rejectionReason.trim().isEmpty) {
      throw Exception('Rejection reason is required');
    }
    
    try {
      print('🔍 Rejecting appointment: $appointmentId for doctor UID: $doctorUid');
      
      // Get doctor's doctorId from their profile
      final doctorDoc = await _firestore.collection('users').doc(doctorUid).get();
      if (!doctorDoc.exists) {
        throw Exception('Doctor profile not found');
      }
      
      final doctorId = doctorDoc.data()!['doctorId'] as String?;
      if (doctorId == null) {
        throw Exception('Doctor ID not found in profile');
      }
      
      print('✅ Doctor has doctorId: $doctorId');
      
      final appointmentDoc = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();
      
      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }
      
      final data = appointmentDoc.data()!;
      
      print('📋 Appointment doctorId: ${data['doctorId']}');
      
      // Verify this is the correct doctor (compare doctorId, not UID)
      if (data['doctorId'] != doctorId) {
        throw Exception('Unauthorized: This appointment is not assigned to you');
      }
      
      // Update status to rejected
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': 'rejected',
        'rejectionReason': rejectionReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Appointment rejected: $appointmentId - Status changed to "rejected"');
      
      // ========== SEND REJECTION NOTIFICATION (SAFELY) ==========
      try {
        final doctorName = data['doctorName'] ?? 'Doctor';

        // Send rejection notification
        await _notificationService.showNotification(
          title: '❌ Appointment Not Available',
          body: 'Dr. $doctorName couldn\'t accept your appointment. Reason: $rejectionReason',
        );

        print('📲 Rejection notification sent for appointment: $appointmentId');
      } catch (notificationError) {
        print('⚠️ Notification error (non-critical): $notificationError');
        print('   Appointment was rejected successfully despite notification failure');
      }
      // ==========================================================
      
      // Trigger grace period and recommendations
      await _appointmentService.rejectAppointment(appointmentId, rejectionReason);
      
    } catch (e) {
      print('❌ Error rejecting appointment: $e');
      rethrow;
    }
  }
  
  /// Mark appointment as completed
  Future<void> completeAppointment(String appointmentId, String doctorUid) async {
    try {
      print('🔍 Completing appointment: $appointmentId for doctor UID: $doctorUid');
      
      // Get doctor's doctorId from their profile
      final doctorDoc = await _firestore.collection('users').doc(doctorUid).get();
      if (!doctorDoc.exists) {
        throw Exception('Doctor profile not found');
      }
      
      final doctorId = doctorDoc.data()!['doctorId'] as String?;
      if (doctorId == null) {
        throw Exception('Doctor ID not found in profile');
      }
      
      final appointmentDoc = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();
      
      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }
      
      final data = appointmentDoc.data()!;
      
      // Verify this is the correct doctor (compare doctorId, not UID)
      if (data['doctorId'] != doctorId) {
        throw Exception('Unauthorized');
      }
      
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Appointment completed: $appointmentId');
      
    } catch (e) {
      print('❌ Error completing appointment: $e');
      rethrow;
    }
  }
  
  /// Get patient information for an appointment
  Future<Map<String, dynamic>?> getPatientInfo(String userId) async {
    try {
      // Try profiles collection (YOUR MAIN COLLECTION)
      var doc = await _firestore.collection('profiles').doc(userId).get();
      if (doc.exists) return doc.data();
      
      // Try users collection
      doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) return doc.data();
      
      // Try patient_profiles collection
      doc = await _firestore.collection('patient_profiles').doc(userId).get();
      if (doc.exists) return doc.data();
      
      return null;
    } catch (e) {
      print('Error fetching patient info: $e');
      return null;
    }
  }
  
  /// Get patient's appointment history with this doctor
  Future<List<Map<String, dynamic>>> getPatientHistory(
    String userId,
    String doctorId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .where('doctorId', isEqualTo: doctorId)
          .where('status', isEqualTo: 'completed')
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error fetching patient history: $e');
      return [];
    }
  }
  
  /// Get doctor statistics
  Future<Map<String, dynamic>> getDoctorStats(String doctorId) async {
    try {
      final appointments = await getDoctorAppointments(doctorId);
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      return {
        'total': appointments.length,
        'pending': appointments.where((a) => a['status'] == 'pending').length,
        'approved': appointments.where((a) => a['status'] == 'approved').length,
        'completed': appointments.where((a) => a['status'] == 'completed').length,
        'rejected': appointments.where((a) => a['status'] == 'rejected').length,
        'today': appointments.where((a) {
          final aptDate = DateTime.parse(a['appointmentDate']);
          return aptDate.year == now.year && 
                 aptDate.month == now.month && 
                 aptDate.day == now.day;
        }).length,
        'thisWeek': appointments.where((a) {
          final aptDate = DateTime.parse(a['appointmentDate']);
          final weekFromNow = now.add(const Duration(days: 7));
          return aptDate.isAfter(today.subtract(const Duration(seconds: 1))) && 
                 aptDate.isBefore(weekFromNow);
        }).length,
      };
    } catch (e) {
      print('Error calculating doctor stats: $e');
      return {
        'total': 0,
        'pending': 0,
        'approved': 0,
        'completed': 0,
        'rejected': 0,
        'today': 0,
        'thisWeek': 0,
      };
    }
  }
  
  /// Add notes to appointment (doctor's notes)
  Future<void> addDoctorNotes(
    String appointmentId,
    String doctorId,
    String notes,
  ) async {
    try {
      await _firestore.collection('appointments').doc(appointmentId).update({
        'doctorNotes': notes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Doctor notes added to appointment: $appointmentId');
    } catch (e) {
      print('❌ Error adding doctor notes: $e');
      rethrow;
    }
  }
  
  /// Get appointment details with patient info
  Future<Map<String, dynamic>?> getAppointmentDetails(String appointmentId) async {
    try {
      final appointmentDoc = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();
      
      if (!appointmentDoc.exists) return null;
      
      final appointmentData = appointmentDoc.data()!;
      
      // Get patient info
      final patientInfo = await getPatientInfo(appointmentData['userId']);
      
      return {
        'appointment': {
          'id': appointmentDoc.id,
          ...appointmentData,
        },
        'patient': patientInfo,
      };
    } catch (e) {
      print('Error fetching appointment details: $e');
      return null;
    }
  }
}