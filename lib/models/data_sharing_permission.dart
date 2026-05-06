import 'package:cloud_firestore/cloud_firestore.dart';

/// Data Sharing Permission Model
/// 
/// Manages patient's consent for sharing health data with specific doctors
/// Supports granular permissions for different data categories
class DataSharingPermission {
  final String id;
  final String patientId;
  final String doctorId;
  final String? doctorAuthUid; // ✅ NEW: Firebase Auth UID of doctor
  final String appointmentId;
  final Map<String, bool> permissions;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime requestedAt;
  final String status; // 'pending', 'approved', 'rejected'
  final String? notes;

  DataSharingPermission({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.doctorAuthUid, // ✅ NEW: Optional parameter
    required this.appointmentId,
    required this.permissions,
    this.approvedAt,
    this.rejectedAt,
    required this.requestedAt,
    required this.status,
    this.notes,
  });

  // Permission category constants
  static const String BASIC_INFO = 'basic_info';
  static const String NUTRITION_LOGS = 'nutrition_logs';
  static const String SYMPTOM_HISTORY = 'symptom_history';
  static const String ACTIVITY_DATA = 'activity_data';
  static const String HEALTH_SCORES = 'health_scores';
  static const String MEDICAL_HISTORY = 'medical_history';
  static const String LAB_REPORTS = 'lab_reports';

  // Status constants
  static const String STATUS_PENDING = 'pending';
  static const String STATUS_APPROVED = 'approved';
  static const String STATUS_REJECTED = 'rejected';

  /// Check if a specific data category is allowed to be shared
  bool isAllowed(String category) {
    return status == STATUS_APPROVED && (permissions[category] ?? false);
  }

  /// Get list of all allowed categories
  List<String> get allowedCategories {
    if (status != STATUS_APPROVED) return [];
    return permissions.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'patientId': patientId,
      'doctorId': doctorId,
      'doctorAuthUid': doctorAuthUid, // ✅ NEW: Save to Firestore
      'appointmentId': appointmentId,
      'permissions': permissions,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'status': status,
      'notes': notes,
    };
  }

  /// Create from Firestore document
  factory DataSharingPermission.fromFirestore(String id, Map<String, dynamic> data) {
    return DataSharingPermission(
      id: id,
      patientId: data['patientId'] ?? '',
      doctorId: data['doctorId'] ?? '',
      doctorAuthUid: data['doctorAuthUid'], // ✅ NEW: Read from Firestore
      appointmentId: data['appointmentId'] ?? '',
      permissions: Map<String, bool>.from(data['permissions'] ?? {}),
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      rejectedAt: data['rejectedAt'] != null
          ? (data['rejectedAt'] as Timestamp).toDate()
          : null,
      requestedAt: data['requestedAt'] != null
          ? (data['requestedAt'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? STATUS_PENDING,
      notes: data['notes'],
    );
  }

  /// Create a copy with updated fields
  DataSharingPermission copyWith({
    String? id,
    String? patientId,
    String? doctorId,
    String? doctorAuthUid, // ✅ NEW
    String? appointmentId,
    Map<String, bool>? permissions,
    DateTime? approvedAt,
    DateTime? rejectedAt,
    DateTime? requestedAt,
    String? status,
    String? notes,
  }) {
    return DataSharingPermission(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      doctorId: doctorId ?? this.doctorId,
      doctorAuthUid: doctorAuthUid ?? this.doctorAuthUid, // ✅ NEW
      appointmentId: appointmentId ?? this.appointmentId,
      permissions: permissions ?? this.permissions,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      requestedAt: requestedAt ?? this.requestedAt,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  /// Get human-readable label for permission category
  static String getCategoryLabel(String category) {
    switch (category) {
      case BASIC_INFO:
        return 'Basic Information (Name, Age, Gender)';
      case NUTRITION_LOGS:
        return 'Nutrition & Food Logs';
      case SYMPTOM_HISTORY:
        return 'Symptom History';
      case ACTIVITY_DATA:
        return 'Activity & Exercise Data';
      case HEALTH_SCORES:
        return 'Health Scores & Analysis';
      case MEDICAL_HISTORY:
        return 'Medical History';
      case LAB_REPORTS:
        return 'Lab Reports & Documents';
      default:
        return category;
    }
  }

  /// Get icon for permission category
  static String getCategoryIcon(String category) {
    switch (category) {
      case BASIC_INFO:
        return '👤';
      case NUTRITION_LOGS:
        return '🍽️';
      case SYMPTOM_HISTORY:
        return '🩺';
      case ACTIVITY_DATA:
        return '🏃';
      case HEALTH_SCORES:
        return '📊';
      case MEDICAL_HISTORY:
        return '📋';
      case LAB_REPORTS:
        return '📄';
      default:
        return '📁';
    }
  }

  /// Create default permission set (all unchecked)
  static Map<String, bool> createDefaultPermissions() {
    return {
      BASIC_INFO: false,
      NUTRITION_LOGS: false,
      SYMPTOM_HISTORY: false,
      ACTIVITY_DATA: false,
      HEALTH_SCORES: false,
      MEDICAL_HISTORY: false,
      LAB_REPORTS: false,
    };
  }

  /// ✅ UPDATED: Create permission request for new appointment
  static DataSharingPermission createRequest({
    required String patientId,
    required String doctorId,
    required String doctorAuthUid, // ✅ NEW: Required parameter
    required String appointmentId,
  }) {
    return DataSharingPermission(
      id: '${appointmentId}_$patientId',
      patientId: patientId,
      doctorId: doctorId,
      doctorAuthUid: doctorAuthUid, // ✅ NEW: Store Auth UID
      appointmentId: appointmentId,
      permissions: createDefaultPermissions(),
      requestedAt: DateTime.now(),
      status: STATUS_PENDING,
    );
  }
}