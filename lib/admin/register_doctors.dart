import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class DoctorRegistration {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if doctor already exists
  static Future<bool> isDoctorRegistered(String doctorId, String email) async {
    final mappingDoc = await _firestore
        .collection('doctor_id_mapping')
        .doc(doctorId)
        .get();
    if (mappingDoc.exists) return true;

    final usersQuery = await _firestore
        .collection('users')
        .where('doctorId', isEqualTo: doctorId)
        .limit(1)
        .get();
    if (usersQuery.docs.isNotEmpty) return true;

    final emailQuery = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return emailQuery.docs.isNotEmpty;
  }

  /// Register all doctors from JSON file (only new ones)
  static Future<void> registerAllDoctors() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/doctors_database.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> doctors = jsonData['doctors'];

      print('🥼 Checking ${doctors.length} doctors for registration...\n');

      int successCount = 0;
      int skippedCount = 0;
      int failCount = 0;

      for (var doctor in doctors) {
        try {
          final isRegistered = await isDoctorRegistered(doctor['id'], doctor['email']);
          if (isRegistered) {
            skippedCount++;
            print('⏭️  Skipped (already exists): ${doctor['name']}');
            continue;
          }
          await registerSingleDoctor(doctor);
          successCount++;
          print('✅ Successfully registered: ${doctor['name']}\n');
        } catch (e) {
          failCount++;
          print('❌ Failed to register ${doctor['name']}: $e\n');
        }
      }

      print('\n📊 Registration Summary:');
      print('✅ Successfully registered: $successCount');
      print('⏭️  Already registered (skipped): $skippedCount');
      print('❌ Failed: $failCount');
      print('📋 Total doctors: ${doctors.length}');
    } catch (e) {
      print('❌ Error loading doctors database: $e');
      rethrow;
    }
  }

  /// Register a single doctor
  static Future<Map<String, dynamic>> registerSingleDoctor(Map<String, dynamic> doctorData) async {
    final String email = '${doctorData['id']}@nutritrack.lk';
    final String password = 'Doctor@${doctorData['id']}123';

    print('📧 Creating account for: ${doctorData['name']}');
    print('   Email: $email');

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;
      print('   ✓ Auth account created: $uid');

      await userCredential.user!.updateDisplayName(doctorData['name']);

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'fullName': doctorData['name'],
        'userType': 'doctor',
        'doctorId': doctorData['id'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('   ✓ User document created');

      await _firestore.collection('doctor_profiles').doc(uid).set({
        'uid': uid,
        'doctorId': doctorData['id'],
        'email': email,
        'fullName': doctorData['name'],
        'specialization': doctorData['specialization'],
        'qualifications': doctorData['qualifications'],
        'experienceYears': doctorData['experience_years'],
        'rating': doctorData['rating'].toDouble(),
        'consultationFee': doctorData['consultation_fee'],
        'availableDays': List<String>.from(doctorData['available_days']),
        'availableTimeSlots': List<String>.from(doctorData['available_time_slots']),
        'location': doctorData['location'],
        'hospital': doctorData['hospital'],
        'phone': doctorData['phone'],
        'languages': List<String>.from(doctorData['languages']),
        'expertise': List<String>.from(doctorData['expertise']),
        'bio': doctorData['bio'],
        'verified': true,
        'active': true,
        'totalPatients': 0,
        'totalAppointments': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('   ✓ Doctor profile created');

      // ✅ Always write doctor_id_mapping so credentials list stays in sync
      await _firestore.collection('doctor_id_mapping').doc(doctorData['id']).set({
        'originalId': doctorData['id'],
        'firebaseUid': uid,
        'name': doctorData['name'],
        'email': email,
        'registeredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('   ✓ ID mapping created');

      return {
        'success': true,
        'doctorId': doctorData['id'],
        'firebaseUid': uid,
        'email': email,
        'password': password,
        'name': doctorData['name'],
      };
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Email already registered: $email');
      }
      rethrow;
    }
  }

  /// ✅ FIXED: Fetch credentials from doctor_profiles (has all doctors)
  /// then merge with doctor_id_mapping for any extra data.
  /// This ensures all 22 doctors show regardless of mapping gaps.
  static Future<List<Map<String, dynamic>>> getDoctorCredentials() async {
    // Primary source: doctor_profiles — every registered doctor has one
    final profilesSnap = await _firestore
        .collection('doctor_profiles')
        .orderBy('doctorId')
        .get();

    // Secondary source: doctor_id_mapping — for registeredAt timestamp
    final mappingSnap = await _firestore
        .collection('doctor_id_mapping')
        .get();

    // Build a lookup map: originalId → mapping data
    final Map<String, Map<String, dynamic>> mappingById = {};
    for (final doc in mappingSnap.docs) {
      final data = doc.data();
      final id = data['originalId']?.toString() ?? doc.id;
      mappingById[id] = data;
    }

    // Merge profile data with mapping data
    return profilesSnap.docs.map((doc) {
      final profile = doc.data();
      final doctorId = profile['doctorId']?.toString() ?? '';
      final mapping = mappingById[doctorId] ?? {};

      return {
        'originalId': doctorId,
        'firebaseUid': profile['uid'] ?? mapping['firebaseUid'] ?? '',
        'name': profile['fullName'] ?? mapping['name'] ?? '',
        'email': profile['email'] ?? mapping['email'] ?? '$doctorId@nutritrack.lk',
        // Use mapping registeredAt if available, else profile createdAt
        'registeredAt': mapping['registeredAt'] ?? profile['createdAt'],
      };
    }).toList();
  }

  /// Get registration statistics
  static Future<Map<String, int>> getRegistrationStats() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/doctors_database.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final int totalInJson = (jsonData['doctors'] as List).length;

      final registeredDocs = await _firestore
          .collection('users')
          .where('userType', isEqualTo: 'doctor')
          .get();
      final int registered = registeredDocs.docs.length;

      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1);
      final thisMonthDocs = await _firestore
          .collection('doctor_id_mapping')
          .where('registeredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth))
          .get();
      final int thisMonth = thisMonthDocs.docs.length;

      return {
        'total': totalInJson,
        'registered': registered,
        'pending': totalInJson - registered,
        'thisMonth': thisMonth,
      };
    } catch (e) {
      return {'total': 0, 'registered': 0, 'pending': 0, 'thisMonth': 0};
    }
  }

  /// Print doctor login credentials
  static Future<void> printDoctorCredentials() async {
    print('\n📋 DOCTOR LOGIN CREDENTIALS\n');
    print('=' * 80);

    final credentials = await getDoctorCredentials();
    for (var cred in credentials) {
      print('\n👨‍⚕️ ${cred['name']}');
      print('   Email: ${cred['email']}');
      print('   Password: Doctor@${cred['originalId']}123');
      print('   Doctor ID: ${cred['originalId']}');
      print('   Firebase UID: ${cred['firebaseUid']}');
    }

    print('\n' + '=' * 80);
    print('\n⚠️  IMPORTANT: Share these credentials securely with doctors');
    print('⚠️  Doctors should change passwords on first login\n');
  }
}