import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for managing consultation feedback
/// Feedback goes to admin first, then admin can approve/share with doctors
class ConsultationFeedbackService {
  static final ConsultationFeedbackService instance = ConsultationFeedbackService._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ConsultationFeedbackService._init();

  // Feedback types
  static const String typeCompliment = 'compliment';
  static const String typeComplaint = 'complaint';
  static const String typeSuggestion = 'suggestion';

  // Feedback status
  static const String statusPending = 'pending'; // Admin hasn't reviewed yet
  static const String statusApproved = 'approved'; // Admin approved, shared with doctor
  static const String statusRejected = 'rejected'; // Admin rejected (invalid/spam)
  static const String statusResolved = 'resolved'; // Admin marked as resolved

  /// Submit feedback for a completed consultation
  Future<String> submitFeedback({
    required String appointmentId,
    required String patientId,
    required String doctorId,
    required String doctorName,
    required int rating, // 1-5 stars
    required String feedbackType, // compliment, complaint, suggestion
    required String comments,
    bool isAnonymous = false,
  }) async {
    try {
      // Validate inputs
      if (rating < 1 || rating > 5) {
        throw Exception('Rating must be between 1 and 5');
      }
      if (comments.trim().isEmpty) {
        throw Exception('Feedback comments cannot be empty');
      }
      if (![typeCompliment, typeComplaint, typeSuggestion].contains(feedbackType)) {
        throw Exception('Invalid feedback type');
      }

      final feedbackId = const Uuid().v4();

      // Get patient name (unless anonymous)
      String patientName = 'Anonymous';
      if (!isAnonymous) {
        try {
          final profileDoc = await _firestore.collection('profiles').doc(patientId).get();
          if (profileDoc.exists && profileDoc.data() != null) {
            patientName = profileDoc.data()!['name'] ?? 'Patient';
          }
        } catch (e) {
          print('⚠️ Could not fetch patient name: $e');
          patientName = 'Patient';
        }
      }

      // Create feedback document
      await _firestore.collection('consultation_feedback').doc(feedbackId).set({
        'feedbackId': feedbackId,
        'appointmentId': appointmentId,
        'patientId': patientId,
        'patientName': isAnonymous ? 'Anonymous' : patientName,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'rating': rating,
        'feedbackType': feedbackType,
        'comments': comments,
        'isAnonymous': isAnonymous,
        'status': statusPending,
        'sharedWithDoctor': false, // Admin hasn't shared yet
        'adminNotes': '', // Admin can add notes
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null, // Admin who reviewed it
      });

      // Update appointment to mark feedback as submitted
      await _firestore.collection('appointments').doc(appointmentId).update({
        'feedbackSubmitted': true,
        'feedbackId': feedbackId,
        'feedbackRating': rating,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create admin notification
      await _createAdminNotification(
        feedbackId: feedbackId,
        feedbackType: feedbackType,
        rating: rating,
        doctorName: doctorName,
        patientName: isAnonymous ? 'Anonymous' : patientName,
      );

      print('✅ Feedback submitted successfully: $feedbackId');
      return feedbackId;
    } catch (e) {
      print('❌ Error submitting feedback: $e');
      throw Exception('Failed to submit feedback: $e');
    }
  }

/// Check if patient has already submitted feedback for this appointment
Future<bool> hasFeedbackForAppointment(String appointmentId) async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final snapshot = await _firestore
        .collection('consultation_feedback')
        .where('appointmentId', isEqualTo: appointmentId)
        .where('patientId', isEqualTo: currentUser.uid) // ✅ ADD THIS LINE
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  } catch (e) {
    print('❌ Error checking feedback status: $e');
    return false;
  }
}

/// Get feedback for a specific appointment
Future<Map<String, dynamic>?> getFeedbackForAppointment(String appointmentId) async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final snapshot = await _firestore
        .collection('consultation_feedback')
        .where('appointmentId', isEqualTo: appointmentId)
        .where('patientId', isEqualTo: currentUser.uid) // ✅ ADD THIS LINE
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    final data = doc.data();
    return {
      'id': doc.id,
      ...data,
      'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
      'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
      'reviewedAt': (data['reviewedAt'] as Timestamp?)?.toDate().toIso8601String(),
    };
  } catch (e) {
    print('❌ Error fetching feedback: $e');
    return null;
  }
}

  /// Get all feedback for a patient
  Future<List<Map<String, dynamic>>> getPatientFeedback(String patientId) async {
    try {
      final snapshot = await _firestore
          .collection('consultation_feedback')
          .where('patientId', isEqualTo: patientId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'reviewedAt': (data['reviewedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();
    } catch (e) {
      print('❌ Error fetching patient feedback: $e');
      return [];
    }
  }

  /// ADMIN: Get all pending feedback (for admin review)
  Future<List<Map<String, dynamic>>> getPendingFeedback() async {
    try {
      final snapshot = await _firestore
          .collection('consultation_feedback')
          .where('status', isEqualTo: statusPending)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();
    } catch (e) {
      print('❌ Error fetching pending feedback: $e');
      return [];
    }
  }

  /// ADMIN: Get all feedback (with filters)
  Future<List<Map<String, dynamic>>> getAllFeedback({
    String? status,
    String? feedbackType,
    String? doctorId,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore.collection('consultation_feedback');

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      if (feedbackType != null) {
        query = query.where('feedbackType', isEqualTo: feedbackType);
      }
      if (doctorId != null) {
        query = query.where('doctorId', isEqualTo: doctorId);
      }

      final snapshot = await query.orderBy('createdAt', descending: true).get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'reviewedAt': (data['reviewedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();
    } catch (e) {
      print('❌ Error fetching all feedback: $e');
      return [];
    }
  }

  /// ADMIN: Approve feedback and optionally share with doctor
  Future<void> approveFeedback({
    required String feedbackId,
    required String adminId,
    required bool shareWithDoctor,
    String? adminNotes,
  }) async {
    try {
      await _firestore.collection('consultation_feedback').doc(feedbackId).update({
        'status': statusApproved,
        'sharedWithDoctor': shareWithDoctor,
        'adminNotes': adminNotes ?? '',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // If sharing with doctor, create notification for doctor
      if (shareWithDoctor) {
        final feedbackDoc = await _firestore
            .collection('consultation_feedback')
            .doc(feedbackId)
            .get();
        
        if (feedbackDoc.exists) {
          final data = feedbackDoc.data()!;
          await _createDoctorNotification(
            feedbackId: feedbackId,
            doctorId: data['doctorId'],
            feedbackType: data['feedbackType'],
            rating: data['rating'],
            patientName: data['patientName'],
          );
        }
      }

      print('✅ Feedback approved: $feedbackId');
    } catch (e) {
      print('❌ Error approving feedback: $e');
      throw Exception('Failed to approve feedback: $e');
    }
  }

  /// ADMIN: Reject feedback
  Future<void> rejectFeedback({
    required String feedbackId,
    required String adminId,
    String? adminNotes,
  }) async {
    try {
      await _firestore.collection('consultation_feedback').doc(feedbackId).update({
        'status': statusRejected,
        'sharedWithDoctor': false,
        'adminNotes': adminNotes ?? '',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Feedback rejected: $feedbackId');
    } catch (e) {
      print('❌ Error rejecting feedback: $e');
      throw Exception('Failed to reject feedback: $e');
    }
  }

  /// ADMIN: Mark feedback as resolved
  Future<void> resolveFeedback({
    required String feedbackId,
    required String adminId,
    String? resolutionNotes,
  }) async {
    try {
      await _firestore.collection('consultation_feedback').doc(feedbackId).update({
        'status': statusResolved,
        'adminNotes': resolutionNotes ?? '',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Feedback marked as resolved: $feedbackId');
    } catch (e) {
      print('❌ Error resolving feedback: $e');
      throw Exception('Failed to resolve feedback: $e');
    }
  }

  /// DOCTOR: Get approved feedback for doctor
  Future<List<Map<String, dynamic>>> getDoctorFeedback(String doctorId) async {
    try {
      final snapshot = await _firestore
          .collection('consultation_feedback')
          .where('doctorId', isEqualTo: doctorId)
          .where('sharedWithDoctor', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
          'updatedAt': (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String(),
        };
      }).toList();
    } catch (e) {
      print('❌ Error fetching doctor feedback: $e');
      return [];
    }
  }

  /// Get feedback statistics for a doctor
  Future<Map<String, dynamic>> getDoctorFeedbackStats(String doctorId) async {
    try {
      final snapshot = await _firestore
          .collection('consultation_feedback')
          .where('doctorId', isEqualTo: doctorId)
          .where('sharedWithDoctor', isEqualTo: true)
          .get();

      final feedbacks = snapshot.docs.map((doc) => doc.data()).toList();

      if (feedbacks.isEmpty) {
        return {
          'totalFeedback': 0,
          'averageRating': 0.0,
          'compliments': 0,
          'complaints': 0,
          'suggestions': 0,
          'ratingDistribution': {5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
        };
      }

      final totalRating = feedbacks.fold<int>(0, (sum, f) => sum + (f['rating'] as int));
      final avgRating = totalRating / feedbacks.length;

      final compliments = feedbacks.where((f) => f['feedbackType'] == typeCompliment).length;
      final complaints = feedbacks.where((f) => f['feedbackType'] == typeComplaint).length;
      final suggestions = feedbacks.where((f) => f['feedbackType'] == typeSuggestion).length;

      final ratingDist = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      for (var f in feedbacks) {
        final rating = f['rating'] as int;
        ratingDist[rating] = (ratingDist[rating] ?? 0) + 1;
      }

      return {
        'totalFeedback': feedbacks.length,
        'averageRating': double.parse(avgRating.toStringAsFixed(1)),
        'compliments': compliments,
        'complaints': complaints,
        'suggestions': suggestions,
        'ratingDistribution': ratingDist,
      };
    } catch (e) {
      print('❌ Error calculating doctor stats: $e');
      return {
        'totalFeedback': 0,
        'averageRating': 0.0,
        'compliments': 0,
        'complaints': 0,
        'suggestions': 0,
        'ratingDistribution': {5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
      };
    }
  }

  /// Create notification for admin
  Future<void> _createAdminNotification({
    required String feedbackId,
    required String feedbackType,
    required int rating,
    required String doctorName,
    required String patientName,
  }) async {
    try {
      // Get all admin users
      final adminsSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      // Create notification for each admin
      for (var adminDoc in adminsSnapshot.docs) {
        await _firestore.collection('notifications').add({
          'userId': adminDoc.id,
          'type': 'new_feedback',
          'priority': feedbackType == typeComplaint ? 'high' : 'normal',
          'title': 'New ${feedbackType.toUpperCase()} Feedback',
          'message': 'From $patientName for Dr. $doctorName ($rating★)',
          'feedbackId': feedbackId,
          'feedbackType': feedbackType,
          'rating': rating,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      print('✅ Admin notification created');
    } catch (e) {
      print('⚠️ Failed to create admin notification: $e');
    }
  }

  /// Create notification for doctor
  Future<void> _createDoctorNotification({
    required String feedbackId,
    required String doctorId,
    required String feedbackType,
    required int rating,
    required String patientName,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': doctorId,
        'type': 'feedback_shared',
        'priority': 'normal',
        'title': 'New Feedback from Admin',
        'message': '$feedbackType from $patientName ($rating★)',
        'feedbackId': feedbackId,
        'feedbackType': feedbackType,
        'rating': rating,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ Doctor notification created');
    } catch (e) {
      print('⚠️ Failed to create doctor notification: $e');
    }
  }
}