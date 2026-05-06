import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';
import '../widgets/health_summary_download_dialog.dart'; 
import 'package:image_cropper/image_cropper.dart';

class ProfileForm extends StatefulWidget {
  final Map<String, dynamic>? existingData;

  const ProfileForm({super.key, this.existingData});

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  // Personal Information
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  // Physical Measurements
  late TextEditingController _weightController;
  late TextEditingController _heightController;

  // Medical Information
  late TextEditingController _bloodGroupController;
  late TextEditingController _allergiesController;
  late TextEditingController _chronicConditionsController;
  late TextEditingController _medicationsController;

  // Emergency Contact
  late TextEditingController _emergencyContactNameController;
  late TextEditingController _emergencyContactPhoneController;

  String _selectedGender = "Male";
  DateTime? _dateOfBirth;
  int _calculatedAge = 0;
  double _bmi = 0.0;
  String _bmiCategory = '';
  bool _isLoading = false;
  String? _profilePhotoBase64;
  bool _uploadingPhoto = false;

  /// Validates Sri Lankan phone numbers
  /// Accepts: 0XXXXXXXXX (10 digits) or +94XXXXXXXXX (+94 + 9 digits)
  String? _validateSriLankanPhone(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Please enter a phone number' : null;
    }

    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final localFormat = RegExp(r'^0[0-9]{9}$');       // e.g. 0712345678
    final intlFormat = RegExp(r'^\+94[0-9]{9}$');      // e.g. +94712345678

    if (!localFormat.hasMatch(cleaned) && !intlFormat.hasMatch(cleaned)) {
      return 'Invalid phone number (e.g. 0712345678 or +94712345678)';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.existingData?["name"] ?? "");
    _emailController = TextEditingController(
        text: widget.existingData?["email"] ?? FirebaseAuth.instance.currentUser?.email ?? "");
    _phoneController = TextEditingController(text: widget.existingData?["phone"] ?? "");

    _weightController = TextEditingController(text: widget.existingData?["weight"]?.toString() ?? "");
    _heightController = TextEditingController(text: widget.existingData?["height"]?.toString() ?? "");

    _bloodGroupController = TextEditingController(text: widget.existingData?["bloodGroup"] ?? "");
    _allergiesController = TextEditingController(text: widget.existingData?["allergies"] ?? "");
    _chronicConditionsController = TextEditingController(text: widget.existingData?["chronicConditions"] ?? "");
    _medicationsController = TextEditingController(text: widget.existingData?["currentMedications"] ?? "");

    _emergencyContactNameController = TextEditingController(text: widget.existingData?["emergencyContactName"] ?? "");
    _emergencyContactPhoneController = TextEditingController(text: widget.existingData?["emergencyContactPhone"] ?? "");

    _selectedGender = widget.existingData?["gender"] ?? "Male";

    _profilePhotoBase64 = widget.existingData?["profilePhotoBase64"];

    if (widget.existingData?["dateOfBirth"] != null) {
      try {
        if (widget.existingData!["dateOfBirth"] is Timestamp) {
          _dateOfBirth = (widget.existingData!["dateOfBirth"] as Timestamp).toDate();
        } else if (widget.existingData!["dateOfBirth"] is String) {
          _dateOfBirth = DateTime.parse(widget.existingData!["dateOfBirth"]);
        }
        _calculateAge();
      } catch (e) {
        print('Error parsing date of birth: $e');
      }
    }

    _calculateBMI();
    _weightController.addListener(_calculateBMI);
    _heightController.addListener(_calculateBMI);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _bloodGroupController.dispose();
    _allergiesController.dispose();
    _chronicConditionsController.dispose();
    _medicationsController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    super.dispose();
  }

  void _calculateAge() {
    if (_dateOfBirth != null) {
      final today = DateTime.now();
      int age = today.year - _dateOfBirth!.year;
      if (today.month < _dateOfBirth!.month ||
          (today.month == _dateOfBirth!.month && today.day < _dateOfBirth!.day)) {
        age--;
      }
      setState(() {
        _calculatedAge = age;
      });
    }
  }

  void _calculateBMI() {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);

    if (weight != null && height != null && height > 0) {
      final heightInMeters = height / 100;
      final bmi = weight / (heightInMeters * heightInMeters);

      setState(() {
        _bmi = bmi;
        if (bmi < 18.5) {
          _bmiCategory = 'Underweight';
        } else if (bmi < 25) {
          _bmiCategory = 'Normal';
        } else if (bmi < 30) {
          _bmiCategory = 'Overweight';
        } else {
          _bmiCategory = 'Obese';
        }
      });
    } else {
      setState(() {
        _bmi = 0;
        _bmiCategory = '';
      });
    }
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.deepPurple,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _dateOfBirth) {
      setState(() {
        _dateOfBirth = picked;
        _calculateAge();
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 60,
      );

      if (pickedFile == null) {
        print('❌ No image selected');
        return;
      }

      setState(() => _uploadingPhoto = true);

      try {
        final bytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(bytes);

        print('📷 Image size: ${bytes.length} bytes');
        print('📷 Base64 length: ${base64Image.length} characters');

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('profiles')
              .doc(user.uid)
              .set({
                'profilePhotoBase64': base64Image,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

          setState(() {
            _profilePhotoBase64 = base64Image;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profile photo updated!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print('❌ Error saving photo: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error picking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final uid = user.uid;

          final profileData = {
            "name": _nameController.text.trim(),
            "email": _emailController.text.trim(),
            "phone": _phoneController.text.trim(),
            "gender": _selectedGender,
            "dateOfBirth": _dateOfBirth != null ? Timestamp.fromDate(_dateOfBirth!) : null,
            "age": _calculatedAge,
            "weight": double.tryParse(_weightController.text.trim()) ?? 0,
            "height": double.tryParse(_heightController.text.trim()) ?? 0,
            "bmi": _bmi,
            "bmiCategory": _bmiCategory,
            "bloodGroup": _bloodGroupController.text.trim(),
            "allergies": _allergiesController.text.trim(),
            "chronicConditions": _chronicConditionsController.text.trim(),
            "currentMedications": _medicationsController.text.trim(),
            "emergencyContactName": _emergencyContactNameController.text.trim(),
            "emergencyContactPhone": _emergencyContactPhoneController.text.trim(),
            "profilePhotoBase64": _profilePhotoBase64,
            "updatedAt": FieldValue.serverTimestamp(),
          };

          await FirebaseFirestore.instance
              .collection("profiles")
              .doc(uid)
              .set(profileData, SetOptions(merge: true));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text("Profile saved successfully!"),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );

            Navigator.pop(context, true);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error saving profile: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.deepPurple),
      filled: true,
      fillColor: Colors.white.withOpacity(0.95),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.deepPurple, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
          child: Column(
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.purple.shade300],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            backgroundImage: _profilePhotoBase64 != null && _profilePhotoBase64!.isNotEmpty
                                ? MemoryImage(base64Decode(_profilePhotoBase64!))
                                : null,
                            child: _uploadingPhoto
                                ? const CircularProgressIndicator(
                                    color: Colors.deepPurple,
                                    strokeWidth: 3,
                                  )
                                : (_profilePhotoBase64 == null || _profilePhotoBase64!.isEmpty)
                                    ? const Icon(Icons.person, size: 60, color: Colors.deepPurple)
                                    : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _uploadingPhoto ? Colors.grey : Colors.deepPurple,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Profile & Health Information",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _nameController.text.isNotEmpty ? _nameController.text : "Complete your profile",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildHealthSummaryButton(),

              const SizedBox(height: 20),

              // Form Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ========== PERSONAL INFORMATION ==========
                      _buildSectionHeader("Personal Information", Icons.person_outline),

                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration(
                          label: "Full Name",
                          icon: Icons.person,
                          hint: "Enter your full name",
                        ),
                        validator: (value) => value!.isEmpty ? "Please enter your name" : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration(
                          label: "Email",
                          icon: Icons.email,
                          hint: "your.email@example.com",
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value!.isEmpty) return "Please enter your email";
                          if (!value.contains('@')) return "Enter a valid email";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ✅ Phone with Sri Lankan validation
                      TextFormField(
                        controller: _phoneController,
                        decoration: _inputDecoration(
                          label: "Phone Number",
                          icon: Icons.phone,
                          hint: "+94 71 234 5678",
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) => _validateSriLankanPhone(value),
                      ),
                      const SizedBox(height: 16),

                      // Gender Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedGender,
                        items: ["Male", "Female", "Other"]
                            .map((gender) => DropdownMenuItem(
                                  value: gender,
                                  child: Text(gender),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedGender = value!;
                          });
                        },
                        decoration: _inputDecoration(
                          label: "Gender",
                          icon: Icons.wc,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Date of Birth Picker
                      InkWell(
                        onTap: _selectDateOfBirth,
                        child: InputDecorator(
                          decoration: _inputDecoration(
                            label: "Date of Birth",
                            icon: Icons.cake,
                            hint: "Select your date of birth",
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _dateOfBirth != null
                                    ? DateFormat('dd MMM yyyy').format(_dateOfBirth!)
                                    : "Select date",
                                style: TextStyle(
                                  color: _dateOfBirth != null ? Colors.black87 : Colors.grey,
                                ),
                              ),
                              if (_calculatedAge > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "$_calculatedAge years",
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // ========== PHYSICAL MEASUREMENTS ==========
                      _buildSectionHeader("Physical Measurements", Icons.fitness_center),

                      TextFormField(
                        controller: _weightController,
                        decoration: _inputDecoration(
                          label: "Weight (kg)",
                          icon: Icons.monitor_weight,
                          hint: "e.g., 70",
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value!.isNotEmpty) {
                            final weight = double.tryParse(value);
                            if (weight == null || weight <= 0) {
                              return "Enter a valid weight";
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _heightController,
                        decoration: _inputDecoration(
                          label: "Height (cm)",
                          icon: Icons.height,
                          hint: "e.g., 170",
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value!.isNotEmpty) {
                            final height = double.tryParse(value);
                            if (height == null || height <= 0) {
                              return "Enter a valid height";
                            }
                          }
                          return null;
                        },
                      ),

                      // BMI Display
                      if (_bmi > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade50,
                                Colors.purple.shade50,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Your BMI:",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _bmi.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Category:"),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getBMIColor(),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _bmiCategory,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ========== MEDICAL INFORMATION ==========
                      _buildSectionHeader("Medical Information", Icons.medical_services),

                      TextFormField(
                        controller: _bloodGroupController,
                        decoration: _inputDecoration(
                          label: "Blood Group",
                          icon: Icons.bloodtype,
                          hint: "e.g., O+, A-, AB+",
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _allergiesController,
                        decoration: _inputDecoration(
                          label: "Allergies",
                          icon: Icons.warning_amber,
                          hint: "e.g., Peanuts, Penicillin",
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _chronicConditionsController,
                        decoration: _inputDecoration(
                          label: "Chronic Conditions",
                          icon: Icons.healing,
                          hint: "e.g., Diabetes, Asthma",
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _medicationsController,
                        decoration: _inputDecoration(
                          label: "Current Medications",
                          icon: Icons.medication,
                          hint: "e.g., Metformin 500mg daily",
                        ),
                        maxLines: 3,
                      ),

                      // ========== EMERGENCY CONTACT ==========
                      _buildSectionHeader("Emergency Contact", Icons.emergency),

                      TextFormField(
                        controller: _emergencyContactNameController,
                        decoration: _inputDecoration(
                          label: "Emergency Contact Name",
                          icon: Icons.contact_emergency,
                          hint: "Name of emergency contact",
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ✅ Emergency contact phone with Sri Lankan validation
                      TextFormField(
                        controller: _emergencyContactPhoneController,
                        decoration: _inputDecoration(
                          label: "Emergency Contact Phone",
                          icon: Icons.phone_in_talk,
                          hint: "+94 71 234 5678",
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) => _validateSriLankanPhone(value),
                      ),

                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 5,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "Save Profile",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getBMIColor() {
    if (_bmi < 18.5) {
      return Colors.blue;
    } else if (_bmi < 25) {
      return Colors.green;
    } else if (_bmi < 30) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  Widget _buildHealthSummaryButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.teal.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showHealthSummaryDialog,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade400, Colors.purple.shade300],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.file_download,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Download Health Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get your comprehensive health report',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHealthSummaryDialog() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Please save your profile first before downloading health summary'),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    await showHealthSummaryDownloadDialog(
      context: context,
      userId: user.uid,
      userName: _nameController.text.trim(),
    );
  }
}