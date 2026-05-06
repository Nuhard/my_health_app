import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_sharing_permission.dart';

/// Data Sharing Service
/// 
/// Handles all data sharing permission operations between patients and doctors
class DataSharingService {
  static final DataSharingService instance = DataSharingService._init();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  DataSharingService._init();

  // ========== CREATE PERMISSION REQUEST ==========
  
  /// Create a data sharing request when appointment is approved
  Future<void> createPermissionRequest({
    required String patientId,
    required String doctorId,
    required String doctorAuthUid, // ✅ Firebase Auth UID of doctor
    required String appointmentId,
  }) async {
    try {
      final permission = DataSharingPermission.createRequest(
        patientId: patientId,
        doctorId: doctorId,
        doctorAuthUid: doctorAuthUid,
        appointmentId: appointmentId,
      );

      await _firestore
          .collection('data_sharing_permissions')
          .doc(permission.id)
          .set(permission.toFirestore());

      print('✅ Data sharing permission request created: ${permission.id}');
      print('   Patient: $patientId');
      print('   Doctor ID: $doctorId');
      print('   Doctor Auth UID: $doctorAuthUid');
    } catch (e) {
      print('❌ Error creating permission request: $e');
      rethrow;
    }
  }

  // ========== PATIENT ACTIONS ==========
  
  /// Patient approves data sharing with selected permissions
  Future<void> approveDataSharing({
    required String appointmentId,
    required String patientId,
    required Map<String, bool> permissions,
    String? notes,
  }) async {
    try {
      final docId = '${appointmentId}_$patientId';
      
      await _firestore
          .collection('data_sharing_permissions')
          .doc(docId)
          .update({
        'permissions': permissions,
        'status': DataSharingPermission.STATUS_APPROVED,
        'approvedAt': FieldValue.serverTimestamp(),
        'notes': notes,
      });

      // Update appointment status
      await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'dataShareStatus': 'approved',
        'dataShareApprovedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Data sharing approved for appointment: $appointmentId');
    } catch (e) {
      print('❌ Error approving data sharing: $e');
      rethrow;
    }
  }

  /// Patient rejects data sharing request
  Future<void> rejectDataSharing({
    required String appointmentId,
    required String patientId,
    String? notes,
  }) async {
    try {
      final docId = '${appointmentId}_$patientId';
      
      await _firestore
          .collection('data_sharing_permissions')
          .doc(docId)
          .update({
        'status': DataSharingPermission.STATUS_REJECTED,
        'rejectedAt': FieldValue.serverTimestamp(),
        'notes': notes,
      });

      // Update appointment status
      await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'dataShareStatus': 'rejected',
        'dataShareRejectedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Data sharing rejected for appointment: $appointmentId');
    } catch (e) {
      print('❌ Error rejecting data sharing: $e');
      rethrow;
    }
  }

  /// Patient updates existing permissions
  Future<void> updatePermissions({
    required String appointmentId,
    required String patientId,
    required Map<String, bool> permissions,
  }) async {
    try {
      final docId = '${appointmentId}_$patientId';
      
      await _firestore
          .collection('data_sharing_permissions')
          .doc(docId)
          .update({
        'permissions': permissions,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Permissions updated for appointment: $appointmentId');
    } catch (e) {
      print('❌ Error updating permissions: $e');
      rethrow;
    }
  }

  // ========== GET PERMISSIONS ==========
  
  /// Get permission for specific appointment
  Future<DataSharingPermission?> getPermission({
    required String appointmentId,
    required String patientId,
  }) async {
    try {
      final docId = '${appointmentId}_$patientId';
      final doc = await _firestore
          .collection('data_sharing_permissions')
          .doc(docId)
          .get();

      if (!doc.exists) return null;

      return DataSharingPermission.fromFirestore(doc.id, doc.data()!);
    } catch (e) {
      print('❌ Error getting permission: $e');
      return null;
    }
  }

  /// Stream permission for real-time updates
  Stream<DataSharingPermission?> streamPermission({
    required String appointmentId,
    required String patientId,
  }) {
    final docId = '${appointmentId}_$patientId';
    
    return _firestore
        .collection('data_sharing_permissions')
        .doc(docId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return DataSharingPermission.fromFirestore(doc.id, doc.data()!);
    });
  }

  /// Get all pending permission requests for a patient
  Future<List<DataSharingPermission>> getPendingRequestsForPatient(String patientId) async {
    try {
      final snapshot = await _firestore
          .collection('data_sharing_permissions')
          .where('patientId', isEqualTo: patientId)
          .where('status', isEqualTo: DataSharingPermission.STATUS_PENDING)
          .get();

      return snapshot.docs
          .map((doc) => DataSharingPermission.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('❌ Error getting pending requests: $e');
      return [];
    }
  }

  /// Stream pending requests for patient
  Stream<List<DataSharingPermission>> streamPendingRequestsForPatient(String patientId) {
    return _firestore
        .collection('data_sharing_permissions')
        .where('patientId', isEqualTo: patientId)
        .where('status', isEqualTo: DataSharingPermission.STATUS_PENDING)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => DataSharingPermission.fromFirestore(doc.id, doc.data()))
          .toList();
    });
  }

  // ========== ACCESS CHECKS FOR DOCTORS ==========
  
  /// Check if doctor has permission to view specific data category
  Future<bool> checkPermission({
    required String appointmentId,
    required String patientId,
    required String category,
  }) async {
    try {
      final permission = await getPermission(
        appointmentId: appointmentId,
        patientId: patientId,
      );

      if (permission == null) return false;
      return permission.isAllowed(category);
    } catch (e) {
      print('❌ Error checking permission: $e');
      return false;
    }
  }

  /// Get all permissions doctor has for a patient
  Future<List<String>> getAllowedCategories({
    required String appointmentId,
    required String patientId,
  }) async {
    try {
      final permission = await getPermission(
        appointmentId: appointmentId,
        patientId: patientId,
      );

      if (permission == null) return [];
      return permission.allowedCategories;
    } catch (e) {
      print('❌ Error getting allowed categories: $e');
      return [];
    }
  }

  /// Check overall permission status
  Future<String> getPermissionStatus({
    required String appointmentId,
    required String patientId,
  }) async {
    try {
      final permission = await getPermission(
        appointmentId: appointmentId,
        patientId: patientId,
      );

      if (permission == null) return DataSharingPermission.STATUS_PENDING;
      return permission.status;
    } catch (e) {
      print('❌ Error getting permission status: $e');
      return DataSharingPermission.STATUS_PENDING;
    }
  }

  // ========== REVOKE ACCESS ==========
  
  /// Patient revokes data sharing (converts approved to rejected)
  Future<void> revokeDataSharing({
    required String appointmentId,
    required String patientId,
    String? reason,
  }) async {
    try {
      final docId = '${appointmentId}_$patientId';
      
      await _firestore
          .collection('data_sharing_permissions')
          .doc(docId)
          .update({
        'status': DataSharingPermission.STATUS_REJECTED,
        'rejectedAt': FieldValue.serverTimestamp(),
        'notes': reason ?? 'Access revoked by patient',
      });

      print('✅ Data sharing revoked for appointment: $appointmentId');
    } catch (e) {
      print('❌ Error revoking data sharing: $e');
      rethrow;
    }
  }

  // ========== STATISTICS ==========
  
  /// Get permission statistics for a patient
  Future<Map<String, int>> getPatientPermissionStats(String patientId) async {
    try {
      final snapshot = await _firestore
          .collection('data_sharing_permissions')
          .where('patientId', isEqualTo: patientId)
          .get();

      int pending = 0;
      int approved = 0;
      int rejected = 0;

      for (var doc in snapshot.docs) {
        final status = doc.data()['status'];
        if (status == DataSharingPermission.STATUS_PENDING) pending++;
        if (status == DataSharingPermission.STATUS_APPROVED) approved++;
        if (status == DataSharingPermission.STATUS_REJECTED) rejected++;
      }

      return {
        'pending': pending,
        'approved': approved,
        'rejected': rejected,
        'total': snapshot.docs.length,
      };
    } catch (e) {
      print('❌ Error getting permission stats: $e');
      return {'pending': 0, 'approved': 0, 'rejected': 0, 'total': 0};
    }
  }
}