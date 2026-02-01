import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_preferences.dart';

class PreferencesService {
  static const String _userIdKey = 'user_id';
  static const String backendUrl = 'http://10.37.93.185:8000';

  /// Get or generate user ID
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(_userIdKey);

    if (userId == null) {
      // Generate new UUID
      userId = const Uuid().v4();
      await prefs.setString(_userIdKey, userId);
    }

    return userId;
  }

  /// Check if user has completed onboarding (has preferences)
  static Future<bool> hasCompletedOnboarding() async {
    final userId = await getUserId();
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/preferences/$userId'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error checking onboarding status: $e');
      return false;
    }
  }

  /// Create user preferences (first time)
  static Future<UserPreferences?> createPreferences(String rawPreferences) async {
    final userId = await getUserId();

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/preferences/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'raw_preferences': rawPreferences,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserPreferences.fromJson(data);
      } else {
        print('Failed to create preferences: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating preferences: $e');
      return null;
    }
  }

  /// Get user preferences
  static Future<UserPreferences?> getPreferences() async {
    final userId = await getUserId();

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/preferences/$userId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserPreferences.fromJson(data);
      } else if (response.statusCode == 404) {
        // User hasn't set preferences yet
        return null;
      } else {
        print('Failed to get preferences: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting preferences: $e');
      return null;
    }
  }

  /// Update user preferences
  static Future<UserPreferences?> updatePreferences(String rawPreferences) async {
    final userId = await getUserId();

    try {
      final response = await http.put(
        Uri.parse('$backendUrl/preferences/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'raw_preferences': rawPreferences,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserPreferences.fromJson(data);
      } else {
        print('Failed to update preferences: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error updating preferences: $e');
      return null;
    }
  }

  /// Clear user data (for testing)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
  }
}
