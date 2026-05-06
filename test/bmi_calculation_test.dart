import 'package:flutter_test/flutter_test.dart';

double calculateBMI(double weight, double height) {
  // Height should be in meters
  return weight / (height * height);
}

String getBMICategory(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}

void main() {
  group('BMI Calculation Tests', () {
    test('Calculate BMI correctly', () {
      double weight = 80; // kg
      double height = 1.70; // meters
      
      double bmi = calculateBMI(weight, height);
      
      expect(bmi, closeTo(27.68, 0.01));
    });

    test('BMI category - Underweight', () {
      expect(getBMICategory(17.5), 'Underweight');
    });

    test('BMI category - Normal', () {
      expect(getBMICategory(22.0), 'Normal');
    });

    test('BMI category - Overweight', () {
      expect(getBMICategory(27.7), 'Overweight');
    });

    test('BMI category - Obese', () {
      expect(getBMICategory(32.0), 'Obese');
    });
  });
}