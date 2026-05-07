import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  String _email = '';
  DateTime? _selectedDOB;
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String _errorMessage = '';
  String _successMessage = '';

  bool _dobVerified = false;
  String? _verifiedUid;

  // Step 1: Verify email + DOB
  Future<void> _verifyIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDOB == null) {
      setState(() => _errorMessage = 'Please select your date of birth');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      final uid = await _authService.verifyEmailAndDOB(
        email: _email,
        dateOfBirth: _selectedDOB!,
      );
      setState(() {
        _loading = false;
        _dobVerified = true;
        _verifiedUid = uid;
      });
    } catch (e) {
      final msg = e.toString();
      debugPrint('❌ verifyIdentity error: $msg');
      setState(() {
        _loading = false;
        if (msg.contains('user-not-found')) {
          _errorMessage = 'No account found with this email';
        } else if (msg.contains('dob-mismatch')) {
          _errorMessage = 'Date of birth does not match our records';
        } else {
          _errorMessage = 'Verification failed. Please try again.';
        }
      });
    }
  }

  // Step 2: Send Firebase password reset email
  Future<void> _resetPassword() async {
    if (_email.trim().isEmpty) {
      setState(() => _errorMessage = 'Email is missing. Please go back.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      debugPrint('📧 Sending reset email to: $_email');

      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.trim());

      debugPrint('✅ Reset email sent successfully');

      // ✅ Must call setState AFTER await completes
      if (mounted) {
        setState(() {
          _loading = false;
          _successMessage =
              'A password reset link has been sent to $_email. Please check your inbox.';
        });
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ FirebaseAuthException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          switch (e.code) {
            case 'user-not-found':
              _errorMessage = 'No account found with this email.';
              break;
            case 'invalid-email':
              _errorMessage = 'Invalid email address.';
              break;
            case 'too-many-requests':
              _errorMessage = 'Too many attempts. Please try again later.';
              break;
            default:
              _errorMessage = 'Failed to send reset email: ${e.message}';
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Unexpected error: ${e.toString()}';
        });
      }
    }
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
              Colors.blue.withOpacity(0.7),
              Colors.purple.withOpacity(0.7),
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
                child: _dobVerified ? _buildStep2() : _buildStep1(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Email + DOB ───────────────────────────────────────────────────
  Widget _buildStep1() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_reset, size: 48, color: Colors.deepPurple),
          const SizedBox(height: 12),
          const Text(
            'Forgot Password',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter your email and date of birth to verify your identity',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Email field
          TextFormField(
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (val) =>
                val == null || val.isEmpty ? 'Enter your email' : null,
            onChanged: (val) => setState(() => _email = val.trim()),
          ),
          const SizedBox(height: 16),

          // DOB picker
          GestureDetector(
            onTap: _pickDOB,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.grey),
                  const SizedBox(width: 12),
                  Text(
                    _selectedDOB == null
                        ? 'Select Date of Birth'
                        : '${_selectedDOB!.day.toString().padLeft(2, '0')} / '
                            '${_selectedDOB!.month.toString().padLeft(2, '0')} / '
                            '${_selectedDOB!.year}',
                    style: TextStyle(
                      color:
                          _selectedDOB == null ? Colors.grey : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style:
                            TextStyle(color: Colors.red.shade800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          _loading
              ? const CircularProgressIndicator()
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _verifyIdentity,
                    child: const Text(
                      'Verify Identity',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Step 2: Send reset email ──────────────────────────────────────────────
  Widget _buildStep2() {
    // ✅ Success state
    if (_successMessage.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'Check your email',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _successMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text('Back to Login'),
            ),
          ),
        ],
      );
    }

    // ✅ Pre-send state
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_user, size: 48, color: Colors.green),
        const SizedBox(height: 12),
        const Text(
          'Identity Verified!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'ll send a password reset link to\n$_email',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 24),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style:
                          TextStyle(color: Colors.red.shade800, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _loading
            ? const CircularProgressIndicator()
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _resetPassword, // ✅ Direct method reference
                  child: const Text(
                    'Send Reset Link',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
      ],
    );
  }
}
