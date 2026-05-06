import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'register_doctors.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  bool _isRegistering = false;
  bool _isLoadingStats = true;
  String _statusMessage = '';
  List<Map<String, dynamic>> _credentials = [];
  Map<String, int> _stats = {'total': 0, 'registered': 0, 'pending': 0};

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadCredentials();
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

  Future<void> _registerAllDoctors() async {
    final previousRegistered = _stats['registered'] ?? 0;
    
    setState(() {
      _isRegistering = true;
      _statusMessage = 'Checking and registering doctors...';
    });

    try {
      await DoctorRegistration.registerAllDoctors();
      await _loadStats();
      final creds = await DoctorRegistration.getDoctorCredentials();
      
      final newCount = (_stats['registered'] ?? 0) - previousRegistered;
      
      setState(() {
        _credentials = creds;
        if (newCount > 0) {
          _statusMessage = '✅ Successfully registered $newCount new doctor(s)!';
        } else {
          _statusMessage = '💡 All doctors are already registered!';
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: newCount > 0 ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isRegistering = false);
    }
  }

  void _copyCredentials() {
    final text = _credentials.map((cred) {
      return '''
${cred['name']}
Email: ${cred['email']}
Password: Doctor@${cred['originalId']}123
---''';
    }).join('\n\n');
    
    Clipboard.setData(ClipboardData(text: text));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Credentials copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel - Doctor Registration'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings, 
                          size: 32, color: Colors.deepPurple),
                      const SizedBox(width: 12),
                      const Text(
                        'Doctor Registration System',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This will register only NEW doctors from the doctors_database.json file.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Statistics Card
            if (_isLoadingStats)
              const Center(child: CircularProgressIndicator())
            else
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registration Statistics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            'Total',
                            _stats['total'].toString(),
                            Colors.blue,
                            Icons.groups,
                          ),
                          _buildStatItem(
                            'Registered',
                            _stats['registered'].toString(),
                            Colors.green,
                            Icons.check_circle,
                          ),
                          _buildStatItem(
                            'Pending',
                            _stats['pending'].toString(),
                            Colors.orange,
                            Icons.pending,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Register Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isRegistering ? null : _registerAllDoctors,
                icon: _isRegistering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.person_add, size: 24),
                label: Text(
                  _isRegistering ? 'Checking & Registering...' : 'Register New Doctors',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Status Message
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusMessage.startsWith('✅')
                      ? Colors.green.shade50
                      : _statusMessage.startsWith('💡')
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.startsWith('✅')
                        ? Colors.green.shade300
                        : _statusMessage.startsWith('💡')
                            ? Colors.blue.shade300
                            : Colors.orange.shade300,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.startsWith('✅')
                        ? Colors.green.shade900
                        : _statusMessage.startsWith('💡')
                            ? Colors.blue.shade900
                            : Colors.orange.shade900,
                  ),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Credentials List
            if (_credentials.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Registered Doctor Credentials',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: _copyCredentials,
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy all credentials',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _credentials.length,
                itemBuilder: (context, index) {
                  final cred = _credentials[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepPurple,
                        child: Text(
                          cred['name'].toString().substring(4, 5),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        cred['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email: ${cred['email']}'),
                          Text('Password: Doctor@${cred['originalId']}123'),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}