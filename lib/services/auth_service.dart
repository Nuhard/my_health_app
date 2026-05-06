import 'package:firebase_auth/firebase_auth.dart';

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
