import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  String _email = '';
  String _password = '';
  DateTime? _selectedDOB;
  bool _loading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  String _getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'This email is already registered. Please log in instead.';
        case 'invalid-email':
          return 'The email address is not valid.';
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'operation-not-allowed':
          return 'Email/password sign up is not enabled.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        default:
          return 'Sign up failed: ${error.message ?? error.code}';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select your date of birth',
      fieldLabelText: 'Date of Birth',
      fieldHintText: 'DD/MM/YYYY',
    );
    if (picked != null) {
      setState(() {
        _selectedDOB = picked;
        _errorMessage = '';
      });
    }
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDOB == null) {
      setState(() => _errorMessage = 'Please select your date of birth.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      final user = await _authService.signUp(_email.trim(), _password);

      if (user != null) {
        final emailKey = _email.trim().toLowerCase();

        // ✅ Save to profiles collection
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .set({
          'email': emailKey,
          'dateOfBirth': Timestamp.fromDate(_selectedDOB!),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // ✅ Save to recovery_lookup so forgot-password works
        await FirebaseFirestore.instance
            .collection('recovery_lookup')
            .doc(emailKey)
            .set({
          'uid': user.uid,
          'dob': Timestamp.fromDate(_selectedDOB!),
        });

        setState(() => _loading = false);

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = _getErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        height: size.height,
        width: size.width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.withOpacity(0.7),
              Colors.blue.withOpacity(0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Card(
              elevation: 8,
              color: Colors.white.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Email Field ──────────────────────────────────────
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) => val == null || val.isEmpty
                            ? 'Enter an email'
                            : null,
                        onChanged: (val) => setState(() => _email = val),
                      ),
                      const SizedBox(height: 15),

                      // ── Password Field ───────────────────────────────────
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (val) => val == null || val.length < 6
                            ? 'Password too short'
                            : null,
                        onChanged: (val) => setState(() => _password = val),
                      ),
                      const SizedBox(height: 15),

                      // ── Date of Birth Picker ─────────────────────────────
                      GestureDetector(
                        onTap: _pickDOB,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _selectedDOB == null
                                  ? Colors.grey
                                  : Colors.deepPurple,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: _selectedDOB == null
                                    ? Colors.grey
                                    : Colors.deepPurple,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _selectedDOB == null
                                    ? 'Select Date of Birth'
                                    : '${_selectedDOB!.day.toString().padLeft(2, '0')} / '
                                        '${_selectedDOB!.month.toString().padLeft(2, '0')} / '
                                        '${_selectedDOB!.year}',
                                style: TextStyle(
                                  color: _selectedDOB == null
                                      ? Colors.grey
                                      : Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Sign Up Button ───────────────────────────────────
                      _loading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _handleSignUp,
                                child: const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(height: 10),

                      // ── Error Message ────────────────────────────────────
                      if (_errorMessage.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        child: const Text(
                          "Already have an account? Log in",
                          style: TextStyle(color: Colors.deepPurple),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
