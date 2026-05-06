import 'package:flutter/material.dart';

/// Shows detailed information about a doctor in a beautiful dialog
/// Returns the selected doctor if user clicks "Select Doctor", null otherwise
Future<Map<String, dynamic>?> showDoctorDetailsDialog(
  BuildContext context, 
  Map<String, dynamic> doctor,
) async {
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _DoctorDetailsDialog(doctor: doctor),
  );
}

class _DoctorDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> doctor;

  const _DoctorDetailsDialog({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final languages = (doctor['languages'] as List?)?.cast<String>() ?? [];
    final expertise = (doctor['expertise'] as List?)?.cast<String>() ?? [];
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Doctor Avatar
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Text(
                      doctor['fullName'].toString().split(' ').length > 1
                          ? doctor['fullName'].toString().split(' ')[1][0].toUpperCase()
                          : doctor['fullName'].toString()[0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.teal.shade700,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Doctor Name
                  Text(
                    doctor['name'] ?? doctor['fullName'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Specialization
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      doctor['specialization'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Rating and Experience Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Rating
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${doctor['rating'] ?? 'N/A'}',
                              style: TextStyle(
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Experience
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.work_outline, 
                                color: Colors.teal.shade700, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${doctor['experienceYears'] ?? 0}+ years',
                              style: TextStyle(
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bio
                    if (doctor['bio'] != null && doctor['bio'].toString().isNotEmpty) ...[
                      _buildSectionTitle('About', Icons.person_outline),
                      const SizedBox(height: 8),
                      Text(
                        doctor['bio'],
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // Hospital & Location
                    _buildSectionTitle('Practice', Icons.local_hospital),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.business,
                      doctor['hospital'] ?? 'Not specified',
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      Icons.location_on,
                      doctor['location'] ?? 'Not specified',
                      Colors.red,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Languages
                    if (languages.isNotEmpty) ...[
                      _buildSectionTitle('Languages Spoken', Icons.language),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: languages.map((lang) => Chip(
                          avatar: const Icon(Icons.translate, size: 16),
                          label: Text(lang),
                          backgroundColor: Colors.purple.shade50,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.purple.shade700,
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // Expertise Areas
                    if (expertise.isNotEmpty) ...[
                      _buildSectionTitle('Areas of Expertise', Icons.medical_services),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: expertise.map((area) => Chip(
                          avatar: Icon(Icons.check_circle, 
                              size: 16, color: Colors.green.shade700),
                          label: Text(area),
                          backgroundColor: Colors.green.shade50,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // ✅ REMOVED: Consultation Fee section (already shown in header as chips would be redundant)
                  ],
                ),
              ),
            ),
            
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context, doctor); // Return selected doctor
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Select Doctor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}

