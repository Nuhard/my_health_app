import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

class HealthLogScreen extends StatefulWidget {
  const HealthLogScreen({super.key});

  @override
  _HealthLogScreenState createState() => _HealthLogScreenState();
}

class _HealthLogScreenState extends State<HealthLogScreen> with SingleTickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _mealSearchController = TextEditingController();
  final TextEditingController _activityController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _waterIntakeController = TextEditingController();
  final TextEditingController _sleepHoursController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // State variables
  String _mood = "Happy";
  DateTime _selectedDate = DateTime.now();
  String? _editingLogId;
  List<Map<String, dynamic>> _selectedFoods = [];
  late TabController _tabController;
   String _mealType = "Breakfast"; // NEW
TimeOfDay _selectedTime = TimeOfDay.now(); // NEW
  // Datasets
  Map<String, dynamic> _nutritionDatabase = {};
  List<Map<String, dynamic>> _allFoods = [];
  List<Map<String, dynamic>> _allActivities = [];
Map<String, dynamic>? _selectedActivity;
String _activityIntensity = "moderate";
int _activityDuration = 30; // minutes
double _caloriesBurned = 0;

  // User profile data
  Map<String, dynamic>? _userProfile;
  
  // Nutrition totals for the day
  double _totalCalories = 0;
  double _totalProtein = 0;
  double _totalCarbs = 0;
  double _totalFat = 0;

  // Gamification
  int _xp = 0;
  int _level = 1;
  int get _nextLevelXp => _level * 100;

  // Daily goals (based on user profile)
  double _calorieGoal = 2000;
  double _proteinGoal = 50;
  double _carbsGoal = 250;
  double _fatGoal = 65;

  CollectionReference get _logsCollection =>
      FirebaseFirestore.instance.collection("health_logs");

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNutritionDatabase();
    _loadActivitiesDatabase();
    _loadUserProgress();
    _loadUserProfile();
    _calculateDailyNutrition();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// ============ LOAD COMPREHENSIVE NUTRITION DATABASE ============
  Future<void> _loadNutritionDatabase() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/nutrition_database.json');
      final data = json.decode(jsonString);
      setState(() {
        _nutritionDatabase = data;
        _allFoods = List<Map<String, dynamic>>.from(data['foods'] ?? []);
      });
      print('✅ Loaded ${_allFoods.length} foods from database');
    } catch (e) {
      print('❌ Error loading nutrition database: $e');
    }
  }
Future<void> _loadActivitiesDatabase() async {
  try {
    final jsonString = await rootBundle.loadString('assets/data/activities_database.json');
    final data = json.decode(jsonString);
    setState(() {
      _allActivities = List<Map<String, dynamic>>.from(data['activities'] ?? []);
    });
    print('✅ Loaded ${_allActivities.length} activities from database');
  } catch (e) {
    print('❌ Error loading activities database: $e');
  }
}

double _calculateCaloriesBurned(Map<String, dynamic> activity, String intensity, int durationMinutes, double userWeight) {
  // Get MET value for the intensity
  final met = (activity['met'][intensity] ?? 5.0).toDouble();
  
  // Formula: Calories/min = (MET × 3.5 × Weight in kg) / 200
  final caloriesPerMinute = (met * 3.5 * userWeight) / 200;
  
  return caloriesPerMinute * durationMinutes;
}

  /// ============ LOAD USER PROFILE FOR PERSONALIZED GOALS ============
  Future<void> _loadUserProfile() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("profiles")
          .doc(user!.uid)
          .get();
      
      if (doc.exists) {
        setState(() {
          _userProfile = doc.data();
          _calculatePersonalizedGoals();
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  /// ============ CALCULATE PERSONALIZED NUTRITION GOALS ============
  void _calculatePersonalizedGoals() {
    if (_userProfile == null) return;

    final age = _userProfile!['age'] ?? 25;
    final weight = _userProfile!['weight'] ?? 70;
    final height = _userProfile!['height'] ?? 170;
    final gender = _userProfile!['gender'] ?? 'Male';

    // Harris-Benedict equation for BMR
    double bmr;
    if (gender == 'Male') {
      bmr = 88.362 + (13.397 * weight) + (4.799 * height) - (5.677 * age);
    } else {
      bmr = 447.593 + (9.247 * weight) + (3.098 * height) - (4.330 * age);
    }

    // Activity multiplier (assuming moderate activity)
    final tdee = bmr * 1.55;

    setState(() {
      _calorieGoal = tdee.roundToDouble();
      _proteinGoal = (weight * 1.6).roundToDouble(); // 1.6g per kg
      _carbsGoal = (_calorieGoal * 0.50 / 4).roundToDouble(); // 50% of calories
      _fatGoal = (_calorieGoal * 0.25 / 9).roundToDouble(); // 25% of calories
    });
  }

  /// ============ CALCULATE TODAY'S NUTRITION TOTALS ============
  Future<void> _calculateDailyNutrition() async {
    if (user == null) return;

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final snapshot = await _logsCollection
          .where('userId', isEqualTo: user!.uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      double calories = 0;
      double protein = 0;
      double carbs = 0;
      double fat = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        calories += (data['totalCalories'] ?? 0).toDouble();
        protein += (data['totalProtein'] ?? 0).toDouble();
        carbs += (data['totalCarbs'] ?? 0).toDouble();
        fat += (data['totalFat'] ?? 0).toDouble();
      }

      setState(() {
        _totalCalories = calories;
        _totalProtein = protein;
        _totalCarbs = carbs;
        _totalFat = fat;
      });
    } catch (e) {
      print('Error calculating daily nutrition: $e');
    }
  }

  Future<void> _loadUserProgress() async {
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection("user_progress")
        .doc(user!.uid)
        .get();
    if (doc.exists) {
      setState(() {
        _xp = doc["xp"] ?? 0;
        _level = doc["level"] ?? 1;
      });
    }
  }

  Future<void> _updateUserProgress(int gainedXp) async {
    if (user == null) return;
    int newXp = _xp + gainedXp;
    int newLevel = _level;
    final oldLevel = _level;

    while (newXp >= newLevel * 100) {
      newXp -= newLevel * 100;
      newLevel++;
    }

    setState(() {
      _xp = newXp;
      _level = newLevel;
    });

    await FirebaseFirestore.instance
        .collection("user_progress")
        .doc(user!.uid)
        .set({
      "xp": newXp,
      "level": newLevel,
      "updatedAt": FieldValue.serverTimestamp(),
    });

   if (newLevel > oldLevel) {
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mounted) _showLevelUpDialog(newLevel);
  });
}
  }
// Add this method to show gamification info dialog
void _showGamificationInfo() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Text('🎮 ', style: TextStyle(fontSize: 28)),
          const Text(
            'Gamification System',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Earn XP and Level Up!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Track your health consistently to earn experience points (XP) and level up!',
              style: TextStyle(fontSize: 14),
            ),
            const Divider(height: 24),
            
            // XP earning breakdown
            const Text(
              '💎 How to Earn XP:',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildXpRow('📝 Create a log', '+20 XP'),
            _buildXpRow('🍽️ Add foods', '+10 XP'),
            _buildXpRow('🏃 Log activity', '+10 XP'),
            _buildXpRow('💧 Track water', '+5 XP'),
            _buildXpRow('😴 Log sleep', '+5 XP'),
            _buildXpRow('✏️ Update a log', '+10 XP'),
            
            const Divider(height: 24),
            
            const Text(
              '⭐ Level Progress:',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You need ${_nextLevelXp} XP to reach Level ${_level + 1}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Progress: $_xp / $_nextLevelXp XP',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            
            const Divider(height: 24),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '💡 Tip: Log your meals and activities daily to level up faster and maintain healthy habits!',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it!'),
        ),
      ],
    ),
  );
}


Widget _buildXpRow(String action, String xp) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(action, style: const TextStyle(fontSize: 13)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            xp,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
            ),
          ),
        ),
      ],
    ),
  );
}


void _showLevelUpDialog(int newLevel) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      title: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 8),
          const Text(
            'Level Up!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade100, Colors.blue.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'You reached',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Level $newLevel',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Congratulations! 🌟',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep logging your health data to continue leveling up!',
            style: TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Awesome! Keep Going!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

  /// ============ SAVE LOG WITH NUTRITION CALCULATIONS ============
  Future<void> _saveLog() async {
    if (_formKey.currentState!.validate() && user != null) {
      // Calculate nutrition totals from selected foods
      double logCalories = 0;
      double logProtein = 0;
      double logCarbs = 0;
      double logFat = 0;

      for (var food in _selectedFoods) {
        logCalories += (food['calories'] ?? 0).toDouble();
        logProtein += (food['protein'] ?? 0).toDouble();
        logCarbs += (food['carbs'] ?? 0).toDouble();
        logFat += (food['fat'] ?? 0).toDouble();
      }

      final data = {
  "userId": user!.uid,
  "date": Timestamp.fromDate(DateTime(
    _selectedDate.year,
    _selectedDate.month,
    _selectedDate.day,
    _selectedTime.hour,
    _selectedTime.minute,
  )), // NEW - includes time
  "mealType": _mealType, // NEW
  "foods": _selectedFoods.map((f) => f['name']).toList(),
  "foodsDetailed": _selectedFoods,
  "physicalActivity": _selectedActivity?['name'] ?? _activityController.text.trim(),
"activityDetails": _selectedActivity != null ? {
  "activityId": _selectedActivity!['id'],
  "activityName": _selectedActivity!['name'],
  "emoji": _selectedActivity!['emoji'],
  "category": _selectedActivity!['category'],
  "duration": _activityDuration,
  "intensity": _activityIntensity,
  "caloriesBurned": _caloriesBurned,
  "met": _selectedActivity!['met'][_activityIntensity],
} : null,
"caloriesBurned": _caloriesBurned,
  "weight": double.tryParse(_weightController.text.trim()) ?? 0,
  "waterIntake": double.tryParse(_waterIntakeController.text.trim()) ?? 0,
  "sleepHours": double.tryParse(_sleepHoursController.text.trim()) ?? 0,
  "mood": _mood,
  "notes": _notesController.text.trim(),
  "totalCalories": logCalories,
  "totalProtein": logProtein,
  "totalCarbs": logCarbs,
  "totalFat": logFat,
  "updatedAt": FieldValue.serverTimestamp(),
};

      try {
        if (_editingLogId == null) {
          await _logsCollection.add(data);
          
          // Award XP based on completeness
          int xpGained = 20; // Base XP
          if (_selectedFoods.isNotEmpty) xpGained += 10;
          if (_activityController.text.isNotEmpty) xpGained += 10;
          if (_waterIntakeController.text.isNotEmpty) xpGained += 5;
          if (_sleepHoursController.text.isNotEmpty) xpGained += 5;
          
          await _updateUserProgress(xpGained);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Log added! +$xpGained XP")),
          );
        } else {
          await _logsCollection.doc(_editingLogId).update(data);
          await _updateUserProgress(10);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Log updated! +10 XP")),
          );
        }

        await _calculateDailyNutrition();
        _clearForm();
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

void _clearForm() {
  _mealSearchController.clear();
  _activityController.clear();
  _weightController.clear();
  _waterIntakeController.clear();
  _sleepHoursController.clear();
  _notesController.clear();
  _mood = "Happy";
  _mealType = "Breakfast"; // NEW
  _selectedDate = DateTime.now();
  _selectedTime = TimeOfDay.now(); // NEW
  _selectedFoods = [];
  _editingLogId = null;
  _selectedActivity = null;
_activityIntensity = "moderate";
_activityDuration = 30;
_caloriesBurned = 0;
}

/// ============ FOOD SEARCH WITH AUTOCOMPLETE ============
Future<void> _showFoodSearchDialog() async {
  _mealSearchController.clear();
  
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        List<Map<String, dynamic>> filteredFoods = _allFoods;
        
        if (_mealSearchController.text.isNotEmpty) {
          filteredFoods = _allFoods.where((food) {
            final name = food['name'].toString().toLowerCase();
            final category = food['category'].toString().toLowerCase();
            final query = _mealSearchController.text.toLowerCase();
            return name.contains(query) || category.contains(query);
          }).toList();
        }

        print('🔍 Dialog rebuilding - Total foods: ${_allFoods.length}, Filtered: ${filteredFoods.length}, Selected: ${_selectedFoods.length}');

        return AlertDialog(
          title: Text('🔍 Search Foods (${_selectedFoods.length} selected)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                TextField(
                  controller: _mealSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search foods...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    print('🔍 Search query: $value');
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _allFoods.isEmpty
                      ? const Center(
                          child: Text('Loading foods...'),
                        )
                      : filteredFoods.isEmpty
                          ? const Center(
                              child: Text('No foods found'),
                            )
                          : ListView.builder(
                              itemCount: filteredFoods.length,
                              itemBuilder: (context, index) {
                                final food = filteredFoods[index];
                                final isSelected = _selectedFoods.any((f) => f['id'] == food['id']);
                                
                                return Card(
                                  color: isSelected ? Colors.green.shade50 : Colors.white,
                                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected ? Colors.green : Colors.grey.shade300,
                                      child: Text(
                                        food['category'][0],
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      food['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(food['category']),
                                        Text(
                                          'Per ${food['servingSize']} | ${food['calories']} cal',
                                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                                        ),
                                        Text(
                                          'P: ${food['protein']}g | C: ${food['carbs']}g | F: ${food['fat']}g',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    trailing: Icon(
                                      isSelected ? Icons.check_circle : Icons.add_circle_outline,
                                      color: isSelected ? Colors.green : Colors.grey,
                                      size: 30,
                                    ),
                                    onTap: () {
                                      print('🔍 Tapped on: ${food['name']} (Selected: $isSelected)');
                                      
                                      if (isSelected) {
                                        _selectedFoods.removeWhere((f) => f['id'] == food['id']);
                                        print('❌ Removed ${food['name']}. Count: ${_selectedFoods.length}');
                                        setDialogState(() {});
                                      } else {
                                        // Show serving size selector
                                        _showServingSizeDialog(food, setDialogState);
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('🚫 Cancelled - clearing selections');
                _selectedFoods.clear();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                print('✅ Confirmed ${_selectedFoods.length} foods');
                print('Selected foods: ${_selectedFoods.map((f) => f['name']).toList()}');
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text('Add ${_selectedFoods.length} foods'),
            ),
          ],
        );
      },
    ),
  );
}
void _showServingSizeDialog(Map<String, dynamic> food, Function setParentState) {
  // Common serving sizes with multipliers
  final servingSizes = [
    {'label': '0.5x (${food['servingSize']} / 2)', 'multiplier': 0.5},
    {'label': '1x (${food['servingSize']})', 'multiplier': 1.0},
    {'label': '1.5x', 'multiplier': 1.5},
    {'label': '2x (Double)', 'multiplier': 2.0},
    {'label': '3x (Triple)', 'multiplier': 3.0},
    {'label': 'Custom', 'multiplier': 0.0}, // Will prompt for custom amount
  ];

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Select Serving Size\n${food['name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Base serving: ${food['servingSize']}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            '${food['calories']} cal | P: ${food['protein']}g | C: ${food['carbs']}g',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24),
          ...servingSizes.map((serving) {
            final multiplier = serving['multiplier'] as double;
            final isCustom = multiplier == 0.0;
            
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(serving['label'] as String),
              subtitle: isCustom 
                  ? const Text('Enter your own amount')
                  : Text(
                      '${(food['calories'] * multiplier).toInt()} cal | '
                      'P: ${(food['protein'] * multiplier).toStringAsFixed(1)}g | '
                      'C: ${(food['carbs'] * multiplier).toStringAsFixed(1)}g',
                      style: const TextStyle(fontSize: 11),
                    ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                if (isCustom) {
                  _showCustomServingDialog(food, setParentState);
                } else {
                  _addFoodWithServing(food, multiplier, setParentState);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// ============ CUSTOM SERVING SIZE INPUT ============
void _showCustomServingDialog(Map<String, dynamic> food, Function setParentState) {
  final TextEditingController customController = TextEditingController(text: '1.0');
  
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Custom Serving\n${food['name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter multiplier (e.g., 1.5 for 150g if base is 100g)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: customController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Multiplier',
              hintText: '1.0',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixText: 'x',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
          ),
          onPressed: () {
            final multiplier = double.tryParse(customController.text) ?? 1.0;
            if (multiplier > 0 && multiplier <= 10) {
              Navigator.pop(ctx); // Close custom dialog
              Navigator.pop(context); // Close serving size dialog
              _addFoodWithServing(food, multiplier, setParentState);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a value between 0.1 and 10')),
              );
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}


String _getMealEmoji(String mealType) {
  switch (mealType) {
    case 'Breakfast':
      return '🌅';
    case 'Lunch':
      return '🌞';
    case 'Dinner':
      return '🌆';
    case 'Snack':
      return '🍎';
    case 'Supplement':
      return '💊';
    default:
      return '🍽️';
  }
}

/// ============ ADD FOOD WITH CALCULATED SERVING ============
void _addFoodWithServing(Map<String, dynamic> food, double multiplier, Function setParentState) {
  // Create a new food object with adjusted nutrition values
  final adjustedFood = {
    'id': food['id'],
    'name': food['name'],
    'category': food['category'],
    'servingSize': multiplier == 1.0 
        ? food['servingSize'] 
        : '${food['servingSize']} x $multiplier',
    'servingMultiplier': multiplier,
    'calories': (food['calories'] * multiplier).toDouble(),
    'protein': (food['protein'] * multiplier).toDouble(),
    'carbs': (food['carbs'] * multiplier).toDouble(),
    'fat': (food['fat'] * multiplier).toDouble(),
    'fiber': (food['fiber'] * multiplier).toDouble(),
    'sugar': (food['sugar'] * multiplier).toDouble(),
    // Keep original values for reference
    'originalCalories': food['calories'],
    'originalProtein': food['protein'],
    'originalCarbs': food['carbs'],
    'originalFat': food['fat'],
  };

  _selectedFoods.add(adjustedFood);
  print('✅ Added ${food['name']} with ${multiplier}x serving. Count: ${_selectedFoods.length}');
  print('   Calories: ${adjustedFood['calories'].toInt()} (${food['calories']} x $multiplier)');
  
  // Update parent dialog
  setParentState(() {});
}

Future<void> _showActivitySearchDialog() async {
  final searchController = TextEditingController(); 
  await showDialog(
   context: context,
  builder: (ctx) => StatefulBuilder(
    builder: (context, setDialogState) {
      List<Map<String, dynamic>> filteredActivities = _allActivities;
      
      if (searchController.text.isNotEmpty) {
        filteredActivities = _allActivities.where((activity) {
          final name = activity['name'].toString().toLowerCase();
          final category = activity['category'].toString().toLowerCase();
          final query = searchController.text.toLowerCase();
          return name.contains(query) || category.contains(query);
        }).toList();
      }

        return AlertDialog(
          title: const Text('🏃 Select Activity'),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search activities...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _allActivities.isEmpty
                      ? const Center(child: Text('Loading activities...'))
                      : filteredActivities.isEmpty
                          ? const Center(child: Text('No activities found'))
                          : ListView.builder(
                              itemCount: filteredActivities.length,
                              itemBuilder: (context, index) {
                                final activity = filteredActivities[index];
                                final isSelected = _selectedActivity != null && 
                                                   _selectedActivity!['id'] == activity['id'];
                                
                                return Card(
                                  color: isSelected ? Colors.blue.shade50 : null,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
                                      child: Text(
                                        activity['emoji'],
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                    title: Text(
                                      activity['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      '${activity['category']} | MET: ${activity['met']['moderate']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle, color: Colors.blue)
                                        : const Icon(Icons.add_circle_outline),
                              
onTap: () async { 
    _selectedActivity = activity;
    Navigator.pop(ctx);
    await _showActivityDetailsDialog();
},
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}
Future<void> _showActivityDetailsDialog() async {
  if (_selectedActivity == null) return;
  
 await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        // Get user weight (default to 70kg if not set)
        final userWeight = _userProfile?['weight'] ?? 70.0;
        
        // Calculate calories for preview
        final previewCalories = _calculateCaloriesBurned(
          _selectedActivity!,
          _activityIntensity,
          _activityDuration,
          userWeight
        );

        return AlertDialog(
          title: Row(
            children: [
              Text(_selectedActivity!['emoji'], style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedActivity!['name'],
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Activity description
                Text(
                  _selectedActivity!['description'],
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 20),
                
                // Duration Slider
                const Text(
                  'Duration',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _activityDuration.toDouble(),
                        min: 5,
                        max: 180,
                        divisions: 35,
                        label: '$_activityDuration min',
                        onChanged: (value) {
                          setDialogState(() {
                            _activityDuration = value.toInt();
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '$_activityDuration min',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Intensity Selection
                const Text(
                  'Intensity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                
                ...['light', 'moderate', 'vigorous'].map((intensity) {
                  final isSelected = _activityIntensity == intensity;
                  final met = _selectedActivity!['met'][intensity];
                  final intensityEmoji = intensity == 'light' ? '🟢' : 
                                        intensity == 'moderate' ? '🟡' : '🔴';
                  
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        _activityIntensity = intensity;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(intensityEmoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  intensity.toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.blue : Colors.black,
                                  ),
                                ),
                                Text(
                                  'MET: $met',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.blue),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                
                const Divider(height: 32),
                
                // Calories Preview
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade100, Colors.red.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '🔥',
                        style: TextStyle(fontSize: 32),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          Text(
                            '${previewCalories.toInt()}',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                          const Text(
                            'calories burned',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Formula explanation
                Text(
                  'Based on your weight (${userWeight.toInt()}kg) and activity MET value',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _selectedActivity = null;
                Navigator.pop(ctx);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _caloriesBurned = previewCalories;
                  // Update the activity controller text for display
                  _activityController.text = 
                    '${_selectedActivity!['emoji']} ${_selectedActivity!['name']} - '
                    '$_activityDuration min (${_activityIntensity}) - '
                    '${previewCalories.toInt()} cal';
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Activity'),
            ),
          ],
        );
      },
    ),
  );
}
  /// ============ BUILD FORM DIALOG ============
/// ============ BUILD FORM DIALOG ============
void _openForm({DocumentSnapshot? doc}) {
  if (doc != null) {
    final data = doc.data() as Map<String, dynamic>;
   if (data["activityDetails"] != null) {
  final activityData = data["activityDetails"] as Map<String, dynamic>;
  _selectedActivity = _allActivities.firstWhere(
    (a) => a['id'] == activityData['activityId'],
    orElse: () => {},
  );
  _activityDuration = activityData['duration'] ?? 30;
  _activityIntensity = activityData['intensity'] ?? 'moderate';
  _caloriesBurned = (activityData['caloriesBurned'] ?? 0).toDouble();
  
  _activityController.text = 
    '${activityData['emoji']} ${activityData['activityName']} - '
    '$_activityDuration min (${_activityIntensity}) - '
    '${_caloriesBurned.toInt()} cal';
} 
else {
  _activityController.text = data["physicalActivity"] ?? "";
}
    _weightController.text = (data["weight"] ?? "").toString();
    _waterIntakeController.text = (data["waterIntake"] ?? "").toString();
    _sleepHoursController.text = (data["sleepHours"] ?? "").toString();
    _notesController.text = data["notes"] ?? "";
    _mood = data["mood"] ?? "Happy";
    _mealType = data["mealType"] ?? "Breakfast"; // NEW
    
    // Extract date and time
    final dateTime = (data["date"] as Timestamp).toDate();
    _selectedDate = dateTime;
    _selectedTime = TimeOfDay(hour: dateTime.hour, minute: dateTime.minute); // NEW
    
    _selectedFoods = List<Map<String, dynamic>>.from(data["foodsDetailed"] ?? []);
    _editingLogId = doc.id;
  } else {
    _clearForm();
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(  // ADD THIS!
      builder: (context, setModalState) => Container(  // ADD THIS!
        height: MediaQuery.of(ctx).size.height * 0.9,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade200, Colors.purple.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 25,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _editingLogId == null ? "➕ Add Health Log" : "✏️ Edit Health Log",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Date picker
                Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.15),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    children: [
      // Date Picker
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today, color: Colors.white),
        title: const Text("Date", style: TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(
          DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setState(() => _selectedDate = picked);
            setModalState(() {});
          }
        },
      ),
      const Divider(color: Colors.white24),
      // Time Picker
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.access_time, color: Colors.white),
        title: const Text("Time", style: TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(
          _selectedTime.format(context),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: _selectedTime,
          );
          if (picked != null) {
            setState(() => _selectedTime = picked);
            setModalState(() {});
          }
        },
      ),
    ],
  ),
),

const SizedBox(height: 12),

// Meal Type Selector
DropdownButtonFormField<String>(
  value: _mealType,
  dropdownColor: Colors.teal.shade100,
  decoration: InputDecoration(
    labelText: "Meal Type",
    labelStyle: const TextStyle(color: Colors.white),
    filled: true,
    fillColor: Colors.white.withOpacity(0.15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    prefixIcon: Icon(
      _getMealEmoji(_mealType) == '🌅' ? Icons.wb_sunny :
      _getMealEmoji(_mealType) == '🌞' ? Icons.lunch_dining :
      _getMealEmoji(_mealType) == '🌆' ? Icons.dinner_dining :
      _getMealEmoji(_mealType) == '🍎' ? Icons.apple :
      Icons.medication,
      color: Colors.white,
    ),
  ),
  items: [
    DropdownMenuItem(
      value: "Breakfast",
      child: Row(
        children: const [
          Text('🌅', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Breakfast'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: "Lunch",
      child: Row(
        children: const [
          Text('🌞', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Lunch'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: "Dinner",
      child: Row(
        children: const [
          Text('🌆', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Dinner'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: "Snack",
      child: Row(
        children: const [
          Text('🍎', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Snack'),
        ],
      ),
    ),
    DropdownMenuItem(
      value: "Supplement",
      child: Row(
        children: const [
          Text('💊', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Supplement'),
        ],
      ),
    ),
  ],
  onChanged: (val) {
    setState(() => _mealType = val!);
    setModalState(() {});
  },
),

const SizedBox(height: 12),
                  
                  // Food selection button - UPDATED
                  ElevatedButton.icon(
                    onPressed: () async {
                     await _showFoodSearchDialog();
                      setModalState(() {}); // This will update the button text
                    },
                    icon: const Icon(Icons.restaurant_menu),
                    label: Text('Select Foods (${_selectedFoods.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  


// Show selected foods
if (_selectedFoods.isNotEmpty) ...[
  const SizedBox(height: 12),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Selected Foods:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_selectedFoods.fold<double>(0, (sum, f) => sum + (f['calories'] ?? 0)).toInt()} cal total',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedFoods.map((food) {
            final servingInfo = food['servingMultiplier'] != null && food['servingMultiplier'] != 1.0
                ? ' (${food['servingMultiplier']}x)'
                : '';
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${food['name']}$servingInfo',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${food['calories'].toInt()} cal | P:${food['protein'].toStringAsFixed(1)}g C:${food['carbs'].toStringAsFixed(1)}g',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFoods.remove(food);
                      });
                      setModalState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ),
  ),
],
                  
                  const SizedBox(height: 12),
                  Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ElevatedButton.icon(
    onPressed: () async {
await _showActivitySearchDialog();
setModalState(() {});
},
      icon: const Icon(Icons.fitness_center),
      label: Text(_selectedActivity == null 
        ? 'Select Activity' 
        : '${_selectedActivity!['emoji']} ${_selectedActivity!['name']}'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
      ),
    ),
    if (_selectedActivity != null) ...[
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_activityDuration min',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _activityIntensity.toUpperCase(),
                  style: TextStyle(
                    color: _activityIntensity == 'light' ? Colors.green :
                           _activityIntensity == 'moderate' ? Colors.yellow :
                           Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  '🔥',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_caloriesBurned.toInt()} calories burned',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedActivity = null;
                  _activityController.clear();
                  _caloriesBurned = 0;
                });
                setModalState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                minimumSize: const Size(double.infinity, 36),
              ),
              child: const Text('Remove Activity'),
            ),
          ],
        ),
      ),
    ],
  ],
),
                  const SizedBox(height: 12),
                  _buildTextField(_weightController, "Weight (kg)", isNumber: true),
                  const SizedBox(height: 12),
                  _buildTextField(_waterIntakeController, "Water Intake (ml)", isNumber: true),
                  const SizedBox(height: 12),
                  _buildTextField(_sleepHoursController, "Sleep Hours", isNumber: true),
                  const SizedBox(height: 12),
                  
                  // Mood dropdown
                  DropdownButtonFormField<String>(
                    value: _mood,
                    dropdownColor: Colors.teal.shade100,
                    items: ["Happy", "Neutral", "Sad", "Tired", "Energetic", "Stressed"]
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      setState(() => _mood = val!);
                      setModalState(() {}); // UPDATE MODAL!
                    },
                    decoration: _inputDecoration("Mood"),
                  ),
                  
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: _inputDecoration("Notes"),
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                  ),
                  
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveLog,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      _editingLogId == null ? "Add Log" : "Update Log",
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white),
      filled: true,
      fillColor: Colors.white.withOpacity(0.15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

 Widget _buildTextField(TextEditingController controller, String label,
    {bool isNumber = false}) {
  return TextFormField(
    controller: controller,
    keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    decoration: _inputDecoration(label),
    style: const TextStyle(color: Colors.white),
    validator: (value) {
      // Make Weight and Sleep Hours optional
      if (label == "Weight (kg)" || label == "Sleep Hours") {
        if (value != null && value.isNotEmpty) {
          final parsed = double.tryParse(value);
          if (parsed == null || parsed <= 0) {
            return "Please enter a valid number";
          }
        }
        return null; // Optional field
      }
      
      // Water Intake is also optional but validates if filled
      if (label == "Water Intake (ml)") {
        if (value != null && value.isNotEmpty) {
          final parsed = double.tryParse(value);
          if (parsed == null || parsed < 0) {
            return "Please enter a valid number";
          }
        }
        return null; // Optional field
      }
      
      return null; // All fields are now optional
    },
  );
}

  /// ============ BUILD PROGRESS BAR ============
  Widget _buildProgressBar() {
  double progress = _xp / _nextLevelXp;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                "Level $_level",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showGamificationInfo,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          Text(
            "XP: $_xp / $_nextLevelXp",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Stack(
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple, Colors.purple.shade300],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        '${(progress * 100).toInt()}% to next level',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
        ),
      ),
    ],
  );
}

  /// ============ BUILD NUTRITION SUMMARY CARD ============
  Widget _buildNutritionSummary() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Nutrition",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildNutritionBar('Calories', _totalCalories, _calorieGoal, Colors.orange),
            const SizedBox(height: 12),
            _buildNutritionBar('Protein (g)', _totalProtein, _proteinGoal, Colors.red),
            const SizedBox(height: 12),
            _buildNutritionBar('Carbs (g)', _totalCarbs, _carbsGoal, Colors.blue),
            const SizedBox(height: 12),
            _buildNutritionBar('Fat (g)', _totalFat, _fatGoal, Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionBar(String label, double current, double goal, Color color) {
    final percentage = (current / goal * 100).clamp(0, 150);
    final isOver = current > goal;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${current.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)}',
              style: TextStyle(
                color: isOver ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: (current / goal).clamp(0.0, 1.0),
          backgroundColor: Colors.grey.shade200,
          color: isOver ? Colors.red : color,
          minHeight: 8,
        ),
        if (isOver)
          Text(
            '⚠️ ${(current - goal).toStringAsFixed(0)} over goal',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
      ],
    );
  }

  /// ============ BUILD MAIN UI ============
  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No user found.")),
      );
    }
return Scaffold(
  appBar: AppBar(
    title: const Text(
      "My Health Logs",
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
        fontSize: 22,
      ),
    ),
    centerTitle: true,
    elevation: 0,
    flexibleSpace: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade400, Colors.purple.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    ),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 32),
          labelColor: Colors.white,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            shadows: [
              Shadow(
                color: Colors.black26,
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          unselectedLabelColor: Colors.white.withOpacity(0.85),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 20),
          tabs: [
            Tab(
              height: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.list_alt_rounded, size: 24),
                    SizedBox(width: 10),
                    Text('Logs'),
                  ],
                ),
              ),
            ),
            Tab(
              height: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.analytics_rounded, size: 24),
                    SizedBox(width: 10),
                    Text('Analytics'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
  body: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.teal.shade300, Colors.purple.shade200],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: TabBarView(
      controller: _tabController,
      children: [
        _buildLogsTab(),
        _buildAnalyticsTab(),
      ],
    ),
  ),
  floatingActionButton: FloatingActionButton(
    backgroundColor: Colors.deepPurple,
    onPressed: () => _openForm(),
    child: const Icon(Icons.add, color: Colors.white),
  ),
);
  }

  /// ============ LOGS TAB ============
  Widget _buildLogsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildProgressBar(),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _logsCollection
                .where("userId", isEqualTo: user!.uid)
                .orderBy("updatedAt", descending: true)
                .limit(30)
                .snapshots(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text("Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.white)),
                );
              }

              // CORRECT:
final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    "No health logs yet.\nTap + to add one!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (ctx, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final date = (data["date"] as Timestamp?)?.toDate();

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 6,
                    margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                         Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meal Type and Date
          Row(
            children: [
              Text(
                _getMealEmoji(data["mealType"] ?? "Breakfast"),
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["mealType"] ?? "Meal",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    if (date != null)
                      Text(
                        DateFormat('dd MMM yyyy, h:mm a').format(date),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
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
    Row(
      children: [
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.blue),
          onPressed: () => _openForm(doc: doc),
        ),
       IconButton(
  icon: const Icon(Icons.delete, color: Colors.redAccent),
  onPressed: () async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Log?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this log? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _logsCollection.doc(doc.id).delete();
      await _calculateDailyNutrition();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Log deleted")),
      );
    }
  },
),
      ],
    )
  ],
),

                          const Divider(),
                          
                          // Nutrition Summary
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildNutrientChip('🔥', '${data["totalCalories"]?.toInt() ?? 0}', 'cal'),
                                _buildNutrientChip('🥩', '${data["totalProtein"]?.toInt() ?? 0}', 'P'),
                                _buildNutrientChip('🍞', '${data["totalCarbs"]?.toInt() ?? 0}', 'C'),
                                _buildNutrientChip('🥑', '${data["totalFat"]?.toInt() ?? 0}', 'F'),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Foods eaten
                          if (data["foods"] != null && (data["foods"] as List).isNotEmpty) ...[
                            const Text('Foods:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: (data["foods"] as List).map((food) => 
                                Chip(
                                  label: Text(food),
                                  backgroundColor: Colors.green.shade100,
                                  padding: EdgeInsets.zero,
                                )
                              ).toList(),
                            ),
                          ],
                          
                          const SizedBox(height: 8),
                          
                        
                         // Activity Section
if (data["activityDetails"] != null) ...[
  Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              (data["activityDetails"]["emoji"] ?? '🏃‍♂️').toString(),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data["activityDetails"]["activityName"] ?? "Activity",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${data["activityDetails"]["duration"] ?? 0} min'),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (data["activityDetails"]["intensity"] == 'light')
                    ? Colors.green.shade100
                    : (data["activityDetails"]["intensity"] == 'moderate')
                        ? Colors.yellow.shade100
                        : Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                (data["activityDetails"]["intensity"] ?? '').toString().toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  '${(data["activityDetails"]["caloriesBurned"] ?? 0).toInt()} cal',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ),
] else if (data["physicalActivity"] != null && data["physicalActivity"].toString().isNotEmpty)
  // Fallback for old logs without activity details
  Row(
    children: [
      const Icon(Icons.fitness_center, size: 18, color: Colors.grey),
      const SizedBox(width: 6),
      Expanded(child: Text("Activity: ${data["physicalActivity"]}")),
    ],
  ),

                          
                          const SizedBox(height: 4),
                          
                          // Weight
                          if (data["weight"] != null && data["weight"] > 0)
                            Row(
                              children: [
                                const Icon(Icons.monitor_weight, size: 18, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text("Weight: ${data["weight"]} kg"),
                              ],
                            ),
                          
                          const SizedBox(height: 4),
                          
                          // Water intake
                          if (data["waterIntake"] != null && data["waterIntake"] > 0)
                            Row(
                              children: [
                                const Icon(Icons.water_drop, size: 18, color: Colors.blue),
                                const SizedBox(width: 6),
                                Text("Water: ${data["waterIntake"]} ml"),
                              ],
                            ),
                          
                          const SizedBox(height: 4),
                          
                          // Sleep
                          if (data["sleepHours"] != null && data["sleepHours"] > 0)
                            Row(
                              children: [
                                const Icon(Icons.bedtime, size: 18, color: Colors.indigo),
                                const SizedBox(width: 6),
                                Text("Sleep: ${data["sleepHours"]} hours"),
                              ],
                            ),
                          
                          const SizedBox(height: 4),
                          
                          // Mood
                          Row(
                            children: [
                              const Icon(Icons.mood, size: 18, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text("Mood: ${data["mood"] ?? ""}"),
                            ],
                          ),
                          
                          // Notes
                          if (data["notes"] != null && data["notes"].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "Notes: ${data["notes"]}",
                                style: const TextStyle(fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNutrientChip(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }


Widget _buildMealTimingInsight(List<QueryDocumentSnapshot> logs) {
  if (logs.isEmpty) {
    return const Text('Log more meals to see insights!');
  }
  
  // Analyze breakfast timing
  final breakfastLogs = logs.where((log) {
    final data = log.data() as Map<String, dynamic>;
    return data['mealType'] == 'Breakfast';
  }).toList();
  
  if (breakfastLogs.isEmpty) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'You haven\'t logged any breakfasts this week. Breakfast helps kickstart your metabolism!',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
  
  // Calculate average breakfast time
  int totalMinutes = 0;
  for (var log in breakfastLogs) {
    final data = log.data() as Map<String, dynamic>;
    final dateTime = (data['date'] as Timestamp).toDate();
    totalMinutes += dateTime.hour * 60 + dateTime.minute;
  }
  final avgMinutes = totalMinutes ~/ breakfastLogs.length;
  final avgHour = avgMinutes ~/ 60;
  final avgMinute = avgMinutes % 60;
  
  String insight;
  Color insightColor;
  
  if (avgHour < 7) {
    insight = '🌟 Great! You\'re an early bird. Eating breakfast before 7 AM is excellent for metabolism.';
    insightColor = Colors.green;
  } else if (avgHour < 10) {
    insight = '✅ Good timing! Your average breakfast time (${avgHour}:${avgMinute.toString().padLeft(2, '0')}) is within the ideal window.';
    insightColor = Colors.blue;
  } else {
    insight = '💡 Consider eating breakfast earlier. Late breakfast (after 10 AM) may affect your energy levels.';
    insightColor = Colors.orange;
  }
  
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: insightColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: insightColor.withOpacity(0.3)),
    ),
    child: Text(
      insight,
      style: const TextStyle(fontSize: 13),
    ),
  );
}

Color _getMealColor(String mealType) {
  switch (mealType) {
    case 'Breakfast':
      return Colors.orange;
    case 'Lunch':
      return Colors.green;
    case 'Dinner':
      return Colors.blue;
    case 'Snack':
      return Colors.purple;
    case 'Supplement':
      return Colors.red;
    default:
      return Colors.grey;
  }
}








  /// ============ ANALYTICS TAB ============
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildNutritionSummary(),
          
          // Weekly summary card
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "This Week's Summary",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: _logsCollection
                        .where("userId", isEqualTo: user!.uid)
                        .where("date", isGreaterThanOrEqualTo: 
                          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7))))
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      final logs = snapshot.data!.docs;
                      int totalLogs = logs.length;
                      double avgCalories = 0;
                      double avgProtein = 0;
                      
                      for (var log in logs) {
                        final data = log.data() as Map<String, dynamic>;
                        avgCalories += (data['totalCalories'] ?? 0).toDouble();
                        avgProtein += (data['totalProtein'] ?? 0).toDouble();
                      }
                      
                      if (totalLogs > 0) {
                        avgCalories /= totalLogs;
                        avgProtein /= totalLogs;
                      }
                      
                      return Column(
                        children: [
                          _buildStatRow('📊 Logs This Week', totalLogs.toString()),
                          const SizedBox(height: 8),
                          _buildStatRow('🔥 Avg Calories/Day', avgCalories.toStringAsFixed(0)),
                          const SizedBox(height: 8),
                          _buildStatRow('🥩 Avg Protein/Day', '${avgProtein.toStringAsFixed(0)}g'),
                          const SizedBox(height: 8),
                          _buildStatRow('⭐ Current Level', _level.toString()),
                          const SizedBox(height: 8),
                          _buildStatRow('🎯 Total XP', _xp.toString()),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Meal Timing Analysis Card
Card(
  margin: const EdgeInsets.all(16),
  elevation: 8,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🍽️ Meal Patterns",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: _logsCollection
              .where("userId", isEqualTo: user!.uid)
              .where("date", isGreaterThanOrEqualTo: 
                Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7))))
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final logs = snapshot.data!.docs;
            
            // Count meals by type
            Map<String, int> mealCounts = {
              'Breakfast': 0,
              'Lunch': 0,
              'Dinner': 0,
              'Snack': 0,
              'Supplement': 0,
            };
            
            // Calculate average calories by meal type
            Map<String, double> mealCalories = {
              'Breakfast': 0,
              'Lunch': 0,
              'Dinner': 0,
              'Snack': 0,
              'Supplement': 0,
            };
            
            for (var log in logs) {
              final data = log.data() as Map<String, dynamic>;
              final mealType = data['mealType'] ?? 'Breakfast';
              final calories = (data['totalCalories'] ?? 0).toDouble();
              
              mealCounts[mealType] = (mealCounts[mealType] ?? 0) + 1;
              mealCalories[mealType] = (mealCalories[mealType] ?? 0) + calories;
            }
            
            // Calculate averages
            mealCalories.forEach((key, value) {
              if (mealCounts[key]! > 0) {
                mealCalories[key] = value / mealCounts[key]!;
              }
            });
            
            return Column(
              children: [
                // Meal frequency bars
                ...mealCounts.entries.map((entry) {
                  final percentage = logs.isEmpty ? 0.0 : (entry.value / logs.length);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _getMealEmoji(entry.key),
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            Text(
                              '${entry.value} logs | Avg: ${mealCalories[entry.key]?.toInt() ?? 0} cal',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: percentage,
                          backgroundColor: Colors.grey.shade200,
                          color: _getMealColor(entry.key),
                          minHeight: 8,
                        ),
                      ],
                    ),
                  );
                }).toList(),
                
                const Divider(height: 24),
                
                // Meal timing insights
                _buildMealTimingInsight(logs),
              ],
            );
          },
        ),
      ],
    ),
  ),
),
          // Insights card
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "💡 Personalized Insights",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildInsightCard(
                    '🎯 Daily Goals',
                    'Calories: ${_calorieGoal.toInt()}\nProtein: ${_proteinGoal.toInt()}g\nCarbs: ${_carbsGoal.toInt()}g\nFat: ${_fatGoal.toInt()}g',
                    Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildInsightCard(
                    '📈 Progress',
                    _totalCalories > _calorieGoal * 0.9
                        ? 'Great! You\'re meeting your calorie goals!'
                        : 'Try to reach your daily calorie goal for optimal energy.',
                    _totalCalories > _calorieGoal * 0.9 ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  _buildInsightCard(
                    '💪 Recommendation',
                    _totalProtein < _proteinGoal * 0.8
                        ? 'Increase protein intake for muscle recovery'
                        : 'Excellent protein intake! Keep it up!',
                    _totalProtein < _proteinGoal * 0.8 ? Colors.orange : Colors.green,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
        ),
      ],
    );
  }

  Widget _buildInsightCard(String title, String content, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(content, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}