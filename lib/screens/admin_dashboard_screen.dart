import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin/register_doctors.dart';
import '../services/admin_auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/consultation_feedback_service.dart';
import 'admin_feedback_screen.dart';
import 'admin_analytics_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _authService = AdminAuthService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _isRegistering = false;
  bool _isLoadingStats = true;
  String _statusMessage = '';
  List<Map<String, dynamic>> _credentials = [];
  Map<String, int> _stats = {'total': 0, 'registered': 0, 'pending': 0, 'thisMonth': 0};
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _selectedFilterType = 'all';
  int _pendingFeedbackCount = 0;
  int _totalFeedbackCount = 0;
  bool _isLoadingFeedback = false;

  int _totalPatients = 0;
  int _totalAppointments = 0;
  bool _isLoadingQuickStats = true;

  // ── Doctor list search, expand & pagination ─────────────
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedDoctorIds = {};
  int _currentPage = 0;
  static const int _pageSize = 6;

  // ── Add doctor form ───────────────────────────────────────
  final _nameController = TextEditingController();
  final _specializationController = TextEditingController();
  final _qualificationsController = TextEditingController();
  final _experienceController = TextEditingController();
  final _consultationFeeController = TextEditingController();
  final _locationController = TextEditingController();
  final _hospitalController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  List<String> _selectedDays = [];
  List<String> _selectedTimeSlots = [];

  // ── Edit doctor form ──────────────────────────────────────
  final _editFormKey = GlobalKey<FormState>();
  final _editNameController = TextEditingController();
  final _editSpecializationController = TextEditingController();
  final _editQualificationsController = TextEditingController();
  final _editExperienceController = TextEditingController();
  final _editFeeController = TextEditingController();
  final _editLocationController = TextEditingController();
  final _editHospitalController = TextEditingController();
  final _editPhoneController = TextEditingController();
  final _editBioController = TextEditingController();
  List<String> _editSelectedDays = [];
  List<String> _editSelectedTimeSlots = [];

  final List<String> _allDays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];

  final List<String> _allTimeSlots = [
    '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM',
    '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
    '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM',
    '02:00 PM', '02:30 PM', '03:00 PM', '03:30 PM',
    '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM',
    '06:00 PM'
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _qualificationsController.dispose();
    _experienceController.dispose();
    _consultationFeeController.dispose();
    _locationController.dispose();
    _hospitalController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _editNameController.dispose();
    _editSpecializationController.dispose();
    _editQualificationsController.dispose();
    _editExperienceController.dispose();
    _editFeeController.dispose();
    _editLocationController.dispose();
    _editHospitalController.dispose();
    _editPhoneController.dispose();
    _editBioController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadStats(),
      _loadCredentials(),
      _loadFeedbackStats(),
      _loadQuickStats(),
    ]);
  }

  Future<void> _loadQuickStats() async {
    setState(() => _isLoadingQuickStats = true);
    try {
      final profiles = await FirebaseFirestore.instance.collection('profiles').get();
      final appointments = await FirebaseFirestore.instance.collection('appointments').get();
      setState(() {
        _totalPatients = profiles.docs.length;
        _totalAppointments = appointments.docs.length;
        _isLoadingQuickStats = false;
      });
    } catch (e) {
      print('Error loading quick stats: $e');
      setState(() => _isLoadingQuickStats = false);
    }
  }

  Future<void> _loadFeedbackStats() async {
    setState(() => _isLoadingFeedback = true);
    try {
      final allFeedback = await ConsultationFeedbackService.instance.getAllFeedback();
      final pendingFeedback = await ConsultationFeedbackService.instance.getPendingFeedback();
      setState(() {
        _totalFeedbackCount = allFeedback.length;
        _pendingFeedbackCount = pendingFeedback.length;
        _isLoadingFeedback = false;
      });
    } catch (e) {
      print('Error loading feedback stats: $e');
      setState(() => _isLoadingFeedback = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final stats = await DoctorRegistration.getRegistrationStats();
      setState(() {
        _stats = stats;
        _isLoadingStats = false;
      });
    } catch (e) {
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadCredentials() async {
    try {
      final creds = await DoctorRegistration.getDoctorCredentials();
      setState(() => _credentials = creds);
    } catch (e) {
      print('Error loading credentials: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredCredentials {
    var list = _credentials;
    // Date filter
    if (_selectedFilterType != 'all') {
      list = list.where((cred) {
        final registeredAt = cred['registeredAt'];
        if (registeredAt == null) return false;
        DateTime date;
        if (registeredAt is Timestamp) {
          date = registeredAt.toDate();
        } else {
          return false;
        }
        if (_filterStartDate != null && date.isBefore(_filterStartDate!)) return false;
        if (_filterEndDate != null && date.isAfter(_filterEndDate!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
    }
    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((cred) =>
        cred['name'].toString().toLowerCase().contains(q) ||
        cred['email'].toString().toLowerCase().contains(q) ||
        (cred['originalId'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }
    return list;
  }

  void _applyQuickFilter(String filterType) {
    final now = DateTime.now();
    setState(() {
      _selectedFilterType = filterType;
      _currentPage = 0;
      switch (filterType) {
        case 'today':
          _filterStartDate = DateTime(now.year, now.month, now.day);
          _filterEndDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          final startOfWeek = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _filterStartDate = startOfWeek;
          _filterEndDate = DateTime(now.year, now.month, now.day);
          break;
        case 'month':
          _filterStartDate = DateTime(now.year, now.month, 1);
          _filterEndDate = DateTime(now.year, now.month, now.day);
          break;
        case 'all':
          _filterStartDate = null;
          _filterEndDate = null;
          break;
      }
    });
  }

  Future<void> _showCustomDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _filterStartDate != null && _filterEndDate != null
          ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.deepOrange,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedFilterType = 'custom';
        _filterStartDate = picked.start;
        _filterEndDate = picked.end;
      });
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is Map && timestamp.containsKey('_seconds')) {
        date = DateTime.fromMillisecondsSinceEpoch((timestamp['_seconds'] as int) * 1000);
      } else if (timestamp is Map && timestamp.containsKey('seconds')) {
        date = DateTime.fromMillisecondsSinceEpoch((timestamp['seconds'] as int) * 1000);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'Unknown';
      }
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _showAddDoctorDialog() async {
    _selectedDays = [];
    _selectedTimeSlots = [];
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Register New Doctor'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name', hintText: 'Dr. John Doe',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _specializationController,
                    decoration: const InputDecoration(
                      labelText: 'Specialization', hintText: 'Cardiologist',
                      prefixIcon: Icon(Icons.medical_services),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qualificationsController,
                    decoration: const InputDecoration(
                      labelText: 'Qualifications', hintText: 'MBBS, MD',
                      prefixIcon: Icon(Icons.school),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _experienceController,
                    decoration: const InputDecoration(
                      labelText: 'Years of Experience', prefixIcon: Icon(Icons.work),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _consultationFeeController,
                    decoration: const InputDecoration(
                      labelText: 'Consultation Fee (LKR)', prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location', hintText: 'Colombo 07',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hospitalController,
                    decoration: const InputDecoration(
                      labelText: 'Hospital/Clinic', prefixIcon: Icon(Icons.local_hospital),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone', hintText: '+94 77 123 4567',
                      prefixIcon: Icon(Icons.phone),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Available Days', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _allDays.map((day) => FilterChip(
                      label: Text(day),
                      selected: _selectedDays.contains(day),
                      onSelected: (selected) => setDialogState(() {
                        if (selected) _selectedDays.add(day); else _selectedDays.remove(day);
                      }),
                      selectedColor: Colors.deepOrange.shade100,
                      checkmarkColor: Colors.deepOrange,
                    )).toList(),
                  ),
                  if (_selectedDays.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Please select at least one day',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),
                  const Text('Available Time Slots', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _allTimeSlots.map((slot) => FilterChip(
                          label: Text(slot),
                          selected: _selectedTimeSlots.contains(slot),
                          onSelected: (selected) => setDialogState(() {
                            if (selected) _selectedTimeSlots.add(slot); else _selectedTimeSlots.remove(slot);
                          }),
                          selectedColor: Colors.deepOrange.shade100,
                          checkmarkColor: Colors.deepOrange,
                        )).toList(),
                      ),
                    ),
                  ),
                  if (_selectedTimeSlots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Please select at least one time slot',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio', hintText: 'Brief description...',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 3,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { _clearForm(); Navigator.pop(context); },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _registerNewDoctor,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange, foregroundColor: Colors.white,
              ),
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearForm() {
    _nameController.clear();
    _specializationController.clear();
    _qualificationsController.clear();
    _experienceController.clear();
    _consultationFeeController.clear();
    _locationController.clear();
    _hospitalController.clear();
    _phoneController.clear();
    _bioController.clear();
    _selectedDays = [];
    _selectedTimeSlots = [];
  }

  Future<void> _registerNewDoctor() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one available day'), backgroundColor: Colors.red,
      ));
      return;
    }
    if (_selectedTimeSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one time slot'), backgroundColor: Colors.red,
      ));
      return;
    }
    Navigator.pop(context);
    setState(() { _isRegistering = true; _statusMessage = 'Registering new doctor...'; });
    try {
      final nextId = _stats['registered']! + 1;
      final doctorId = 'DOC${nextId.toString().padLeft(3, '0')}';
      final doctorData = {
        'id': doctorId,
        'name': _nameController.text.trim(),
        'specialization': _specializationController.text.trim(),
        'qualifications': _qualificationsController.text.trim(),
        'experience_years': int.parse(_experienceController.text.trim()),
        'rating': 4.5,
        'consultation_fee': int.parse(_consultationFeeController.text.trim()),
        'available_days': _selectedDays,
        'available_time_slots': _selectedTimeSlots,
        'location': _locationController.text.trim(),
        'hospital': _hospitalController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': '$doctorId@nutritrack.lk',
        'languages': ['English', 'Sinhala'],
        'expertise': [],
        'bio': _bioController.text.trim(),
      };
      await DoctorRegistration.registerSingleDoctor(doctorData);
      await _loadStats();
      await _loadCredentials();
      setState(() => _statusMessage = '✅ Successfully registered ${_nameController.text}!');
      _clearForm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Doctor registered successfully!'), backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() => _statusMessage = '❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: Colors.red,
        ));
      }
    } finally {
      setState(() => _isRegistering = false);
    }
  }

  // ── EDIT DOCTOR ───────────────────────────────────────────

  /// ✅ FIXED: Try document ID first, then query by 'id' field, then query by 'doctorId' field
  Future<void> _showEditDoctorDialog(Map<String, dynamic> cred) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final doctorId = cred['originalId']?.toString() ?? '';

      print('🔍 Attempting to find doctor with id: "$doctorId"');
      print('🔍 Full cred object: $cred');

      if (doctorId.isEmpty) {
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Doctor ID is missing'), backgroundColor: Colors.red),
        );
        return;
      }

      DocumentSnapshot? docSnap;
      DocumentReference? docRef;

      // ── Strategy 1: Query doctor_profiles by 'doctorId' field ──
      // (confirmed from Firestore: collection=doctor_profiles, field=doctorId)
      try {
        final querySnap = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .where('doctorId', isEqualTo: doctorId)
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          print('✅ Found in doctor_profiles by doctorId: $doctorId');
          docSnap = querySnap.docs.first;
          docRef = querySnap.docs.first.reference;
        }
      } catch (e) {
        print('⚠️ doctor_profiles query by doctorId failed: $e');
      }

      // ── Strategy 2: Direct document ID in doctor_profiles ──
      if (docSnap == null) {
        try {
          final directSnap = await FirebaseFirestore.instance
              .collection('doctor_profiles')
              .doc(doctorId)
              .get();
          if (directSnap.exists) {
            print('✅ Found in doctor_profiles by doc ID: $doctorId');
            docSnap = directSnap;
            docRef = directSnap.reference;
          }
        } catch (e) {
          print('⚠️ doctor_profiles direct doc fetch failed: $e');
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      if (docSnap == null || docRef == null) {
        // Show a more helpful error with debug info
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Doctor not found. ID searched: "$doctorId". Check Firestore collection name.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      final data = docSnap.data() as Map<String, dynamic>;

      // Pre-fill edit controllers
      // Field names confirmed from Firestore screenshot:
      // fullName, doctorId, experienceYears, consultationFee, specialization, hospital, bio
      _editNameController.text = (data['fullName'] ?? data['name'] ?? '').toString();
      _editSpecializationController.text = (data['specialization'] ?? '').toString();
      _editQualificationsController.text = (data['qualifications'] ?? '').toString();
      _editExperienceController.text = (data['experienceYears'] ?? data['experience_years'] ?? '').toString();
      _editFeeController.text = (data['consultationFee'] ?? data['consultation_fee'] ?? '').toString();
      _editLocationController.text = (data['location'] ?? '').toString();
      _editHospitalController.text = (data['hospital'] ?? '').toString();
      _editPhoneController.text = (data['phone'] ?? '').toString();
      _editBioController.text = (data['bio'] ?? '').toString();
      _editSelectedDays = List<String>.from(data['availableDays'] ?? data['available_days'] ?? []);
      _editSelectedTimeSlots = List<String>.from(data['availableTimeSlots'] ?? data['available_time_slots'] ?? []);

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(Icons.edit, color: Colors.deepOrange, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('Edit Doctor', style: TextStyle(fontSize: 18))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(doctorId,
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                  key: _editFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editSectionHeader('Basic Information', Icons.person),
                      const SizedBox(height: 10),
                      _editField(_editNameController, 'Full Name', Icons.person, required: true),
                      const SizedBox(height: 10),
                      _editField(_editSpecializationController, 'Specialization', Icons.medical_services, required: true),
                      const SizedBox(height: 10),
                      _editField(_editQualificationsController, 'Qualifications', Icons.school, required: true),
                      const SizedBox(height: 10),
                      _editField(_editExperienceController, 'Years of Experience', Icons.work,
                          keyboardType: TextInputType.number, required: true),
                      const SizedBox(height: 10),
                      _editField(_editFeeController, 'Consultation Fee (LKR)', Icons.attach_money,
                          keyboardType: TextInputType.number, required: true),
                      const SizedBox(height: 16),
                      _editSectionHeader('Location & Contact', Icons.location_on),
                      const SizedBox(height: 10),
                      _editField(_editLocationController, 'Location', Icons.location_on, required: true),
                      const SizedBox(height: 10),
                      _editField(_editHospitalController, 'Hospital / Clinic', Icons.local_hospital, required: true),
                      const SizedBox(height: 10),
                      _editField(_editPhoneController, 'Phone', Icons.phone, required: true),
                      const SizedBox(height: 16),
                      _editSectionHeader('Available Days', Icons.calendar_today),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _allDays.map((day) => FilterChip(
                          label: Text(day, style: const TextStyle(fontSize: 12)),
                          selected: _editSelectedDays.contains(day),
                          onSelected: (selected) => setDialogState(() {
                            if (selected) _editSelectedDays.add(day);
                            else _editSelectedDays.remove(day);
                          }),
                          selectedColor: Colors.deepOrange.shade100,
                          checkmarkColor: Colors.deepOrange,
                        )).toList(),
                      ),
                      if (_editSelectedDays.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Select at least one day',
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                        ),
                      const SizedBox(height: 16),
                      _editSectionHeader('Available Time Slots', Icons.access_time),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _allTimeSlots.map((slot) => FilterChip(
                              label: Text(slot, style: const TextStyle(fontSize: 11)),
                              selected: _editSelectedTimeSlots.contains(slot),
                              onSelected: (selected) => setDialogState(() {
                                if (selected) _editSelectedTimeSlots.add(slot);
                                else _editSelectedTimeSlots.remove(slot);
                              }),
                              selectedColor: Colors.deepOrange.shade100,
                              checkmarkColor: Colors.deepOrange,
                            )).toList(),
                          ),
                        ),
                      ),
                      if (_editSelectedTimeSlots.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Select at least one time slot',
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                        ),
                      const SizedBox(height: 16),
                      _editSectionHeader('About', Icons.description),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _editBioController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Bio',
                          hintText: 'Brief description...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => _saveEditedDoctor(context, docRef!),
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading doctor: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveEditedDoctor(BuildContext dialogContext, DocumentReference docRef) async {
    if (!_editFormKey.currentState!.validate()) return;
    if (_editSelectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one day'), backgroundColor: Colors.red,
      ));
      return;
    }
    if (_editSelectedTimeSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select at least one time slot'), backgroundColor: Colors.red,
      ));
      return;
    }

    Navigator.of(dialogContext).pop();
    setState(() => _statusMessage = 'Saving changes...');

    try {
      // Update using field names confirmed from Firestore (camelCase)
      await docRef.update({
        'fullName': _editNameController.text.trim(),
        'specialization': _editSpecializationController.text.trim(),
        'qualifications': _editQualificationsController.text.trim(),
        'experienceYears': int.tryParse(_editExperienceController.text.trim()) ?? 0,
        'consultationFee': int.tryParse(_editFeeController.text.trim()) ?? 0,
        'location': _editLocationController.text.trim(),
        'hospital': _editHospitalController.text.trim(),
        'phone': _editPhoneController.text.trim(),
        'bio': _editBioController.text.trim(),
        'availableDays': _editSelectedDays,
        'availableTimeSlots': _editSelectedTimeSlots,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _statusMessage = '✅ Doctor details updated successfully!');
      await _loadCredentials();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Doctor updated successfully!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() => _statusMessage = '❌ Update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error updating doctor: $e'), backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _editSectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.deepOrange),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade800)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: Colors.deepOrange.shade100)),
    ]);
  }

  Widget _editField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: required ? (v) => (v == null || v.isEmpty) ? 'Required' : null : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  void _copyCredentials() {
    final text = _credentials.map((cred) => '''
${cred['name']}
Email: ${cred['email']}
Password: Doctor@${cred['originalId']}123
---''').join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('📋 Credentials copied to clipboard'), backgroundColor: Colors.green,
    ));
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.signOut();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Control Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.feedback_outlined),
                tooltip: 'Feedback Management',
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (context) => const AdminFeedbackScreen()));
                  _loadFeedbackStats();
                },
              ),
              if (_pendingFeedbackCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Center(
                      child: Text(
                        _pendingFeedbackCount > 9 ? '9+' : _pendingFeedbackCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh Data', onPressed: _loadAllData),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _handleLogout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDoctorDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Doctor'),
        backgroundColor: Colors.deepOrange,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // bottom padding so FAB never covers content
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroSection(),
              const SizedBox(height: 20),
              _buildQuickStatsGrid(),
              const SizedBox(height: 20),
              _buildActionCardsGrid(),
              const SizedBox(height: 24),
              _buildDoctorManagementSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.deepOrange.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.admin_panel_settings, size: 40, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome Back, Admin',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Manage your healthcare platform',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.95))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildQuickStatCard('Total Patients',
            _isLoadingQuickStats ? '...' : _totalPatients.toString(), Icons.people, Colors.blue),
        _buildQuickStatCard('Total Doctors',
            _isLoadingStats ? '...' : _stats['registered'].toString(), Icons.medical_services, Colors.green),
        _buildQuickStatCard('Appointments',
            _isLoadingQuickStats ? '...' : _totalAppointments.toString(), Icons.calendar_today, Colors.purple),
        _buildQuickStatCard('Pending Feedback',
            _isLoadingFeedback ? '...' : _pendingFeedbackCount.toString(),
            Icons.pending_actions, Colors.orange, badge: _pendingFeedbackCount > 0),
      ],
    );
  }

  Widget _buildQuickStatCard(String label, String value, IconData icon, Color color, {bool badge = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (badge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                  child: const Text('New',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color, height: 1.0)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildActionCardsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            'Analytics Dashboard', 'View detailed statistics',
            Icons.analytics, Colors.blue,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const AdminAnalyticsScreen())),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            'Feedback Review', 'Manage patient feedback',
            Icons.feedback, Colors.purple,
            () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminFeedbackScreen()));
              _loadFeedbackStats();
            },
            badge: _pendingFeedbackCount > 0 ? _pendingFeedbackCount : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap, {int? badge}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: Text(badge > 9 ? '9+' : badge.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [Icon(Icons.arrow_forward, size: 16, color: color)]),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Doctor Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_credentials.isNotEmpty)
              IconButton(
                onPressed: _copyCredentials,
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy all credentials',
                style: IconButton.styleFrom(backgroundColor: Colors.deepOrange.shade50),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingStats)
          const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
        else ...[
          _buildDoctorStatsCard(),
          const SizedBox(height: 16),
          if (_credentials.isNotEmpty) ...[
            // ── Search bar ──────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() { _searchQuery = v; _expandedDoctorIds.clear(); }),
                decoration: InputDecoration(
                  hintText: 'Search by name, email or ID...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, color: Colors.deepOrange.shade400),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() { _searchController.clear(); _searchQuery = ''; _currentPage = 0; }),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFilterBar(),
            const SizedBox(height: 8),
            _buildCredentialsList(),
          ] else
            _buildEmptyState(),
        ],
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildStatusMessage(),
        ],
      ],
    );
  }

  Widget _buildDoctorStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('Registered', _stats['registered'].toString(), Colors.green),
          Container(width: 1, height: 40, color: Colors.grey.shade300),
          _buildStatColumn('Active', _stats['registered'].toString(), Colors.blue),
          Container(width: 1, height: 40, color: Colors.grey.shade300),
          _buildStatColumn('This Month', _stats['thisMonth'].toString(), Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, color: Colors.deepOrange, size: 18),
              const SizedBox(width: 8),
              const Text('Filter by Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_selectedFilterType != 'all')
                TextButton(
                  onPressed: () => _applyQuickFilter('all'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              _buildFilterChip('All', 'all'),
              _buildFilterChip('Today', 'today'),
              _buildFilterChip('Week', 'week'),
              _buildFilterChip('Month', 'month'),
              _buildFilterChip(
                _selectedFilterType == 'custom' && _filterStartDate != null
                    ? '${_formatDate(_filterStartDate)} - ${_formatDate(_filterEndDate)}'
                    : 'Custom',
                'custom',
                onTap: _showCustomDateRangePicker,
              ),
            ],
          ),
          if (_selectedFilterType != 'all') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50, borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.deepOrange.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Showing ${_filteredCredentials.length} of ${_credentials.length} doctors',
                    style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterType, {VoidCallback? onTap}) {
    final isSelected = _selectedFilterType == filterType;
    return InkWell(
      onTap: onTap ?? () => _applyQuickFilter(filterType),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepOrange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            )),
      ),
    );
  }

  Widget _buildCredentialsList() {
    final allDoctors = _filteredCredentials;
    final totalPages = (allDoctors.length / _pageSize).ceil().clamp(1, 999);
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final start = safePage * _pageSize;
    final end = (start + _pageSize).clamp(0, allDoctors.length);
    final doctors = allDoctors.isEmpty ? <Map<String, dynamic>>[] : allDoctors.sublist(start, end);

    if (allDoctors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No doctors match your search',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ]),
        ),
      );
    }

    return Column(
      children: [
        // ── Doctor cards ───────────────────────────────────────
        ...List.generate(doctors.length, (index) {
          final cred = doctors[index];
          final id = cred['originalId']?.toString() ?? index.toString();
          final isExpanded = _expandedDoctorIds.contains(id);
          final name = cred['name'].toString();
          final initial = name.length > 4 ? name.substring(4, 5).toUpperCase() : name[0].toUpperCase();

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isExpanded ? Colors.deepOrange.shade200 : Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  // Main row — tap to expand
                  InkWell(
                    onTap: () => setState(() {
                      if (isExpanded) _expandedDoctorIds.remove(id);
                      else _expandedDoctorIds.add(id);
                    }),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.deepOrange.shade100,
                            child: Text(initial,
                                style: TextStyle(color: Colors.deepOrange.shade700,
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.badge_outlined, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(id, style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade600, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 10),
                                  Icon(Icons.email_outlined, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(cred['email'],
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      overflow: TextOverflow.ellipsis)),
                                ]),
                              ],
                            ),
                          ),
                          Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.deepOrange.shade200),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.edit_outlined, color: Colors.deepOrange.shade700, size: 18),
                              tooltip: 'Edit doctor',
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(8),
                              onPressed: () => _showEditDoctorDialog(cred),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Expanded details
                  if (isExpanded) ...[
                    Divider(height: 1, color: Colors.deepOrange.shade50),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        children: [
                          _buildDetailRow(Icons.lock_outline, 'Password', 'Doctor@${id}123', isMonospace: true),
                          const SizedBox(height: 8),
                          _buildDetailRow(Icons.calendar_today_outlined, 'Registered', _formatDate(cred['registeredAt'])),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text: '${name}\nEmail: ${cred['email']}\nPassword: Doctor@${id}123'));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Credentials copied'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 1),
                                ));
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Copy Credentials', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.deepOrange,
                                side: BorderSide(color: Colors.deepOrange.shade200),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        // ── Pagination controls ─────────────────────────────────
        if (totalPages > 1) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: safePage > 0
                      ? () => setState(() { _currentPage = safePage - 1; _expandedDoctorIds.clear(); })
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Prev', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    disabledForegroundColor: Colors.grey.shade300,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (i) => GestureDetector(
                    onTap: () => setState(() { _currentPage = i; _expandedDoctorIds.clear(); }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == safePage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == safePage ? Colors.deepOrange : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )),
                ),
                TextButton.icon(
                  onPressed: safePage < totalPages - 1
                      ? () => setState(() { _currentPage = safePage + 1; _expandedDoctorIds.clear(); })
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Next', style: TextStyle(fontSize: 12)),
                  iconAlignment: IconAlignment.end,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    disabledForegroundColor: Colors.grey.shade300,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Page ${safePage + 1} of $totalPages  •  ${allDoctors.length} doctors total',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              '${allDoctors.length} doctor${allDoctors.length == 1 ? "" : "s"}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }


  Widget _buildDetailRow(IconData icon, String label, String value, {bool isMonospace = false}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.deepOrange.shade400),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontWeight: isMonospace ? FontWeight.w600 : FontWeight.normal),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }


  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No doctors registered yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Tap the "Add Doctor" button to get started',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage() {
    final isSuccess = _statusMessage.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSuccess ? Colors.green.shade300 : Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle : Icons.info,
              color: isSuccess ? Colors.green.shade700 : Colors.orange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_statusMessage,
                style: TextStyle(
                    color: isSuccess ? Colors.green.shade900 : Colors.orange.shade900, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
