import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  // ✅ Lazy getter (Firebase not touched during widget build)
  FirebaseAuth get _auth => FirebaseAuth.instance;

  // Signup with email and password
  // Future<User?> signUp(String email, String password) async {
  //   try {
  //     UserCredential userCred =
  //         await _auth.createUserWithEmailAndPassword(
  //       email: email,
  //       password: password,
  //     );
  //     return userCred.user;
  //   } catch (e) {
  //     print('Signup error: $e');
  //     return null;
  //   }
  // }

  Future<bool> verifyDOBAndResetPassword({
    required String email,
    required DateTime dateOfBirth,
    required String newPassword,
  }) async {
    // Step 1: Find user in Firestore profiles by email
    final query = await FirebaseFirestore.instance
        .collection('profiles')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('user-not-found');
    }

    final profileData = query.docs.first.data();

    // Step 2: Compare dateOfBirth (stored as Firestore Timestamp)
    final storedDOB = (profileData['dateOfBirth'] as Timestamp).toDate();

    final bool dobMatches = storedDOB.year == dateOfBirth.year &&
        storedDOB.month == dateOfBirth.month &&
        storedDOB.day == dateOfBirth.day;

    if (!dobMatches) {
      throw Exception('dob-mismatch');
    }

    // Step 3: Sign in silently to get a user credential, then update password
    // We need to re-authenticate — use a temporary sign-in with a known workaround:
    // Since we can't update password without being signed in,
    // we sign in first (requires current password) OR use Admin SDK.
    // Best approach for client-side: use signInWithEmailAndPassword with a
    // "forgot flow" — we already verified identity via Firestore DOB check,
    // so we update via the currently signed-in user OR prompt them to sign in first.

    // For this flow (user is NOT signed in), we use Firebase's updatePassword
    // after signing them in temporarily. We'll do this differently — see note below.
    throw Exception('use-screen-logic'); // replaced in screen
  }

// Simpler split approach — verify only:
// Future<String> verifyEmailAndDOB({
//   required String email,
//   required DateTime dateOfBirth,
// }) async {
//   final query = await FirebaseFirestore.instance
//       .collection('profiles')
//       .where('email', isEqualTo: email.trim())
//       .limit(1)
//       .get();

//   if (query.docs.isEmpty) throw Exception('user-not-found');

//   final data = query.docs.first.data();
//   final Timestamp storedTimestamp = data['dateOfBirth'] as Timestamp;

//   // ✅ Convert to UTC to avoid timezone shifting the day
//   final storedDOB = storedTimestamp.toDate().toUtc();
//   final enteredDOB = dateOfBirth.toUtc();

//   print('🗓 Stored DOB: ${storedDOB.year}-${storedDOB.month}-${storedDOB.day}');
//   print('🗓 Entered DOB: ${enteredDOB.year}-${enteredDOB.month}-${enteredDOB.day}');

//   if (storedDOB.year != enteredDOB.year ||
//       storedDOB.month != enteredDOB.month ||
//       storedDOB.day != enteredDOB.day) {
//     throw Exception('dob-mismatch');
//   }

//   return query.docs.first.id;
// }

  Future<String?> verifyEmailAndDOB({
    required String email,
    required DateTime dateOfBirth,
  }) async {
    final doc = await FirebaseFirestore.instance
        .collection('recovery_lookup')
        .doc(email.toLowerCase())
        .get();

    if (!doc.exists) throw Exception('user-not-found');

    // Compare DOB
    final storedDOB = (doc.data()!['dob'] as Timestamp).toDate();
    if (storedDOB.day != dateOfBirth.day ||
        storedDOB.month != dateOfBirth.month ||
        storedDOB.year != dateOfBirth.year) {
      throw Exception('dob-mismatch');
    }

    return doc.data()!['uid'];
  }

  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('❌ Sign up error: ${e.code} - ${e.message}');
      rethrow; // ✅ CRITICAL: rethrow so the UI can catch and display it
    } catch (e) {
      print('❌ Unexpected sign up error: $e');
      rethrow; // ✅ Rethrow any other errors too
    }
  }

  // Login with email and password
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential userCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCred.user;
    } on FirebaseAuthException catch (e) {
      print('❌ Sign in error: ${e.code} - ${e.message}');
      rethrow; // ✅ Let LoginScreen catch it and show the right message
    } catch (e) {
      print('❌ Unexpected sign in error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
