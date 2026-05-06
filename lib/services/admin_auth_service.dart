import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Admin Authentication Service
/// 
/// Handles admin-specific authentication
/// Admins have access to doctor management and system settings
class AdminAuthService {
  static final AdminAuthService instance = AdminAuthService._init();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  AdminAuthService._init();
  
  // User type constants
  static const String userTypeAdmin = 'admin';
  
  /// Get current logged in user
  User? get currentUser => _auth.currentUser;
  
  /// Check if current user is an admin
  Future<bool> isAdmin() async {
    final user = currentUser;
    if (user == null) return false;
    
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      
      final data = doc.data()!;
      return data['userType'] == userTypeAdmin;
    } catch (e) {
      print('Error checking user type: $e');
      return false;
    }
  }
  
  /// Admin login
  Future<User?> adminLogin({
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
      
      // Verify this is an admin account
      final isAdminUser = await isAdmin();
      if (!isAdminUser) {
        await _auth.signOut();
        throw Exception('This account does not have admin privileges');
      }
      
      print('✅ Admin logged in: ${user.uid}');
      return user;
      
    } on FirebaseAuthException catch (e) {
      print('❌ Admin login error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      print('❌ Unexpected error during admin login: $e');
      rethrow;
    }
  }
  
  /// Get admin profile
  Future<Map<String, dynamic>?> getAdminProfile(String adminId) async {
    try {
      final doc = await _firestore.collection('users').doc(adminId).get();
      if (!doc.exists) return null;
      
      return {
        'uid': doc.id,
        ...doc.data()!,
      };
    } catch (e) {
      print('Error fetching admin profile: $e');
      return null;
    }
  }
  
  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    print('✅ Admin signed out');
  }
  
  /// Handle authentication exceptions
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return Exception('Invalid email address format.');
      case 'user-not-found':
        return Exception('No admin account found with this email.');
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