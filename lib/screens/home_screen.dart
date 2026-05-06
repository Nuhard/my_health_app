import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../providers/sync_provider.dart';
import 'profile_screen.dart';
import 'health_log.dart';
import 'symptom_checker.dart';
import 'appointments_screen.dart';
import '../widgets/sync_status_widget.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  bool profileExists = false;
  bool isLoading = true;
  Map<String, dynamic>? profileData;
  bool _showMedicalInfo = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SyncProvider>(context, listen: false).checkUnsyncedItems();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkProfile() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection("profiles").doc(user!.uid).get();
      setState(() {
        profileExists = doc.exists;
        profileData = doc.data();
        isLoading = false;
      });
    }
  }

  Widget _buildProfileCard() {
    if (!profileExists || profileData == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Hello,", style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          Text(user?.displayName ?? user?.email ?? "User",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.deepPurple, width: 2)),
              child: CircleAvatar(
                radius: 35,
                backgroundImage: profileData!['profilePhotoBase64'] != null && profileData!['profilePhotoBase64'].toString().isNotEmpty
                    ? MemoryImage(base64Decode(profileData!['profilePhotoBase64']))
                    : null,
                backgroundColor: Colors.deepPurple.shade200,
                child: (profileData!['profilePhotoBase64'] == null || profileData!['profilePhotoBase64'].toString().isEmpty)
                    ? const Icon(Icons.person, size: 40, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profileData!["name"] ?? "User",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  const SizedBox(height: 6),
                  _buildCompactInfoRow(Icons.cake, "Age: ${profileData!["age"] ?? '-'}"),
                  _buildCompactInfoRow(Icons.person, "Gender: ${profileData!["gender"] ?? '-'}"),
                  _buildCompactInfoRow(Icons.monitor_weight, "Weight: ${profileData!["weight"] ?? '-'} kg"),
                  _buildCompactInfoRow(Icons.height, "Height: ${profileData!["height"] ?? '-'} cm"),
                  if (profileData!['bmi'] != null && profileData!['bmi'] > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.favorite, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 5),
                        Text("BMI: ${profileData!['bmi'].toStringAsFixed(1)}", style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _getBMIColor(profileData!['bmi']), borderRadius: BorderRadius.circular(10)),
                          child: Text(profileData!['bmiCategory'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (_hasMedicalInfo() || _hasEmergencyContact()) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          InkWell(
            onTap: () => setState(() => _showMedicalInfo = !_showMedicalInfo),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(_showMedicalInfo ? Icons.expand_less : Icons.expand_more, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 8),
                  Text(_showMedicalInfo ? "Hide Medical Info" : "Show Medical Info",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.deepPurple)),
                  const Spacer(),
                  if (_hasMedicalInfo()) Icon(Icons.medical_services, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  if (_hasEmergencyContact()) Icon(Icons.emergency, size: 16, color: Colors.grey[600]),
                ],
              ),
            ),
          ),
          if (_showMedicalInfo) ...[
            const SizedBox(height: 8),
            if (_hasMedicalInfo()) ...[
              if (profileData!['bloodGroup'] != null && profileData!['bloodGroup'].toString().isNotEmpty)
                _buildGreyInfoRow(Icons.bloodtype, 'Blood Group', profileData!['bloodGroup']),
              if (profileData!['allergies'] != null && profileData!['allergies'].toString().isNotEmpty)
                _buildGreyInfoRow(Icons.warning_amber, 'Allergies', profileData!['allergies']),
              if (profileData!['chronicConditions'] != null && profileData!['chronicConditions'].toString().isNotEmpty)
                _buildGreyInfoRow(Icons.healing, 'Chronic Conditions', profileData!['chronicConditions']),
              if (profileData!['currentMedications'] != null && profileData!['currentMedications'].toString().isNotEmpty)
                _buildGreyInfoRow(Icons.medication, 'Medications', profileData!['currentMedications']),
            ],
            if (_hasEmergencyContact()) ...[
              if (_hasMedicalInfo()) const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _buildGreyInfoRow(Icons.emergency, 'Emergency Contact',
                  "${profileData!['emergencyContactName']} • ${profileData!['emergencyContactPhone'] ?? ''}"),
            ],
          ],
        ],
        
        // ✅ ADD THIS: Health Summary Download Hint
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.download_rounded, size: 18, color: Colors.deepPurple.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You can download your comprehensive health summary from the Profile screen',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.deepPurple.shade700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildGreyInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasMedicalInfo() {
    if (profileData == null) return false;
    return (profileData!['bloodGroup'] != null && profileData!['bloodGroup'].toString().isNotEmpty) ||
        (profileData!['allergies'] != null && profileData!['allergies'].toString().isNotEmpty) ||
        (profileData!['chronicConditions'] != null && profileData!['chronicConditions'].toString().isNotEmpty) ||
        (profileData!['currentMedications'] != null && profileData!['currentMedications'].toString().isNotEmpty);
  }

  bool _hasEmergencyContact() {
    if (profileData == null) return false;
    return profileData!['emergencyContactName'] != null && profileData!['emergencyContactName'].toString().isNotEmpty;
  }

  Widget _buildCustomCard({
    required Color avatarColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(radius: 35, backgroundColor: avatarColor, child: Icon(icon, size: 40, color: Colors.white)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 28, color: Colors.deepPurple), onPressed: onPressed)
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await AuthService().signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),




 // ========== ADD THIS FLOATING ACTION BUTTON ==========
    // floatingActionButton: FloatingActionButton.extended(
    //   onPressed: () async {
    //     await NotificationService.instance.showNotification(
    //       title: '🎉 Test Notification',
    //       body: 'If you see this, notifications are working perfectly!',
    //     );
        
    //     if (mounted) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(
    //           content: Text('✅ Notification sent! Check your notification panel.'),
    //           backgroundColor: Colors.green,
    //           duration: Duration(seconds: 2),
    //         ),
    //       );
    //     }
    //   },
    //   icon: const Icon(Icons.notifications_active),
    //   label: const Text('Test'),
    //   backgroundColor: Colors.deepPurple,
    //   tooltip: 'Test Notification',
    // ),
    // floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    // ====================================================



      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade300, Colors.purple.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    const Text("🌱 Welcome to your Health Dashboard",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 244, 242, 242)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        children: [
                          const Text("Your health is your greatest wealth. 🌿",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.deepPurple),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text("Track your habits, stay active, and nourish your body and mind daily to feel your best!",
                              style: TextStyle(fontSize: 14, color: Colors.grey[800]), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SyncStatusWidget(),
              const SizedBox(height: 5),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8,
                color: Colors.white.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildProfileCard()),
                      IconButton(
                        icon: Icon(profileExists ? Icons.edit : Icons.add, color: Colors.deepPurple),
                        tooltip: profileExists ? "Edit Profile" : "Create Profile",
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileForm(existingData: profileData)))
                              .then((_) => _checkProfile());
                        },
                      ),
                    ],
                  ),
                ),
              ),
              _buildCustomCard(
                avatarColor: Colors.orange.shade400,
                icon: Icons.health_and_safety,
                title: "Health Logs",
                subtitle: "Track your meals, activity, weight & mood daily.",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HealthLogScreen())),
              ),
              _buildCustomCard(
                avatarColor: Colors.red.shade400,
                icon: Icons.medical_services,
                title: "Symptom Checker",
                subtitle: "Log symptoms & check severity.",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SymptomCheckerScreen())),
              ),
              _buildCustomCard(
                avatarColor: Colors.blue.shade400,
                icon: Icons.calendar_month,
                title: "Appointments",
                subtitle: "Book consultations with doctors.",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AppointmentsScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getBMIColor(double bmi) {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return Colors.green;
    if (bmi < 30) return Colors.orange;
    return Colors.red;
  }
}