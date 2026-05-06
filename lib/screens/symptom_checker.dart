import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({super.key});

  @override
  State<SymptomCheckerScreen> createState() =>
      _SymptomCheckerScreenState();
}

class SymptomInput {
  int? symptomId;
  String? symptomName;
  String? category;
  String? icd10Code;
  String severity;
  DateTime onsetDate;
  String? duration;
  String? additionalNotes;
  Map<String, dynamic>? fullSymptomData;

  SymptomInput({
    this.symptomId,
    this.symptomName,
    this.category,
    this.icd10Code,
    this.severity = 'mild',
    DateTime? onsetDate,
    this.duration,
    this.additionalNotes,
    this.fullSymptomData,
  }) : onsetDate = onsetDate ?? DateTime.now();
}

class _SymptomCheckerScreenState
    extends State<SymptomCheckerScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final CollectionReference _symptomsCollection =
      FirebaseFirestore.instance.collection('symptoms');

  List<Map<String, dynamic>> _symptomDatabase = [];
  bool _isDatabaseLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSymptomDatabase();
  }

  Future<void> _loadSymptomDatabase() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/data/symptoms_database.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> data = jsonData['symptoms'];

      setState(() {
        _symptomDatabase = data.cast<Map<String, dynamic>>();
        _isDatabaseLoaded = true;
      });

      print('✅ Loaded ${_symptomDatabase.length} symptoms from database');
    } catch (e) {
      print('❌ Error loading symptom database: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load symptom database: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _searchSymptoms(String query) {
    if (query.isEmpty) return [];

    return _symptomDatabase.where((symptom) {
      final name = symptom['symptom_name']?.toString().toLowerCase() ?? '';
      final category = symptom['category']?.toString().toLowerCase() ?? '';
      final description = symptom['description']?.toString().toLowerCase() ?? '';

      return name.contains(query.toLowerCase()) ||
          category.contains(query.toLowerCase()) ||
          description.contains(query.toLowerCase());
    }).toList();
  }

  Map<String, dynamic>? _getSymptomById(int id) {
    try {
      return _symptomDatabase.firstWhere((s) => s['id'] == id);
    } catch (_) {
      return null;
    }
  }

  void _showAddSymptomDialog() {
    if (!_isDatabaseLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading symptom database...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    List<SymptomInput> tempSymptoms = [SymptomInput()];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.health_and_safety,
                  color: Colors.teal.shade700, size: 28),
              const SizedBox(width: 8),
              const Text("Add Symptoms",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Professional symptom database with treatment protocols',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  ...tempSymptoms.asMap().entries.map((entry) {
                    final index = entry.key;
                    final symptom = entry.value;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tempSymptoms.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Symptom ${index + 1}',
                                  style: TextStyle(
                                    color: Colors.teal.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),

                            Autocomplete<Map<String, dynamic>>(
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<Map<String, dynamic>>.empty();
                                }
                                return _searchSymptoms(textEditingValue.text)
                                    .take(10);
                              },
                              displayStringForOption: (Map<String, dynamic> option) =>
                                  option['symptom_name'] ?? '',
                              onSelected: (Map<String, dynamic> selection) {
                                setStateDialog(() {
                                  symptom.symptomId = selection['id'];
                                  symptom.symptomName = selection['symptom_name'];
                                  symptom.category = selection['category'];
                                  symptom.icd10Code = selection['icd10_code'];
                                  symptom.fullSymptomData = selection;
                                });
                              },
                              fieldViewBuilder: (context, controller,
                                  focusNode, onFieldSubmitted) {
                                if (symptom.symptomName != null &&
                                    controller.text.isEmpty) {
                                  controller.text = symptom.symptomName!;
                                }
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: "Search Symptom",
                                    hintText:
                                        "Type to search (e.g., fever, headache)...",
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: controller.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              controller.clear();
                                              setStateDialog(() {
                                                symptom.symptomId = null;
                                                symptom.symptomName = null;
                                                symptom.category = null;
                                                symptom.icd10Code = null;
                                                symptom.fullSymptomData = null;
                                              });
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                );
                              },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 300,
                                      ),
                                      width: MediaQuery.of(context).size.width *
                                          0.75,
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        itemCount: options.length,
                                        shrinkWrap: true,
                                        itemBuilder: (context, index) {
                                          final option =
                                              options.elementAt(index);
                                          return ListTile(
                                            leading: Icon(
                                              _getCategoryIcon(option['category']),
                                              color: Colors.teal.shade700,
                                              size: 20,
                                            ),
                                            title: Text(
                                              option['symptom_name'] ?? '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  option['category'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                Text(
                                                  'ICD-10: ${option['icd10_code'] ?? ''}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade500,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            onTap: () => onSelected(option),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 16),

                            if (symptom.category != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.blue.shade200, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_getCategoryIcon(symptom.category),
                                        size: 16, color: Colors.blue.shade700),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Category: ${symptom.category}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            if (symptom.icd10Code != null) ...[
                              _buildCodeChip('ICD-10', symptom.icd10Code!, Colors.purple),
                              const SizedBox(height: 16),
                            ],

                            const Text(
                              'Severity Level',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                           SegmentedButton<String>(
  showSelectedIcon: false, // Prevents the checkmark from pushing text
  style: SegmentedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    // Add a little vertical padding to accommodate the two-line layout
    padding: const EdgeInsets.symmetric(vertical: 12),
    // Background and foreground colors based on your lavender theme
    selectedBackgroundColor: const Color(0xFFE8E0FF),
    selectedForegroundColor: const Color(0xFF6750A4),
    // Corrected text style parameter
    textStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  ),
  segments: [
    ButtonSegment(
      value: 'mild',
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sentiment_satisfied, size: 22),
          SizedBox(height: 4),
          Text('Mild'),
        ],
      ),
    ),
    ButtonSegment(
      value: 'moderate',
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sentiment_neutral, size: 22),
          SizedBox(height: 4),
          Text('Moderate'),
        ],
      ),
    ),
    ButtonSegment(
      value: 'severe',
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sentiment_very_dissatisfied, size: 22),
          SizedBox(height: 4),
          Text('Severe'),
        ],
      ),
    ),
  ],
  selected: {symptom.severity},
  onSelectionChanged: (Set<String> newSelection) {
    setStateDialog(() {
      symptom.severity = newSelection.first;
    });
  },
),
const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: symptom.duration,
                              decoration: InputDecoration(
                                labelText: "Duration",
                                prefixIcon: const Icon(Icons.schedule),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              items: const [
                                'Less than 1 hour',
                                '1-6 hours',
                                '6-24 hours',
                                '1-3 days',
                                '3-7 days',
                                '1-2 weeks',
                                '2-4 weeks',
                                'More than 1 month',
                              ]
                                  .map((d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d,
                                            style: TextStyle(fontSize: 13)),
                                      ))
                                  .toList(),
                              onChanged: (val) =>
                                  setStateDialog(() => symptom.duration = val),
                            ),

                            const SizedBox(height: 16),

                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: symptom.onsetDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setStateDialog(
                                      () => symptom.onsetDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade50,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 20),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Onset Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          DateFormat('dd MMM yyyy')
                                              .format(symptom.onsetDate),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextField(
                              decoration: InputDecoration(
                                labelText: "Additional Notes (Optional)",
                                hintText: "Any other details...",
                                prefixIcon: const Icon(Icons.note_alt_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              maxLines: 2,
                              onChanged: (val) => symptom.additionalNotes = val,
                            ),

                            const SizedBox(height: 12),

                            if (tempSymptoms.length > 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  label: const Text('Remove',
                                      style: TextStyle(color: Colors.red)),
                                  onPressed: () => setStateDialog(
                                      () => tempSymptoms.removeAt(index)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setStateDialog(() => tempSymptoms.add(SymptomInput())),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text("Add Another Symptom"),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.teal.shade400, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (tempSymptoms
                    .every((symptom) => symptom.symptomName == null)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one symptom'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (user != null) {
                  for (var symptom in tempSymptoms) {
                    if (symptom.symptomName != null) {
                      await _symptomsCollection.add({
                        "userId": user!.uid,
                        "symptomId": symptom.symptomId,
                        "symptomName": symptom.symptomName!.trim(),
                        "category": symptom.category,
                        "icd10Code": symptom.icd10Code,
                        "severity": symptom.severity,
                        "duration": symptom.duration,
                        "onsetDate": symptom.onsetDate,
                        "additionalNotes": symptom.additionalNotes,
                        "createdAt": FieldValue.serverTimestamp(),
                      });
                    }
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            "${tempSymptoms.where((s) => s.symptomName != null).length} symptom(s) added successfully!"),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  Navigator.pop(ctx);
                }
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text("Submit All"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeChip(String label, String code, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            code,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'constitutional':
      case 'general':
        return Icons.thermostat;
      case 'respiratory':
        return Icons.air;
      case 'neurological':
        return Icons.psychology;
      case 'gastrointestinal':
      case 'digestive':
        return Icons.restaurant;
      case 'musculoskeletal':
        return Icons.fitness_center;
      case 'cardiovascular':
      case 'cardiac':
        return Icons.favorite;
      case 'dermatological':
      case 'skin':
        return Icons.healing;
      case 'urinary':
      case 'renal':
        return Icons.water_drop;
      case 'mental health':
      case 'psychiatric':
        return Icons.sentiment_satisfied;
      case 'ear nose throat':
      case 'ent':
        return Icons.hearing;
      case 'endocrine':
        return Icons.science;
      case 'eye':
      case 'ophthalmic':
        return Icons.visibility;
      default:
        return Icons.medical_services;
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case "mild":
        return Colors.green.shade50;
      case "moderate":
        return Colors.orange.shade50;
      case "severe":
        return Colors.red.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  Color _severityBorderColor(String severity) {
    switch (severity.toLowerCase()) {
      case "mild":
        return Colors.green.shade300;
      case "moderate":
        return Colors.orange.shade300;
      case "severe":
        return Colors.red.shade300;
      default:
        return Colors.grey.shade300;
    }
  }

  Color _severityChipColor(String severity) {
    switch (severity.toLowerCase()) {
      case "mild":
        return Colors.green.shade700;
      case "moderate":
        return Colors.orange.shade700;
      case "severe":
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildSymptomCard(Map<String, dynamic> data) {
    final int? symptomId = data['symptomId'];
    final String symptomName = data['symptomName'] ?? '';
    final String severity = data['severity'] ?? 'mild';
    final String? category = data['category'];
    final String? icd10Code = data['icd10Code'];
    final String? duration = data['duration'];
    final String? additionalNotes = data['additionalNotes'];

    DateTime onsetDate;
    try {
      onsetDate = (data['onsetDate'] as Timestamp).toDate();
    } catch (_) {
      onsetDate = DateTime.now();
    }

    Map<String, dynamic>? symptomDetails;
    if (symptomId != null) {
      symptomDetails = _getSymptomById(symptomId);
    }

    // Check if there are red flags
    bool hasRedFlags = symptomDetails?['red_flags'] != null &&
        (symptomDetails!['red_flags'] as List).isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _severityBorderColor(severity),
          width: 2,
        ),
      ),
      elevation: 3,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _severityColor(severity),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // Main Title Section (Always Visible)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (category != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            _getCategoryIcon(category),
                            size: 24,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              symptomName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: severity.toLowerCase() == "severe"
                                    ? Colors.red.shade900
                                    : severity.toLowerCase() == "moderate"
                                        ? Colors.orange.shade900
                                        : Colors.grey.shade900,
                              ),
                            ),
                            if (category != null)
                              Text(
                                category,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _severityChipColor(severity),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          severity.substring(0, 1).toUpperCase() +
                              severity.substring(1).toLowerCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        "Onset: ${DateFormat('dd MMM yyyy').format(onsetDate)}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (duration != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.schedule,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            duration,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (icd10Code != null) ...[
                    const SizedBox(height: 8),
                    _buildSmallCodeChip('ICD-10', icd10Code, Colors.purple),
                  ],
                ],
              ),
            ),

            // RED FLAGS - ALWAYS VISIBLE IF PRESENT
            if (hasRedFlags)
              _buildCompactRedFlags(symptomDetails!['red_flags'] as List),

            // Expandable Detailed Information
            if (symptomDetails != null)
              _buildExpandableDetails(symptomDetails, severity,
                  additionalNotes: additionalNotes)
            else if (additionalNotes != null && additionalNotes.isNotEmpty)
              ExpansionTile(
                title: const Text('Additional Notes',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        additionalNotes,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // IMPROVED: Compact Red Flags (Always Visible)
  Widget _buildCompactRedFlags(List redFlags) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SEEK IMMEDIATE MEDICAL ATTENTION IF:', // ✅ NO DUPLICATE ICON!
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...redFlags.take(3).map((flag) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.emergency,
                        size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        flag.toString(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          if (redFlags.length > 3) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${redFlags.length - 3} more red flags (tap below for full list)',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // IMPROVED: Expandable Details with Progressive Disclosure
  Widget _buildExpandableDetails(Map<String, dynamic> symptomDetails,
      String userSeverity,
      {String? additionalNotes}) {
    return ExpansionTile(
      title: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          const Text(
            'View Full Details & Treatment',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Description
              if (symptomDetails['description'] != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    symptomDetails['description'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Collapsible Sections
              _buildCollapsibleSection(
                'Complete Red Flags List',
                Icons.warning,
                Colors.red,
                _buildFullRedFlagsContent(symptomDetails['red_flags']),
              ),

              _buildCollapsibleSection(
                'Your Severity Level',
                Icons.analytics,
                Colors.orange,
                _buildSeverityInfo(
                    symptomDetails['severity_classification'], userSeverity),
              ),

              _buildCollapsibleSection(
                'When to Seek Medical Care',
                Icons.local_hospital,
                Colors.purple,
                _buildMedicalCareGuidance(
                    symptomDetails['when_to_seek_medical_care']),
              ),

              _buildCollapsibleSection(
                'Treatment Protocol',
                Icons.medical_services,
                Colors.green,
                _buildTreatmentProtocol(symptomDetails['treatment_protocol']),
              ),

              _buildCollapsibleSection(
                'Common Causes',
                Icons.info_outline,
                Colors.blue,
                _buildCommonCauses(symptomDetails['common_causes']),
              ),

              _buildCollapsibleSection(
                'Patient Education',
                Icons.school,
                Colors.indigo,
                _buildPatientEducation(symptomDetails['patient_education']),
              ),

              if (additionalNotes != null && additionalNotes.isNotEmpty) ...[
                _buildCollapsibleSection(
                  'Your Additional Notes',
                  Icons.note,
                  Colors.amber,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      additionalNotes,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              _buildMedicalDisclaimer(),
            ],
          ),
        ),
      ],
    );
  }

  // NEW: Collapsible Section Widget
  Widget _buildCollapsibleSection(
      String title, IconData icon, Color color, Widget content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildFullRedFlagsContent(List? redFlags) {
    if (redFlags == null || redFlags.isEmpty) {
      return const Text('No specific red flags identified.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: redFlags
          .map((flag) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.emergency,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        flag.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildSeverityInfo(
    dynamic severityClassification, String userSeverity) {
  if (severityClassification == null) {
    return const Text('Severity information not available.');
  }

  final severityData = severityClassification[userSeverity.toLowerCase()];

  // Handle if severityData is a string or a map
  String description = '';
  String characteristics = '';
  if (severityData is String) {
    description = severityData;
  } else if (severityData is Map<String, dynamic>) {
    description = severityData['description'] ?? '';
    characteristics = severityData['characteristics'] ?? '';
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (description.isNotEmpty)
        Text(
          description,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      if (characteristics.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          characteristics,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ],
  );
}


 Widget _buildMedicalCareGuidance(Map<String, dynamic>? careGuidance) {
  if (careGuidance == null) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (careGuidance['emergency_911'] != null &&
          (careGuidance['emergency_911'] as List).isNotEmpty) ...[
        _buildCareCategory(
          '🚨 EMERGENCY - Immediate Care',
          careGuidance['emergency_911'] as List,
          Colors.red,
        ),
        const SizedBox(height: 12),
      ],
      if (careGuidance['urgent_care_same_day'] != null &&
          (careGuidance['urgent_care_same_day'] as List).isNotEmpty) ...[
        _buildCareCategory(
          '⚡ Urgent - Same Day Care',
          careGuidance['urgent_care_same_day'] as List,
          Colors.orange,
        ),
        const SizedBox(height: 12),
      ],
      if (careGuidance['primary_care_1_week'] != null &&
          (careGuidance['primary_care_1_week'] as List).isNotEmpty) ...[
        _buildCareCategory(
          '📅 Schedule Within 1 Week',
          careGuidance['primary_care_1_week'] as List,
          Colors.blue,
        ),
      ],
    ],
  );
}


  Widget _buildCareCategory(String title, List items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.fiber_manual_record, size: 6, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildTreatmentProtocol(Map<String, dynamic>? treatmentProtocol) {
    if (treatmentProtocol == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (treatmentProtocol['home_remedies'] != null) ...[
          const Text(
            '🏠 Home Remedies:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...(treatmentProtocol['home_remedies'] as List).map((remedy) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle,
                        size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(remedy.toString(),
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],
        if (treatmentProtocol['otc_medications'] != null) ...[
          const Text(
            '💊 OTC Medications:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildMedicationSection(treatmentProtocol['otc_medications'] as List),
        ],
      ],
    );
  }

  Widget _buildMedicationSection(List medications) {
    return Column(
      children: medications.map((med) {
        if (med is Map) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  med['medication'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue.shade900,
                  ),
                ),
                if (med['dosage'] != null) ...[
                  const SizedBox(height: 4),
                  Text('Dosage: ${med['dosage']}',
                      style: const TextStyle(fontSize: 10)),
                ],
                if (med['contraindications'] != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 12, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Avoid if: ${med['contraindications']}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _buildCommonCauses(List? causes) {
    if (causes == null || causes.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: causes
          .map((cause) => Chip(
                label: Text(cause.toString()),
                backgroundColor: Colors.blue.shade50,
                labelStyle: const TextStyle(fontSize: 10),
                padding: const EdgeInsets.all(4),
              ))
          .toList(),
    );
  }

  Widget _buildPatientEducation(Map<String, dynamic>? education) {
    if (education == null || education['key_points'] == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: (education['key_points'] as List)
          .map((point) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb,
                        size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point.toString(),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMedicalDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.amber.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'This information is for educational purposes only. Always consult healthcare providers for medical decisions.',
              style: TextStyle(
                fontSize: 9,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallCodeChip(String label, String code, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            code,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text("Please log in to access symptom checker."),
        ),
      );
    }

    if (!_isDatabaseLoaded) {
      return Scaffold(
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
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Loading professional symptom database...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.verified, color: Colors.teal.shade700),
                      const SizedBox(width: 8),
                      const Text('Professional Database'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Master\'s Level Implementation',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.medical_services,
                          'Treatment protocols with dosages'),
                      _buildInfoRow(Icons.warning, 'Emergency red flags'),
                      _buildInfoRow(
                          Icons.local_hospital, 'Urgency-based care guidance'),
                      _buildInfoRow(Icons.school, 'Patient education'),
                      const SizedBox(height: 12),
                      Text(
                        'Evidence-based from WHO ICD-10 and CDC guidelines',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.purple.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(Icons.health_and_safety,
                        size: 50, color: Colors.teal.shade700),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Professional Symptom Checker",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Treatment Protocols • Red Flags • Clinical Guidance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _symptomsCollection
                        .where("userId", isEqualTo: user!.uid)
                        .orderBy("createdAt", descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 60, color: Colors.red.shade300),
                              const SizedBox(height: 16),
                              Text(
                                "Error loading symptoms",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.medical_information_outlined,
                                  size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                "No symptoms logged yet",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Add symptoms to see treatment protocols",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (ctx, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;
                          return _buildSymptomCard(data);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _showAddSymptomDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 28),
                  label: const Text(
                    "Add New Symptom",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 6,
                    shadowColor: Colors.teal.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}