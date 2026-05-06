// ============================================
// NutriTrack - Additional Test Cases (5 more)
// Total: 3 (existing) + 5 (new) = 8 tests
// ============================================

import 'package:flutter_test/flutter_test.dart';

// ============================================
// TEST 4: Nutritional Calculation Accuracy
// ============================================
void testNutritionalCalculations() {
  group('Nutritional Calculation Tests', () {
    test('Calculate total calories from multiple foods', () {
      // Simulate 3 foods selected
      final foods = [
        {'name': 'Rice', 'calories': 180.0, 'protein': 3.0, 'carbs': 38.0, 'fat': 1.0},
        {'name': 'Chicken', 'calories': 165.0, 'protein': 31.0, 'carbs': 0.0, 'fat': 3.6},
        {'name': 'Broccoli', 'calories': 55.0, 'protein': 3.7, 'carbs': 11.0, 'fat': 0.6},
      ];

      double totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;

      for (var food in foods) {
        totalCalories += food['calories'] as double;
        totalProtein += food['protein'] as double;
        totalCarbs += food['carbs'] as double;
        totalFat += food['fat'] as double;
      }

      expect(totalCalories, closeTo(400.0, 0.01));
      expect(totalProtein, closeTo(37.7, 0.01));
      expect(totalCarbs, closeTo(49.0, 0.01));
      expect(totalFat, closeTo(5.2, 0.01));
    });

    test('Calculate BMI correctly', () {
      double calculateBMI(double weight, double height) {
        final heightInMeters = height / 100;
        return weight / (heightInMeters * heightInMeters);
      }

      final bmi = calculateBMI(80, 170); // 80kg, 170cm
      expect(bmi, closeTo(27.68, 0.01));
    });

    test('BMI category classification', () {
      String getBMICategory(double bmi) {
        if (bmi < 18.5) return 'Underweight';
        if (bmi < 25) return 'Normal';
        if (bmi < 30) return 'Overweight';
        return 'Obese';
      }

      expect(getBMICategory(17.5), equals('Underweight'));
      expect(getBMICategory(22.0), equals('Normal'));
      expect(getBMICategory(27.7), equals('Overweight'));
      expect(getBMICategory(32.0), equals('Obese'));
    });

    test('Food serving multiplier calculation', () {
      final baseFood = {
        'name': 'Rice',
        'calories': 130.0,
        'protein': 2.7,
        'servingSize': '100g'
      };
      
      final multiplier = 1.5; // 1.5x serving
      
      final adjustedCalories = (baseFood['calories'] as double) * multiplier;
      final adjustedProtein = (baseFood['protein'] as double) * multiplier;
      
      expect(adjustedCalories, closeTo(195.0, 0.01));
      expect(adjustedProtein, closeTo(4.05, 0.01));
    });
  });
}

// ============================================
// TEST 5: Symptom Severity Assessment
// ============================================
void testSymptomChecker() {
  group('Symptom Checker Logic Tests', () {
    test('Symptom severity classification', () {
      String classifySeverity(String severity) {
        return severity.toLowerCase();
      }

      expect(classifySeverity('Mild'), equals('mild'));
      expect(classifySeverity('Moderate'), equals('moderate'));
      expect(classifySeverity('Severe'), equals('severe'));
    });

    test('Calculate symptom duration in days', () {
      int calculateDurationDays(String duration) {
        switch (duration) {
          case 'Less than 1 hour':
            return 0;
          case '1-6 hours':
            return 0;
          case '6-24 hours':
            return 1;
          case '1-3 days':
            return 2;
          case '3-7 days':
            return 5;
          case '1-2 weeks':
            return 10;
          case '2-4 weeks':
            return 21;
          case 'More than 1 month':
            return 35;
          default:
            return 0;
        }
      }

      expect(calculateDurationDays('1-3 days'), equals(2));
      expect(calculateDurationDays('1-2 weeks'), equals(10));
      expect(calculateDurationDays('More than 1 month'), equals(35));
    });

    test('Red flag detection for severe symptoms', () {
      bool hasRedFlags(List<String> symptoms, String severity) {
        if (severity.toLowerCase() == 'severe') return true;
        
        final criticalSymptoms = ['chest pain', 'difficulty breathing', 
                                   'severe headache', 'high fever'];
        
        return symptoms.any((symptom) => 
          criticalSymptoms.any((critical) => 
            symptom.toLowerCase().contains(critical)
          )
        );
      }

      expect(hasRedFlags(['headache'], 'severe'), isTrue);
      expect(hasRedFlags(['chest pain'], 'mild'), isTrue);
      expect(hasRedFlags(['cough'], 'mild'), isFalse);
    });

    test('ICD-10 code validation format', () {
      bool isValidICD10(String code) {
        // Basic ICD-10 format: Letter followed by 2-3 digits
        final regex = RegExp(r'^[A-Z]\d{2,3}(\.\d+)?$');
        return regex.hasMatch(code);
      }

      expect(isValidICD10('M79.1'), isTrue);  // Body aches
      expect(isValidICD10('R50.9'), isTrue);  // Fever
      expect(isValidICD10('ABC'), isFalse);    // Invalid
      expect(isValidICD10('123'), isFalse);    // Invalid
    });
  });
}

// ============================================
// TEST 6: Appointment Booking Validation
// ============================================
void testAppointmentBooking() {
  group('Appointment Booking Tests', () {
    test('Validate appointment date is not in the past', () {
      bool isValidAppointmentDate(DateTime appointmentDate) {
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final appointmentStart = DateTime(
          appointmentDate.year, 
          appointmentDate.month, 
          appointmentDate.day
        );
        
        return appointmentStart.isAfter(todayStart) || 
               appointmentStart.isAtSameMomentAs(todayStart);
      }

      final tomorrow = DateTime.now().add(Duration(days: 1));
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      
      expect(isValidAppointmentDate(tomorrow), isTrue);
      expect(isValidAppointmentDate(yesterday), isFalse);
    });

    test('Appointment time slot validation', () {
      bool isValidTimeSlot(String timeSlot) {
        final validSlots = [
          '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM',
          '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
          '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM',
          '02:00 PM', '02:30 PM', '03:00 PM', '03:30 PM',
          '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM',
          '06:00 PM'
        ];
        
        return validSlots.contains(timeSlot);
      }

      expect(isValidTimeSlot('09:00 AM'), isTrue);
      expect(isValidTimeSlot('02:30 PM'), isTrue);
      expect(isValidTimeSlot('07:00 PM'), isFalse);  // Outside hours
      expect(isValidTimeSlot('invalid'), isFalse);
    });

    test('Appointment reason validation', () {
      String? validateReason(String reason) {
        if (reason.trim().isEmpty) {
          return 'Please provide a reason for visit';
        }
        if (reason.trim().length < 10) {
          return 'Please provide more details (at least 10 characters)';
        }
        return null; // Valid
      }

      expect(validateReason(''), equals('Please provide a reason for visit'));
      expect(validateReason('Headache'), equals('Please provide more details (at least 10 characters)'));
      expect(validateReason('Severe headache for 3 days'), isNull);
    });

    test('Calculate appointment statistics', () {
      final appointments = [
        {'status': 'pending'},
        {'status': 'pending'},
        {'status': 'approved'},
        {'status': 'approved'},
        {'status': 'approved'},
        {'status': 'completed'},
        {'status': 'rejected'},
      ];

      int countByStatus(List<Map<String, String>> apts, String status) {
        return apts.where((a) => a['status'] == status).length;
      }

      expect(countByStatus(appointments, 'pending'), equals(2));
      expect(countByStatus(appointments, 'approved'), equals(3));
      expect(countByStatus(appointments, 'completed'), equals(1));
      expect(countByStatus(appointments, 'rejected'), equals(1));
      expect(appointments.length, equals(7)); // Total
    });
  });
}

// ============================================
// TEST 7: Profile Data Validation
// ============================================
void testProfileValidation() {
  group('Profile Validation Tests', () {
    test('Email validation', () {
      bool isValidEmail(String email) {
        return email.isNotEmpty && email.contains('@');
      }

      expect(isValidEmail('test@gmail.com'), isTrue);
      expect(isValidEmail('invalid.email'), isFalse);
      expect(isValidEmail(''), isFalse);
    });

    test('Phone number format validation', () {
      bool isValidPhone(String phone) {
        // Basic validation: +94 format or 07x format
        final regex = RegExp(r'^(\+94|0)[0-9]{9}$');
        return regex.hasMatch(phone.replaceAll(' ', ''));
      }

      expect(isValidPhone('+94712345678'), isTrue);
      expect(isValidPhone('0712345678'), isTrue);
      expect(isValidPhone('12345'), isFalse);
      expect(isValidPhone(''), isFalse);
    });

    test('Age calculation from date of birth', () {
      int calculateAge(DateTime dateOfBirth) {
        final today = DateTime.now();
        int age = today.year - dateOfBirth.year;
        
        if (today.month < dateOfBirth.month ||
            (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
          age--;
        }
        
        return age;
      }

      final birthDate1997 = DateTime(1997, 7, 3);
      final age = calculateAge(birthDate1997);
      
      expect(age, greaterThanOrEqualTo(27));
      expect(age, lessThanOrEqualTo(28));
    });

    test('Weight and height validation', () {
      String? validateMeasurement(String value, String type) {
        if (value.isEmpty) return null; // Optional field
        
        final number = double.tryParse(value);
        if (number == null) return 'Enter a valid number';
        
        if (type == 'weight') {
          if (number <= 0 || number > 300) {
            return 'Weight must be between 1 and 300 kg';
          }
        } else if (type == 'height') {
          if (number <= 0 || number > 250) {
            return 'Height must be between 1 and 250 cm';
          }
        }
        
        return null;
      }

      expect(validateMeasurement('70', 'weight'), isNull);
      expect(validateMeasurement('400', 'weight'), isNotNull);
      expect(validateMeasurement('170', 'height'), isNull);
      expect(validateMeasurement('300', 'height'), isNotNull);
      expect(validateMeasurement('abc', 'weight'), isNotNull);
    });

    test('Blood group validation', () {
      bool isValidBloodGroup(String bloodGroup) {
        final validGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];
        return validGroups.contains(bloodGroup.toUpperCase().trim());
      }

      expect(isValidBloodGroup('O+'), isTrue);
      expect(isValidBloodGroup('AB-'), isTrue);
      expect(isValidBloodGroup('XYZ'), isFalse);
      expect(isValidBloodGroup(''), isFalse);
    });
  });
}

// ============================================
// TEST 8: Activity Calories Calculation
// ============================================
void testActivityTracking() {
  group('Activity Tracking Tests', () {
    test('Calculate calories burned using MET formula', () {
      double calculateCaloriesBurned(
        double met,
        int durationMinutes,
        double weightKg,
      ) {
        // Formula: Calories/min = (MET × 3.5 × Weight in kg) / 200
        final caloriesPerMinute = (met * 3.5 * weightKg) / 200;
        return caloriesPerMinute * durationMinutes;
      }

      // Running (MET 8.0), 30 minutes, 70kg
      final calories = calculateCaloriesBurned(8.0, 30, 70);
      
      expect(calories, closeTo(294.0, 1.0));
    });

    test('MET values for different intensities', () {
      Map<String, double> getActivityMET(String activity, String intensity) {
        final activities = {
          'walking': {'light': 2.5, 'moderate': 3.5, 'vigorous': 5.0},
          'running': {'light': 6.0, 'moderate': 8.0, 'vigorous': 11.0},
          'cycling': {'light': 4.0, 'moderate': 6.8, 'vigorous': 10.0},
        };
        
        return activities[activity] ?? {'moderate': 5.0};
      }

      final walkingModerate = getActivityMET('walking', 'moderate');
      expect(walkingModerate['moderate'], equals(3.5));
      
      final runningVigorous = getActivityMET('running', 'vigorous');
      expect(runningVigorous['vigorous'], equals(11.0));
    });

    test('Activity duration validation', () {
      String? validateDuration(int durationMinutes) {
        if (durationMinutes < 5) {
          return 'Duration must be at least 5 minutes';
        }
        if (durationMinutes > 180) {
          return 'Duration cannot exceed 180 minutes';
        }
        return null;
      }

      expect(validateDuration(30), isNull);
      expect(validateDuration(2), isNotNull);
      expect(validateDuration(200), isNotNull);
    });

    test('Calculate net calories (consumed - burned)', () {
      int calculateNetCalories(int consumed, int burned) {
        return consumed - burned;
      }

      expect(calculateNetCalories(2000, 500), equals(1500));
      expect(calculateNetCalories(1800, 600), equals(1200));
      expect(calculateNetCalories(2500, 300), equals(2200));
    });
  });
}

// ============================================
// MAIN TEST RUNNER
// ============================================
void main() {
  print('🧪 Running NutriTrack Test Suite...\n');
  
  // Run all test groups
  testNutritionalCalculations();
  testSymptomChecker();
  testAppointmentBooking();
  testProfileValidation();
  testActivityTracking();
  
  print('\n✅ All tests completed!');
}