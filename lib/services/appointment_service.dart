import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'sync_service.dart';
import 'enhanced_health_summary_service.dart';
import '../models/enhanced_health_summary.dart';
import 'data_sharing_service.dart';
import 'package:intl/intl.dart';


class AppointmentService {
  static final AppointmentService instance = AppointmentService._init();
  final DatabaseService _localDb = DatabaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService.instance;
  final SyncService _syncService = SyncService.instance;
  final DataSharingService _dataSharingService = DataSharingService.instance;
  // In-memory cache for doctors data
  List<Map<String, dynamic>> _doctors = [];
  DateTime? _doctorsLoadedAt;
  static const int _cacheExpiryMinutes = 60;
  
  // Grace period configuration
  final int gracePeriodHours = 24;
  
  // Appointment status constants
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  AppointmentService._init();

  // ========== DOCTORS DATABASE MANAGEMENT ==========
  
  /// ✅ FIXED: Load doctors from Firestore with correct field names
  Future<void> loadDoctors({bool forceReload = false}) async {
    // Check cache validity
    if (!forceReload && 
        _doctors.isNotEmpty && 
        _doctorsLoadedAt != null &&
        DateTime.now().difference(_doctorsLoadedAt!).inMinutes < _cacheExpiryMinutes) {
      print('📋 Using cached doctors data');
      return;
    }
    
    try {
      // ✅ FIX: Fetch from Firestore doctor_profiles collection
      final snapshot = await _firestore
          .collection('doctor_profiles')
          .where('active', isEqualTo: true)
          .get();
      
      _doctors = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': data['doctorId'] ?? doc.id,
          'name': data['fullName'] ?? 'Unknown Doctor',
          'specialization': data['specialization'] ?? '',
          'rating': (data['rating'] as num?)?.toDouble() ?? 0.0,
          'consultation_fee': (data['consultationFee'] as num?)?.toInt() ?? 0,
          'location': data['location'] ?? '',
          'hospital': data['hospital'] ?? '',
          'phone': data['phone'] ?? '',
          'email': data['email'] ?? '',
          'bio': data['bio'] ?? '',
          'qualifications': data['qualifications'] ?? '',
          'experienceYears': (data['experienceYears'] as num?)?.toInt() ?? 0,
          'expertise': List<String>.from(data['expertise'] ?? []),
          'languages': List<String>.from(data['languages'] ?? []),
          // ✅ FIX: Use correct Firestore field names (camelCase)
          'available_time_slots': List<String>.from(data['availableTimeSlots'] ?? []),
          'available_days': List<String>.from(data['availableDays'] ?? []),
          'verified': data['verified'] ?? false,
          'totalAppointments': (data['totalAppointments'] as num?)?.toInt() ?? 0,
          'totalPatients': (data['totalPatients'] as num?)?.toInt() ?? 0,
        };
      }).toList();
      
      _doctorsLoadedAt = DateTime.now();
      print('✅ Loaded ${_doctors.length} doctors from Firestore');
    } catch (e) {
      print('❌ Error loading doctors from Firestore: $e');
      
      // Fallback to JSON if Firestore fails
      try {
        final jsonString = await rootBundle.loadString('assets/data/doctors_database.json');
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        _doctors = List<Map<String, dynamic>>.from(jsonMap['doctors']);
        _doctorsLoadedAt = DateTime.now();
        print('⚠️ Loaded ${_doctors.length} doctors from JSON fallback');
      } catch (jsonError) {
        print('❌ Error loading doctors from JSON: $jsonError');
        throw Exception('Failed to load doctors: $e');
      }
    }
  }

  /// Get all doctors with optional filtering
  Future<List<Map<String, dynamic>>> getAllDoctors({
    String? specialization,
    double? minRating,
    String? location,
  }) async {
    await loadDoctors();
    
    var filteredDoctors = List<Map<String, dynamic>>.from(_doctors);
    
    // Apply filters
    if (specialization != null) {
      filteredDoctors = filteredDoctors
          .where((doc) => doc['specialization'] == specialization)
          .toList();
    }
    
    if (minRating != null) {
      filteredDoctors = filteredDoctors
          .where((doc) => (doc['rating'] as num) >= minRating)
          .toList();
    }
    
    if (location != null) {
      filteredDoctors = filteredDoctors
          .where((doc) => doc['location']
              .toString()
              .toLowerCase()
              .contains(location.toLowerCase()))
          .toList();
    }
    
    return filteredDoctors;
  }

  /// Get doctor by ID with error handling
  Future<Map<String, dynamic>?> getDoctorById(String doctorId) async {
    await loadDoctors();
    try {
      return _doctors.firstWhere((doc) => doc['id'] == doctorId);
    } catch (e) {
      print('⚠️ Doctor not found: $doctorId');
      return null;
    }
  }

  /// Get doctors by specialization sorted by rating
  Future<List<Map<String, dynamic>>> getDoctorsBySpecialization(
    String specialization, {
    bool sortByRating = true,
  }) async {
    await loadDoctors();
    var doctors = _doctors
        .where((doc) => doc['specialization'] == specialization)
        .toList();
    
    if (sortByRating) {
      doctors.sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
    }
    
    return doctors;
  }

  /// Get unique specializations from doctors database
  Future<List<String>> getSpecializations() async {
    await loadDoctors();
    return _doctors
        .map((doc) => doc['specialization'] as String)
        .toSet()
        .toList()
      ..sort();
  }

  // ========== ✅ NEW: DAY VALIDATION ==========
  
  /// Check if doctor is available on the selected date
  bool isDoctorAvailableOnDate(Map<String, dynamic> doctor, DateTime date) {
    final availableDays = List<String>.from(doctor['available_days'] ?? []);
    
    if (availableDays.isEmpty) {
      print('⚠️ Doctor has no available days configured');
      return true; // Allow booking if not configured
    }
    
    // Get day name from date (e.g., "Monday", "Tuesday")
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final selectedDayName = dayNames[date.weekday - 1];
    
    final isAvailable = availableDays.contains(selectedDayName);
    
    if (!isAvailable) {
      print('⚠️ Doctor not available on $selectedDayName. Available days: $availableDays');
    }
    
    return isAvailable;
  }
  
  /// Get doctor's available days as readable text
  String getDoctorAvailableDaysText(Map<String, dynamic> doctor) {
    final availableDays = List<String>.from(doctor['available_days'] ?? []);
    
    if (availableDays.isEmpty) {
      return 'All days';
    }
    
    if (availableDays.length >= 6) {
      return 'All days';
    }
    
    return availableDays.join(', ');
  }

  // ========== GRACE PERIOD HELPER METHOD ==========
  
  /// ✅ Deactivate grace period after successful booking
  Future<void> _deactivateGracePeriod(String userId) async {
    try {
      // Delete the recommendation document to deactivate grace period
      await _firestore
          .collection('appointment_recommendations')
          .doc(userId)
          .delete();
      
      print('✅ Grace period deactivated for user: $userId');
      
      // Send notification
      if (!kIsWeb) {
        try {
          await _notificationService.showNotification(
            title: '✅ Grace Period Ended',
            body: 'You have successfully booked an appointment!',
          );
        } catch (e) {
          print('⚠️ Failed to send notification: $e');
        }
      }
    } catch (e) {
      print('❌ Failed to deactivate grace period: $e');
    }
  }

  // ========== APPOINTMENT BOOKING & MANAGEMENT ==========
  
  
  
  
  
  // ========== APPOINTMENT BOOKING & MANAGEMENT ==========
  
Future<String> bookAppointment({
  required String userId,
  required String doctorId,
  required DateTime appointmentDate,
  required String timeSlot,
  required String reason,
  String? notes,
}) async {
final formatter = DateFormat('hh:mm a');
final parsedTime = formatter.parse(timeSlot);

final appointmentDateTime = DateTime(
  appointmentDate.year,
  appointmentDate.month,
  appointmentDate.day,
  parsedTime.hour,
  parsedTime.minute,
);

final minBookingTime = DateTime.now().add(const Duration(minutes: 30));

// Prevent booking inside 30 minutes
if (appointmentDateTime.isBefore(minBookingTime)) {
  throw Exception('Cannot book appointment less than 30 minutes from now');
}

// Prevent booking in the past (correct check!)
if (appointmentDateTime.isBefore(DateTime.now())) {
  throw Exception('Cannot book appointment in the past');
}

  
  final doctor = await getDoctorById(doctorId);
  if (doctor == null) {
    throw Exception('Doctor not found');
  }

  // Check if doctor is available on selected day
  if (!isDoctorAvailableOnDate(doctor, appointmentDate)) {
    final availableDaysText = getDoctorAvailableDaysText(doctor);
    throw Exception('Doctor is not available on this day. Available days: $availableDaysText');
  }

  // Duplicate prevention checks
  final isDuplicate = await _checkDuplicateBooking(
    userId: userId,
    doctorId: doctorId,
    appointmentDate: appointmentDate,
    timeSlot: timeSlot,
  );
  
  if (isDuplicate) {
    throw Exception('You already have an appointment with this doctor at this time slot');
  }

  final isSlotAvailable = await checkTimeSlotAvailability(
    doctorId: doctorId,
    appointmentDate: appointmentDate,
    timeSlot: timeSlot,
  );
  
  if (!isSlotAvailable) {
    throw Exception('This time slot is no longer available');
  }

  final hasOverlap = await _checkPatientOverlappingAppointments(
    userId: userId,
    appointmentDate: appointmentDate,
    timeSlot: timeSlot,
  );
  
  if (hasOverlap) {
    throw Exception('You have another appointment at this time');
  }

  // Check if time slot is in doctor's available slots list
  final availableSlots = List<String>.from(doctor['available_time_slots'] ?? []);
  if (!availableSlots.contains(timeSlot)) {
    throw Exception('Selected time slot is not available');
  }

  final appointmentId = const Uuid().v4();
  final isGracePeriodActive = await this.isGracePeriodActive(userId);
  
  // ✅ NEW: Get doctor's Auth UID for data sharing
  String? doctorAuthUid;
  try {
    doctorAuthUid = await _getDoctorAuthUid(doctorId);
    print('✅ Found doctor Auth UID: $doctorAuthUid');
  } catch (e) {
    print('⚠️ Could not get doctor Auth UID: $e');
  }
  
  // For WEB: Save directly to Firestore
  if (kIsWeb) {
    try {
      await _firestore.collection('appointments').doc(appointmentId).set({
        'userId': userId,
        'doctorId': doctorId,
        'doctorName': doctor['name'],
        'specialization': doctor['specialization'],
        'appointmentDate': Timestamp.fromDate(appointmentDate),
        'timeSlot': timeSlot,
        'status': statusPending,
        'reason': reason,
        'notes': notes ?? '',
        'rejectionReason': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (isGracePeriodActive) {
        await _deactivateGracePeriod(userId);
      }

      // ✅ FIXED: Create data sharing permission with doctorAuthUid
      try {
        if (doctorAuthUid != null) {
          await _dataSharingService.createPermissionRequest(
            patientId: userId,
            doctorId: doctorId,
            doctorAuthUid: doctorAuthUid,
            appointmentId: appointmentId,
          );
          print('✅ Permission request created with Auth UID (Web)');
        } else {
          print('⚠️ Doctor Auth UID not found, skipping permission request');
        }
      } catch (e) {
        print('⚠️ Permission request failed (Web): $e');
      }

      print('✅ Appointment saved to Firestore (Web): $appointmentId');
      return appointmentId;
    } catch (e) {
      print('❌ Failed to save appointment: $e');
      throw Exception('Failed to book appointment: $e');
    }
  }
  
  // For MOBILE: Save locally first, then sync
  final appointment = {
    'id': appointmentId,
    'userId': userId,
    'doctorId': doctorId,
    'doctorName': doctor['name'],
    'specialization': doctor['specialization'],
    'appointmentDate': appointmentDate.toIso8601String(),
    'timeSlot': timeSlot,
    'status': statusPending,
    'reason': reason,
    'notes': notes ?? '',
    'rejectionReason': '',
    'isSynced': 0,
    'createdAt': DateTime.now().toIso8601String(),
    'updatedAt': DateTime.now().toIso8601String(),
  };

  try {
    await _localDb.createAppointment(appointment);
    print('✅ Appointment saved locally: $appointmentId');

    // Try to sync if online
    final online = await _syncService.isOnline();
    if (online) {
      try {
        await _firestore.collection('appointments').doc(appointmentId).set({
          'userId': userId,
          'doctorId': doctorId,
          'doctorName': doctor['name'],
          'specialization': doctor['specialization'],
          'appointmentDate': Timestamp.fromDate(appointmentDate),
          'timeSlot': timeSlot,
          'status': statusPending,
          'reason': reason,
          'notes': notes ?? '',
          'rejectionReason': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        if (isGracePeriodActive) {
          await _deactivateGracePeriod(userId);
        }
        
        await _localDb.markAsSynced('appointments', appointmentId);
        
        // ✅ FIXED: Create data sharing permission with doctorAuthUid
        try {
          if (doctorAuthUid != null) {
            await _dataSharingService.createPermissionRequest(
              patientId: userId,
              doctorId: doctorId,
              doctorAuthUid: doctorAuthUid,
              appointmentId: appointmentId,
            );
            print('✅ Permission request created with Auth UID (Mobile)');
          } else {
            print('⚠️ Doctor Auth UID not found, skipping permission request');
          }
        } catch (e) {
          print('⚠️ Permission request failed (Mobile): $e');
        }
        
        print('✅ Appointment synced to Firestore: $appointmentId');
      } catch (e) {
        print('⚠️ Failed to sync appointment, will retry later: $e');
      }
    }

    // Send notification
    try {
      await _notificationService.showNotification(
        title: '✅ Appointment Booked',
        body: 'Your appointment with ${doctor['name']} has been requested for ${_formatDateTime(appointmentDate)}',
      );
    } catch (e) {
      print('⚠️ Failed to send notification: $e');
    }

    return appointmentId;
  } catch (e) {
    print('❌ Failed to book appointment: $e');
    throw Exception('Failed to book appointment: $e');
  }
}


/// Get doctor's Firebase Auth UID from doctorId
Future<String?> _getDoctorAuthUid(String doctorId) async {
  try {
    final snapshot = await _firestore
        .collection('doctor_profiles')
        .where('doctorId', isEqualTo: doctorId)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) {
      print('⚠️ No doctor profile found for doctorId: $doctorId');
      return null;
    }
    
    final doctorAuthUid = snapshot.docs.first.id;
    print('✅ Found doctor Auth UID: $doctorAuthUid for doctorId: $doctorId');
    return doctorAuthUid;
  } catch (e) {
    print('❌ Error fetching doctor Auth UID: $e');
    return null;
  }
}
  // ========== DUPLICATE PREVENTION METHODS ==========
  
  /// Check for duplicate bookings - PREVENTS DOUBLE BOOKING
  Future<bool> _checkDuplicateBooking({
    required String userId,
    required String doctorId,
    required DateTime appointmentDate,
    required String timeSlot,
  }) async {
    try {
      final startOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );
      final endOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
        23, 59, 59,
      );
      
      // Check if patient already has appointment with this doctor at this time
      final snapshot = await _firestore
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('appointmentDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .where('timeSlot', isEqualTo: timeSlot)
          .where('status', whereIn: [statusPending, statusApproved]) // Only check active appointments
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        print('⚠️ Duplicate booking detected for user $userId with doctor $doctorId at $timeSlot');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking duplicate booking: $e');
      return false; // Fail safe - allow booking if check fails
    }
  }
  
  /// Check if time slot is available for the doctor
  Future<bool> checkTimeSlotAvailability({
    required String doctorId,
    required DateTime appointmentDate,
    required String timeSlot,
  }) async {
    try {
      final startOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );
      final endOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
        23, 59, 59,
      );
      
      // Check if doctor already has an appointment at this time slot
      final snapshot = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('appointmentDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .where('timeSlot', isEqualTo: timeSlot)
          .where('status', whereIn: [statusPending, statusApproved])
          .get();
      
      final isAvailable = snapshot.docs.isEmpty;
      
      if (!isAvailable) {
        print('⚠️ Time slot $timeSlot already booked for doctor $doctorId on $appointmentDate');
      }
      
      return isAvailable;
    } catch (e) {
      print('❌ Error checking time slot availability: $e');
      return true; // Fail safe - allow booking if check fails
    }
  }
  
  /// Check for overlapping appointments for the patient
  Future<bool> _checkPatientOverlappingAppointments({
    required String userId,
    required DateTime appointmentDate,
    required String timeSlot,
  }) async {
    try {
      final startOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );
      final endOfDay = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
        23, 59, 59,
      );
      
      // Get all patient appointments for that day
      final snapshot = await _firestore
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .where('appointmentDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('appointmentDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .where('status', whereIn: [statusPending, statusApproved])
          .get();
      
      // Check for time slot conflicts
      for (var doc in snapshot.docs) {
        final existingTimeSlot = doc.data()['timeSlot'] as String;
        if (existingTimeSlot == timeSlot) {
          print('⚠️ Patient has overlapping appointment at $existingTimeSlot');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking patient overlapping appointments: $e');
      return false;
    }
  }
  
  /// ✅ ENHANCED: Get available time slots with day validation
  Future<List<String>> getAvailableTimeSlots({
    required String doctorId,
    required DateTime date,
    List<String>? allTimeSlots,
  }) async {
    try {
      // Get doctor's data
      final doctor = await getDoctorById(doctorId);
      if (doctor == null) {
        print('⚠️ Doctor not found: $doctorId');
        return [];
      }
      
      // ✅ Check if doctor is available on this day
      if (!isDoctorAvailableOnDate(doctor, date)) {
        print('⚠️ Doctor not available on ${_getDayName(date)}');
        return [];
      }
      
      // Get doctor's time slots
      final defaultSlots = allTimeSlots ?? 
          List<String>.from(doctor['available_time_slots'] ?? []);
      
      if (defaultSlots.isEmpty) {
        print('⚠️ No time slots configured for doctor');
        return [];
      }
      
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      // Get all booked appointments for this doctor on this date
      final snapshot = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('appointmentDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .where('status', whereIn: [statusPending, statusApproved])
          .get();
      
      // Extract booked time slots
      final bookedSlots = snapshot.docs
          .map((doc) => doc.data()['timeSlot'] as String)
          .toSet();
      
      // Return available slots
      final availableSlots = defaultSlots
          .where((slot) => !bookedSlots.contains(slot))
          .toList();
      
      print('📅 Available slots for $doctorId on ${_getDayName(date)}, ${date.day}/${date.month}: ${availableSlots.length}/${defaultSlots.length}');
      
      return availableSlots;
    } catch (e) {
      print('❌ Error getting available time slots: $e');
      return [];
    }
  }
  
  /// Helper to get day name from date
  String _getDayName(DateTime date) {
    const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return dayNames[date.weekday - 1];
  }
  
  /// Check if user can book with doctor (no pending/approved appointments)
  Future<bool> canUserBookWithDoctor({
    required String userId,
    required String doctorId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .where('doctorId', isEqualTo: doctorId)
          .where('status', whereIn: [statusPending, statusApproved])
          .get();
      
      final canBook = snapshot.docs.isEmpty;
      
      if (!canBook) {
        print('⚠️ User already has pending/approved appointment with this doctor');
      }
      
      return canBook;
    } catch (e) {
      print('❌ Error checking if user can book: $e');
      return true; // Fail safe
    }
  }

  /// Get user's appointments - Cross-platform compatible
  Future<List<Map<String, dynamic>>> getUserAppointments(
    String userId, {
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // On WEB: Fetch directly from Firestore
      if (kIsWeb) {
        Query<Map<String, dynamic>> query = _firestore
            .collection('appointments')
            .where('userId', isEqualTo: userId);
        
        // Apply status filter
        if (status != null) {
          query = query.where('status', isEqualTo: status);
        }
        
        // Apply date range filter
        if (startDate != null) {
          query = query.where('appointmentDate', 
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
        }
        if (endDate != null) {
          query = query.where('appointmentDate', 
              isLessThanOrEqualTo: Timestamp.fromDate(endDate));
        }
        
        final snapshot = await query
            .orderBy('appointmentDate', descending: true)
            .get();

        return snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'userId': data['userId'],
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
            'rejectionReason': data['rejectionReason'] ?? '',
          };
        }).toList();
      }
      
      // On MOBILE: Use local database
      var appointments = await _localDb.getAppointments(userId);
      
      // Apply filters
      if (status != null) {
        appointments = appointments
            .where((apt) => apt['status'] == status)
            .toList();
      }
      
      if (startDate != null || endDate != null) {
        appointments = appointments.where((apt) {
          final aptDate = DateTime.parse(apt['appointmentDate']);
          if (startDate != null && aptDate.isBefore(startDate)) return false;
          if (endDate != null && aptDate.isAfter(endDate)) return false;
          return true;
        }).toList();
      }
      
      return appointments;
    } catch (e) {
      print('❌ Error fetching appointments: $e');
      return [];
    }
  }

  /// Get appointment by ID - Cross-platform compatible
  Future<Map<String, dynamic>?> getAppointmentById(String appointmentId) async {
    try {
      // On WEB: Fetch from Firestore
      if (kIsWeb) {
        final doc = await _firestore
            .collection('appointments')
            .doc(appointmentId)
            .get();
        
        if (!doc.exists) return null;
        
        final data = doc.data()!;
        return {
          'id': doc.id,
          'userId': data['userId'],
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
          'rejectionReason': data['rejectionReason'] ?? '',
        };
      }
      
      // On MOBILE: Use local database
      final db = await _localDb.database;
      final results = await db.query(
        'appointments',
        where: 'id = ?',
        whereArgs: [appointmentId],
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print('❌ Error fetching appointment: $e');
      return null;
    }
  }

  // ========== APPOINTMENT STATUS UPDATES ==========
  
  /// Approve appointment (called by doctor/admin)
  Future<void> approveAppointment(String appointmentId) async {
    await _updateAppointmentStatus(
      appointmentId,
      statusApproved,
      notificationTitle: '✅ Appointment Approved',
      notificationBody: 'Your appointment has been approved!',
    );
  }

  /// Reject appointment with grace period activation
  Future<void> rejectAppointment(
    String appointmentId,
    String rejectionReason,
  ) async {
    if (rejectionReason.trim().isEmpty) {
      throw Exception('Rejection reason is required');
    }

    final appointment = await getAppointmentById(appointmentId);
    if (appointment == null) {
      throw Exception('Appointment not found');
    }

    // Update status to rejected
    try {
      // Update in Firestore
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': statusRejected,
        'rejectionReason': rejectionReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local DB on mobile
      if (!kIsWeb) {
        await _localDb.updateAppointment(appointmentId, {
          ...appointment,
          'status': statusRejected,
          'rejectionReason': rejectionReason,
          'isSynced': 1,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      print('✅ Appointment rejected: $appointmentId');

      // Trigger grace period and recommendations
      await _handleRejectionWithGracePeriod(
        appointment['userId'],
        appointmentId,
        appointment['specialization'],
        appointment['doctorId'],
        rejectionReason,
      );
    } catch (e) {
      print('❌ Failed to reject appointment: $e');
      throw Exception('Failed to reject appointment: $e');
    }
  }

  /// Cancel appointment (by user)
  Future<void> cancelAppointment(String appointmentId) async {
    await _updateAppointmentStatus(
      appointmentId,
      statusCancelled,
      notificationTitle: '❌ Appointment Cancelled',
      notificationBody: 'Your appointment has been cancelled',
    );
  }

  /// Complete appointment
  Future<void> completeAppointment(String appointmentId) async {
    await _updateAppointmentStatus(
      appointmentId,
      statusCompleted,
      notificationTitle: '✅ Appointment Completed',
      notificationBody: 'Thank you for visiting!',
    );
  }

  /// Generic status update method
  Future<void> _updateAppointmentStatus(
    String appointmentId,
    String newStatus, {
    String? notificationTitle,
    String? notificationBody,
  }) async {
    try {
      // Update in Firestore
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local DB on mobile
      if (!kIsWeb) {
        final appointment = await getAppointmentById(appointmentId);
        if (appointment != null) {
          await _localDb.updateAppointment(appointmentId, {
            ...appointment,
            'status': newStatus,
            'isSynced': 1,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }

      // Send notification
      if (!kIsWeb && notificationTitle != null && notificationBody != null) {
        try {
          await _notificationService.showNotification(
            title: notificationTitle,
            body: notificationBody,
          );
        } catch (e) {
          print('⚠️ Failed to send notification: $e');
        }
      }

      print('✅ Appointment status updated to $newStatus: $appointmentId');
    } catch (e) {
      print('❌ Failed to update appointment status: $e');
      throw Exception('Failed to update appointment: $e');
    }
  }

  // ========== GRACE PERIOD & RECOMMENDATIONS ==========
  
  /// Handle rejection with grace period and smart recommendations
  Future<void> _handleRejectionWithGracePeriod(
    String userId,
    String originalAppointmentId,
    String specialization,
    String originalDoctorId,
    String rejectionReason,
  ) async {
    try {
      // Send notification about rejection
      if (!kIsWeb) {
        await _notificationService.showNotification(
          title: '❌ Appointment Rejected',
          body: 'Reason: $rejectionReason',
        );
      }

      // Get recommended doctors
      final recommendations = await getRecommendedDoctors(
        specialization: specialization,
        excludeDoctorId: originalDoctorId,
      );

      if (recommendations.isEmpty) {
        print('⚠️ No alternative doctors available');
        return;
      }

      // Save recommendations with grace period
      final gracePeriodEnd = DateTime.now().add(Duration(hours: gracePeriodHours));
      
      await _firestore
          .collection('appointment_recommendations')
          .doc(userId)
          .set({
        'userId': userId,
        'originalAppointmentId': originalAppointmentId,
        'specialization': specialization,
        'rejectionReason': rejectionReason,
        'recommendations': recommendations.map((doc) => {
          'id': doc['id'],
          'name': doc['name'],
          'specialization': doc['specialization'],
          'rating': doc['rating'],
          'consultationFee': doc['consultation_fee'],
          'location': doc['location'],
          'availableTimeSlots': doc['available_time_slots'],
        }).toList(),
        'gracePeriodEnd': Timestamp.fromDate(gracePeriodEnd),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Schedule grace period reminder
      if (!kIsWeb) {
        await _notificationService.scheduleNotification(
          id: originalAppointmentId.hashCode,
          title: '⏰ Grace Period Active',
          body: 'You have $gracePeriodHours hours to book with another doctor',
          scheduledDate: DateTime.now().add(const Duration(hours: 1)),
        );

        // Send recommendation notification
        await _notificationService.showNotification(
          title: '✨ ${recommendations.length} Alternative Doctors Available',
          body: 'Dr. ${recommendations[0]['name']} - Rating: ${recommendations[0]['rating']}⭐',
        );
      }

      print('✅ Grace period activated with ${recommendations.length} recommendations');
    } catch (e) {
      print('❌ Failed to handle rejection grace period: $e');
    }
  }

  /// Get smart doctor recommendations based on multiple criteria
  Future<List<Map<String, dynamic>>> getRecommendedDoctors({
    required String specialization,
    String? excludeDoctorId,
    String? userLocation,
    double? minRating,
    int limit = 5,
  }) async {
    await loadDoctors();

    // Filter by specialization and exclude specific doctor
    var recommended = _doctors.where((doc) {
      return doc['specialization'] == specialization && 
             doc['id'] != excludeDoctorId;
    }).toList();

    // Apply rating filter
    if (minRating != null) {
      recommended = recommended
          .where((doc) => (doc['rating'] as num) >= minRating)
          .toList();
    }

    // Sort by rating (primary) and consultation fee (secondary)
    recommended.sort((a, b) {
      final ratingCompare = (b['rating'] as num).compareTo(a['rating'] as num);
      if (ratingCompare != 0) return ratingCompare;
      return (a['consultation_fee'] as num).compareTo(b['consultation_fee'] as num);
    });

    // Prioritize nearby doctors if location provided
    if (userLocation != null && userLocation.isNotEmpty) {
      final nearby = recommended.where((doc) =>
        doc['location']
            .toString()
            .toLowerCase()
            .contains(userLocation.toLowerCase())
      ).toList();
      
      final others = recommended.where((doc) =>
        !doc['location']
            .toString()
            .toLowerCase()
            .contains(userLocation.toLowerCase())
      ).toList();
      
      recommended = [...nearby, ...others];
    }

    // Return top recommendations
    return recommended.take(limit).toList();
  }

  /// Check if grace period is active
  Future<bool> isGracePeriodActive(String userId) async {
    try {
      final doc = await _firestore
          .collection('appointment_recommendations')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final gracePeriodEnd = (data['gracePeriodEnd'] as Timestamp).toDate();
      return DateTime.now().isBefore(gracePeriodEnd);
    } catch (e) {
      print('❌ Error checking grace period: $e');
      return false;
    }
  }

  /// Get active recommendations for user
  Future<List<Map<String, dynamic>>> getActiveRecommendations(String userId) async {
    try {
      final doc = await _firestore
          .collection('appointment_recommendations')
          .doc(userId)
          .get();

      if (!doc.exists) return [];

      final data = doc.data()!;
      final gracePeriodEnd = (data['gracePeriodEnd'] as Timestamp).toDate();
      
      if (DateTime.now().isAfter(gracePeriodEnd)) {
        print('⚠️ Grace period expired');
        return [];
      }

      return List<Map<String, dynamic>>.from(data['recommendations']);
    } catch (e) {
      print('❌ Error fetching recommendations: $e');
      return [];
    }
  }

  /// Get grace period time remaining
  Future<Duration?> getGracePeriodRemaining(String userId) async {
    try {
      final doc = await _firestore
          .collection('appointment_recommendations')
          .doc(userId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final gracePeriodEnd = (data['gracePeriodEnd'] as Timestamp).toDate();
      final remaining = gracePeriodEnd.difference(DateTime.now());
      
      return remaining.isNegative ? null : remaining;
    } catch (e) {
      return null;
    }
  }

  /// ✅ FIXED: Deactivate grace period after successful booking
  // Future<void> _deactivateGracePeriod(String userId) async {
  //   try {
  //     // Delete the recommendation document to deactivate grace period
  //     await _firestore
  //         .collection('appointment_recommendations')
  //         .doc(userId)
  //         .delete();
      
  //     print('✅ Grace period deactivated for user: $userId');
      
  //     // Send notification
  //     if (!kIsWeb) {
  //       try {
  //         await _notificationService.showNotification(
  //           title: '✅ Grace Period Ended',
  //           body: 'You have successfully booked an appointment!',
  //         );
  //       } catch (e) {
  //         print('⚠️ Failed to send notification: $e');
  //       }
  //     }
  //   } catch (e) {
  //     print('❌ Failed to deactivate grace period: $e');
  //   }
  // }

  // ========== HEALTH CONTEXT INTEGRATION ==========
  
  final HealthSummaryService _healthSummaryService = HealthSummaryService.instance;

  /// Book appointment WITH health context (enhanced version)
  Future<String> bookAppointmentWithHealthContext({
    required String userId,
    required String doctorId,
    required DateTime appointmentDate,
    required String timeSlot,
    String? reason,
    String? notes,
  }) async {
    final formatter = DateFormat('hh:mm a');
final parsedTime = formatter.parse(timeSlot);

final appointmentDateTime = DateTime(
  appointmentDate.year,
  appointmentDate.month,
  appointmentDate.day,
  parsedTime.hour,
  parsedTime.minute,
);

final minBookingTime = DateTime.now().add(const Duration(minutes: 30));

// Prevent booking inside 30 minutes
if (appointmentDateTime.isBefore(minBookingTime)) {
  throw Exception('Cannot book appointment less than 30 minutes from now');
}

// Prevent booking in the past (correct check!)
if (appointmentDateTime.isBefore(DateTime.now())) {
  throw Exception('Cannot book appointment in the past');
}

    
    final doctor = await getDoctorById(doctorId);
    if (doctor == null) {
      throw Exception('Doctor not found');
    }

    // ✅ NEW: Day validation
    if (!isDoctorAvailableOnDate(doctor, appointmentDate)) {
      final availableDaysText = getDoctorAvailableDaysText(doctor);
      throw Exception('Doctor is not available on this day. Available days: $availableDaysText');
    }

    // ✅ DUPLICATE PREVENTION CHECKS (same as regular booking)
    final isDuplicate = await _checkDuplicateBooking(
      userId: userId,
      doctorId: doctorId,
      appointmentDate: appointmentDate,
      timeSlot: timeSlot,
    );
    
    if (isDuplicate) {
      throw Exception('You already have an appointment with this doctor at this time slot');
    }

    final isSlotAvailable = await checkTimeSlotAvailability(
      doctorId: doctorId,
      appointmentDate: appointmentDate,
      timeSlot: timeSlot,
    );
    
    if (!isSlotAvailable) {
      throw Exception('This time slot is no longer available');
    }

    final hasOverlap = await _checkPatientOverlappingAppointments(
      userId: userId,
      appointmentDate: appointmentDate,
      timeSlot: timeSlot,
    );
    
    if (hasOverlap) {
      throw Exception('You have another appointment at this time');
    }

    // Check if time slot is available
    final availableSlots = List<String>.from(doctor['available_time_slots'] ?? []);
    if (!availableSlots.contains(timeSlot)) {
      throw Exception('Selected time slot is not available');
    }

    // Generate health summary for context
  EnhancedHealthSummary? healthSummary;
    String intelligentReason = reason ?? 'General consultation';
    
    try {
      healthSummary = await _healthSummaryService.generateHealthSummary(
        userId: userId,
        appointmentId: null,
      );
      intelligentReason = reason ?? _generateIntelligentReason(healthSummary);
    } catch (e) {
      print('⚠️ Could not generate health summary: $e');
    }

    final appointmentId = const Uuid().v4();
    final isGracePeriodActive = await this.isGracePeriodActive(userId);
    
    // Prepare appointment data
    final Map<String, dynamic> appointmentData = {
      'userId': userId,
      'doctorId': doctorId,
      'doctorName': doctor['name'],
      'specialization': doctor['specialization'],
      'timeSlot': timeSlot,
      'status': statusPending,
      'reason': intelligentReason,
      'notes': notes ?? '',
      'rejectionReason': '',
    };

    // Add platform-specific fields
    if (kIsWeb) {
      appointmentData['appointmentDate'] = Timestamp.fromDate(appointmentDate);
      appointmentData['createdAt'] = FieldValue.serverTimestamp();
      appointmentData['updatedAt'] = FieldValue.serverTimestamp();
      if (healthSummary != null) {
        appointmentData['healthSummarySnapshot'] = healthSummary.toJson();
      }
    } else {
      appointmentData['appointmentDate'] = appointmentDate.toIso8601String();
      appointmentData['createdAt'] = DateTime.now().toIso8601String();
      appointmentData['updatedAt'] = DateTime.now().toIso8601String();
      if (healthSummary != null) {
        appointmentData['healthSummarySnapshot'] = json.encode(healthSummary);
      }
    }

    try {
      // For WEB: Save to Firestore
      if (kIsWeb) {
        await _firestore.collection('appointments').doc(appointmentId).set(appointmentData);
        
        if (isGracePeriodActive) {
          await _deactivateGracePeriod(userId);
        }
        
        // Create doctor notification
        await _createDoctorNotification(
          doctorId: doctorId,
          appointmentId: appointmentId,
          userId: userId,
          userName: await _getUserName(userId),
          healthSummary: healthSummary?.toJson(),
        );
        
        print('✅ Appointment with health context saved (Web): $appointmentId');
        return appointmentId;
      }
      
      // For MOBILE: Save locally first
      final localData = Map<String, dynamic>.from(appointmentData);
      localData['id'] = appointmentId;
      localData['isSynced'] = 0;

      await _localDb.createAppointment(localData);
      print('✅ Appointment with health context saved locally: $appointmentId');

      // Try to sync if online
      final online = await _syncService.isOnline();
      if (online) {
        try {
          // Prepare Firestore data (convert dates to Timestamp)
          final firestoreData = Map<String, dynamic>.from(appointmentData);
          firestoreData['appointmentDate'] = Timestamp.fromDate(appointmentDate);
          firestoreData['createdAt'] = FieldValue.serverTimestamp();
          firestoreData['updatedAt'] = FieldValue.serverTimestamp();
          if (healthSummary != null) {
            firestoreData['healthSummarySnapshot'] = healthSummary.toJson();
          }
          
          await _firestore.collection('appointments').doc(appointmentId).set(firestoreData);
          await _localDb.markAsSynced('appointments', appointmentId);
          
          if (isGracePeriodActive) {
            await _deactivateGracePeriod(userId);
          }
          
          await _createDoctorNotification(
            doctorId: doctorId,
            appointmentId: appointmentId,
            userId: userId,
            userName: await _getUserName(userId),
            healthSummary: healthSummary?.toJson(),
          );
          
          print('✅ Appointment synced with health context: $appointmentId');
        } catch (e) {
          print('⚠️ Failed to sync, will retry later: $e');
        }
      }

      // Send notification to user
      try {
        await _notificationService.showNotification(
          title: '✅ Appointment Booked',
          body: 'Your appointment with ${doctor['name']} has been requested for ${_formatDateTime(appointmentDate)}',
        );
      } catch (e) {
        print('⚠️ Failed to send notification: $e');
      }

      return appointmentId;
    } catch (e) {
      print('❌ Failed to book appointment with health context: $e');
      throw Exception('Failed to book appointment: $e');
    }
  }

  /// Generate intelligent reason from health summary
  String _generateIntelligentReason(EnhancedHealthSummary? summary) {
    if (summary == null) return 'General health consultation';
    
    final List<String> reasons = [];
    final summaryData = summary.summaryData;

    // Check for red flags (critical symptoms)
    if (summaryData.symptomAnalysis.redFlags.isNotEmpty) {
      reasons.add('⚠️ ${summaryData.symptomAnalysis.redFlags.first}');
    }

    // Check for symptom patterns
    if (summaryData.symptomAnalysis.topSymptoms.isNotEmpty) {
      final topSymptom = summaryData.symptomAnalysis.topSymptoms.first;
      reasons.add('Experiencing ${topSymptom.symptomName} (${topSymptom.frequency} times, ${topSymptom.averageSeverity} severity)');
    }

    // Check for nutrition concerns
    if (summaryData.nutritionInsights.concerns.isNotEmpty) {
      reasons.add('Nutrition concerns: ${summaryData.nutritionInsights.concerns.first}');
    }

    // Check average calories
    if (summaryData.nutritionInsights.averageCalories < 1500) {
      reasons.add('Low calorie intake - nutrition consultation needed');
    }

    // Check for medication adherence
    if (summaryData.medicationAdherence != null) {
      final adherence = summaryData.medicationAdherence!;
      if (adherence.missedDoses > 3) {
        reasons.add('Medication adherence concerns (${adherence.missedDoses} missed doses)');
      }
    }

    return reasons.isEmpty 
        ? 'General health consultation' 
        : reasons.join('; ');
  }

  /// Create notification for doctor with patient context
  Future<void> _createDoctorNotification({
    required String doctorId,
    required String appointmentId,
    required String userId,
    required String userName,
    Map<String, dynamic>? healthSummary,
  }) async {
    try {
      // Determine priority based on health summary
      String priority = 'normal';
      if (healthSummary != null) {
        final criticalAlerts = healthSummary['criticalAlerts'] as List<dynamic>? ?? [];
        final symptomPatterns = healthSummary['symptomPatterns'] as List<dynamic>? ?? [];
        
        if (criticalAlerts.isNotEmpty) {
          priority = 'urgent';
        } else if (symptomPatterns.length > 3) {
          priority = 'high';
        }
      }

      final Map<String, dynamic> notificationData = {
        'userId': doctorId,
        'type': 'new_appointment',
        'priority': priority,
        'title': 'New Appointment Request',
        'message': 'New appointment from $userName',
        'appointmentId': appointmentId,
        'patientId': userId,
        'patientName': userName,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (healthSummary != null) {
        final symptomPatterns = healthSummary['symptomPatterns'] as List<dynamic>? ?? [];
        final topSymptoms = symptomPatterns
            .take(3)
            .map((s) => (s as Map<String, dynamic>)['symptomName'] as String? ?? 'Unknown')
            .toList();
        
        final medicationAdherence = healthSummary['medicationAdherence'] as Map<String, dynamic>? ?? {};
        final criticalAlerts = healthSummary['criticalAlerts'] as List<dynamic>? ?? [];
            
        notificationData['healthContext'] = {
          'criticalAlertsCount': criticalAlerts.length,
          'symptomsCount': symptomPatterns.length,
          'medicationAdherence': medicationAdherence['adherenceRate'] ?? 0,
          'topSymptoms': topSymptoms,
        };
      }

      await _firestore.collection('notifications').add(notificationData);
      print('✅ Doctor notification created for: $doctorId');
    } catch (e) {
      print('⚠️ Failed to create doctor notification: $e');
    }
  }

  /// Get user name for notifications - FIXED FOR PROFILES COLLECTION
  Future<String> _getUserName(String userId) async {
    try {
      print('🔍 Fetching user name for: $userId');
      
      // PRIMARY: Try profiles collection (YOUR MAIN COLLECTION)
      final profileDoc = await _firestore.collection('profiles').doc(userId).get();
      if (profileDoc.exists && profileDoc.data() != null) {
        final name = profileDoc.data()!['name'];
        if (name != null && name.toString().trim().isNotEmpty) {
          print('✅ Found name in profiles collection: $name');
          return name.toString();
        }
      }
      
      // Fallback: Try users collection
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final name = userDoc.data()!['name'];
        if (name != null && name.toString().trim().isNotEmpty) {
          print('✅ Found name in users collection: $name');
          return name.toString();
        }
      }
      
      // Last resort: Try patient_profiles
      final patientDoc = await _firestore.collection('patient_profiles').doc(userId).get();
      if (patientDoc.exists && patientDoc.data() != null) {
        final name = patientDoc.data()!['name'];
        if (name != null && name.toString().trim().isNotEmpty) {
          print('✅ Found name in patient_profiles collection: $name');
          return name.toString();
        }
      }
      
      print('⚠️ No name found for userId: $userId');
      return 'Patient';
    } catch (e) {
      print('❌ Error fetching user name for $userId: $e');
      return 'Patient';
    }
  }

  /// Get appointment with refreshed health context
  Future<Map<String, dynamic>?> getAppointmentWithHealthContext(
    String appointmentId,
  ) async {
    try {
      final appointment = await getAppointmentById(appointmentId);
      if (appointment == null) return null;

      // Check if health summary needs refresh (older than 24 hours)
      if (appointment['healthSummarySnapshot'] != null) {
        DateTime updatedAt;
        
        if (kIsWeb) {
          final timestamp = appointment['updatedAt'];
          if (timestamp is Timestamp) {
            updatedAt = timestamp.toDate();
          } else {
            updatedAt = DateTime.now();
          }
        } else {
          final dateString = appointment['updatedAt'];
          if (dateString is String) {
            updatedAt = DateTime.parse(dateString);
          } else {
            updatedAt = DateTime.now();
          }
        }
        
        if (DateTime.now().difference(updatedAt).inHours > 24) {
          try {
            final userId = appointment['userId'] as String;
            final freshSummary = await _healthSummaryService.generateHealthSummary(
              userId: userId,
              appointmentId: appointmentId,
            );
            
            // Update the appointment with fresh summary
            if (kIsWeb) {
              await _firestore
                  .collection('appointments')
                  .doc(appointmentId)
                  .update({
                'healthSummarySnapshot': freshSummary.toJson(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              appointment['healthSummarySnapshot'] = freshSummary.toJson();
            } else {
              // For mobile, update local database
              final updatedAppointment = Map<String, dynamic>.from(appointment);
              updatedAppointment['healthSummarySnapshot'] = json.encode(freshSummary.toJson());
              updatedAppointment['updatedAt'] = DateTime.now().toIso8601String();
              
              await _localDb.updateAppointment(appointmentId, updatedAppointment);
              appointment['healthSummarySnapshot'] = json.encode(freshSummary.toJson());
            }
            
            print('✅ Health summary refreshed for appointment: $appointmentId');
          } catch (e) {
            print('⚠️ Could not refresh health summary: $e');
          }
        }
      }

      return appointment;
    } catch (e) {
      print('❌ Error fetching appointment with health context: $e');
      return null;
    }
  }

  /// Get doctor's appointments with COMPLETE patient details - ENHANCED VERSION
  Future<List<Map<String, dynamic>>> getDoctorAppointmentsWithHealthContext({
    required String doctorId,
    DateTime? date,
  }) async {
    try {
      print('📋 Fetching appointments for doctor: $doctorId');
      
      // ✅ Fetch ONLY pending and approved (hide rejected/cancelled/completed)
      Query<Map<String, dynamic>> query = _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('status', whereIn: [statusPending, statusApproved]);

      if (date != null) {
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
        
        query = query
            .where('appointmentDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('appointmentDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
      }

      final snapshot = await query.orderBy('appointmentDate').get();
      
      print('📊 Found ${snapshot.docs.length} active appointments');

      final List<Map<String, dynamic>> appointments = [];

      for (var doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final userId = data['userId'] as String;
        
        print('👤 Fetching patient details for userId: $userId');
        
        // ✅ Fetch COMPLETE patient profile
        final patientProfile = await _getCompletePatientProfile(userId);
        
        // ✅ Merge appointment data with patient profile
        data['id'] = doc.id;
        data['patientProfile'] = patientProfile;
        
        // ✅ Add easy-access fields for UI
        data['patientName'] = patientProfile['name'] ?? 'Unknown Patient';
        data['patientAge'] = patientProfile['age'] ?? 0;
        data['patientGender'] = patientProfile['gender'] ?? 'Not specified';
        data['patientPhone'] = patientProfile['phone'] ?? '';
        data['patientEmail'] = patientProfile['email'] ?? '';
        data['bloodGroup'] = patientProfile['bloodGroup'] ?? '';
        data['allergies'] = patientProfile['allergies'] ?? '';
        data['chronicConditions'] = patientProfile['chronicConditions'] ?? '';
        data['currentMedications'] = patientProfile['currentMedications'] ?? '';
        data['bmi'] = patientProfile['bmi'] ?? 0.0;
        data['bmiCategory'] = patientProfile['bmiCategory'] ?? '';
        data['profilePhotoBase64'] = patientProfile['profilePhotoBase64'] ?? '';
        
        print('✅ Added appointment with patient: ${data['patientName']}');
        
        appointments.add(data);
      }

      print('✅ Total appointments with patient details: ${appointments.length}');
      return appointments;
    } catch (e) {
      print('❌ Error fetching doctor appointments: $e');
      return [];
    }
  }

  /// Get COMPLETE patient profile with all medical information
  Future<Map<String, dynamic>> _getCompletePatientProfile(String userId) async {
    try {
      print('🔍 Fetching complete profile for: $userId');
      
      // Fetch from profiles collection
      final profileDoc = await _firestore.collection('profiles').doc(userId).get();
      
      if (profileDoc.exists && profileDoc.data() != null) {
        final profile = profileDoc.data()!;
        print('✅ Found complete profile for: ${profile['name']}');
        
        return {
          'name': profile['name'] ?? 'Unknown',
          'age': profile['age'] ?? 0,
          'gender': profile['gender'] ?? '',
          'phone': profile['phone'] ?? '',
          'email': profile['email'] ?? '',
          'bloodGroup': profile['bloodGroup'] ?? '',
          'allergies': profile['allergies'] ?? '',
          'chronicConditions': profile['chronicConditions'] ?? '',
          'currentMedications': profile['currentMedications'] ?? '',
          'weight': profile['weight'] ?? 0,
          'height': profile['height'] ?? 0,
          'bmi': profile['bmi'] ?? 0.0,
          'bmiCategory': profile['bmiCategory'] ?? '',
          'emergencyContactName': profile['emergencyContactName'] ?? '',
          'emergencyContactPhone': profile['emergencyContactPhone'] ?? '',
          'profilePhotoBase64': profile['profilePhotoBase64'] ?? '',
        };
      }
      
      // Fallback: Try users collection
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        print('⚠️ Found partial data in users collection');
        
        return {
          'name': userData['name'] ?? 'Unknown',
          'age': 0,
          'gender': '',
          'phone': userData['phone'] ?? '',
          'email': userData['email'] ?? '',
          'bloodGroup': '',
          'allergies': '',
          'chronicConditions': '',
          'currentMedications': '',
          'weight': 0,
          'height': 0,
          'bmi': 0.0,
          'bmiCategory': '',
          'emergencyContactName': '',
          'emergencyContactPhone': '',
          'profilePhotoBase64': '',
        };
      }
      
      print('⚠️ No profile found for userId: $userId');
      return {
        'name': 'Unknown Patient',
        'age': 0,
        'gender': '',
        'phone': '',
        'email': '',
        'bloodGroup': '',
        'allergies': '',
        'chronicConditions': '',
        'currentMedications': '',
        'weight': 0,
        'height': 0,
        'bmi': 0.0,
        'bmiCategory': '',
        'emergencyContactName': '',
        'emergencyContactPhone': '',
        'profilePhotoBase64': '',
      };
    } catch (e) {
      print('❌ Error fetching patient profile for $userId: $e');
      return {
        'name': 'Error Loading',
        'age': 0,
        'gender': '',
        'phone': '',
        'email': '',
        'bloodGroup': '',
        'allergies': '',
        'chronicConditions': '',
        'currentMedications': '',
        'weight': 0,
        'height': 0,
        'bmi': 0.0,
        'bmiCategory': '',
        'emergencyContactName': '',
        'emergencyContactPhone': '',
        'profilePhotoBase64': '',
      };
    }
  }

  // ========== STATISTICS & ANALYTICS ==========
  
  /// Get appointment statistics for user
  Future<Map<String, dynamic>> getAppointmentStatistics(String userId) async {
    final appointments = await getUserAppointments(userId);
    
    return {
      'total': appointments.length,
      'pending': appointments.where((a) => a['status'] == statusPending).length,
      'approved': appointments.where((a) => a['status'] == statusApproved).length,
      'rejected': appointments.where((a) => a['status'] == statusRejected).length,
      'completed': appointments.where((a) => a['status'] == statusCompleted).length,
      'cancelled': appointments.where((a) => a['status'] == statusCancelled).length,
    };
  }

  /// Get upcoming appointments count
  Future<int> getUpcomingAppointmentsCount(String userId) async {
    final appointments = await getUserAppointments(
      userId,
      startDate: DateTime.now(),
    );
    return appointments
        .where((a) => [statusPending, statusApproved].contains(a['status']))
        .length;
  }

  // ========== UTILITY METHODS ==========
  
  /// Format date time for display
  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Validate appointment date
  bool isValidAppointmentDate(DateTime date) {
    final now = DateTime.now();
    final minDate = DateTime(now.year, now.month, now.day);
    final maxDate = minDate.add(const Duration(days: 90));
    
    return date.isAfter(minDate) && date.isBefore(maxDate);
  }

  /// Clear cache (useful for testing or forced refresh)
  void clearCache() {
    _doctors = [];
    _doctorsLoadedAt = null;
    print('🗑️ Cache cleared');
  }
}