import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Doctor Authentication & Profile Service
/// 
/// Handles doctor-specific authentication and profile management
/// Separate from patient authentication
class DoctorAuthService {
  static final DoctorAuthService instance = DoctorAuthService._init();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  DoctorAuthService._init();
  
  // User type constants
  static const String userTypeDoctor = 'doctor';
  static const String userTypePatient = 'patient';
  
  /// Get current logged in user
  User? get currentUser => _auth.currentUser;
  
  /// Check if current user is a doctor
  Future<bool> isDoctor() async {
    final user = currentUser;
    if (user == null) return false;
    
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      
      final data = doc.data()!;
      return data['userType'] == userTypeDoctor;
    } catch (e) {
      print('Error checking user type: $e');
      return false;
    }
  }
  
  /// Doctor signup with additional information
  Future<User?> doctorSignup({
    required String email,
    required String password,
    required String fullName,
    required String specialization,
    required String licenseNumber,
    required String phone,
    required String hospital,
  }) async {
    try {
      // Create Firebase Auth account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      if (user == null) throw Exception('User creation failed');
      
      // Update display name
      await user.updateDisplayName(fullName);
      
      // Create doctor profile in Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'fullName': fullName,
        'userType': userTypeDoctor,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Create detailed doctor profile
      await _firestore.collection('doctor_profiles').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'fullName': fullName,
        'specialization': specialization,
        'licenseNumber': licenseNumber,
        'phone': phone,
        'hospital': hospital,
        'verified': false, // Requires admin verification
        'active': true,
        'rating': 0.0,
        'totalPatients': 0,
        'totalAppointments': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Doctor account created: ${user.uid}');
      return user;
      
    } on FirebaseAuthException catch (e) {
      print('❌ Doctor signup error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      print('❌ Unexpected error during doctor signup: $e');
      rethrow;
    }
  }
  
  /// Doctor login
  Future<User?> doctorLogin({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      if (user == null) throw Exception('Login failed');
      
      // Verify this is a doctor account
      final isDoc = await isDoctor();
      if (!isDoc) {
        await _auth.signOut();
        throw Exception('This account is not registered as a doctor');
      }
      
      // Check if doctor is verified
      final profile = await getDoctorProfile(user.uid);
      if (profile != null && profile['verified'] != true) {
        print('⚠️ Doctor account pending verification');
        // You can choose to allow or block unverified doctors
      }
      
      print('✅ Doctor logged in: ${user.uid}');
      return user;
      
    } on FirebaseAuthException catch (e) {
      print('❌ Doctor login error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      print('❌ Unexpected error during doctor login: $e');
      rethrow;
    }
  }
  
  /// Patient signup (for comparison)
  Future<User?> patientSignup({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      if (user == null) throw Exception('User creation failed');
      
      await user.updateDisplayName(fullName);
      
      // Create patient profile
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'fullName': fullName,
        'userType': userTypePatient,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      await _firestore.collection('patient_profiles').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'fullName': fullName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Patient account created: ${user.uid}');
      return user;
      
    } on FirebaseAuthException catch (e) {
      print('❌ Patient signup error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    }
  }
  
  /// Get doctor profile
  Future<Map<String, dynamic>?> getDoctorProfile(String doctorId) async {
    try {
      final doc = await _firestore.collection('doctor_profiles').doc(doctorId).get();
      if (!doc.exists) return null;
      
      return {
        'uid': doc.id,
        ...doc.data()!,
      };
    } catch (e) {
      print('Error fetching doctor profile: $e');
      return null;
    }
  }
  
  /// Update doctor profile
  Future<void> updateDoctorProfile(String doctorId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('doctor_profiles').doc(doctorId).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Doctor profile updated');
    } catch (e) {
      print('❌ Error updating doctor profile: $e');
      rethrow;
    }
  }
  
  /// Get user type
  Future<String?> getUserType(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;
      
      return doc.data()?['userType'] as String?;
    } catch (e) {
      print('Error getting user type: $e');
      return null;
    }
  }
  
  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    print('✅ User signed out');
  }
  
  /// Handle authentication exceptions
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return Exception('Password is too weak. Use at least 6 characters.');
      case 'email-already-in-use':
        return Exception('An account already exists with this email.');
      case 'invalid-email':
        return Exception('Invalid email address format.');
      case 'user-not-found':
        return Exception('No account found with this email.');
      case 'wrong-password':
        return Exception('Incorrect password.');
      case 'user-disabled':
        return Exception('This account has been disabled.');
      case 'too-many-requests':
        return Exception('Too many login attempts. Please try again later.');
      default:
        return Exception('Authentication error: ${e.message}');
    }
  }
  
  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      print('✅ Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }
  
  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}