import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class FoodService {
  static Map<String, List<String>>? _foodData;

  static Future<void> loadFoodData() async {
    final jsonString = await rootBundle.loadString('services/food.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _foodData = jsonMap.map((key, value) => MapEntry(key, List<String>.from(value)));
  }

  static Map<String, List<String>> get foodData {
    if (_foodData == null) {
      throw Exception("Food data not loaded. Call loadFoodData() first.");
    }
    return _foodData!;
  }
}
