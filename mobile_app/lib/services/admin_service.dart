import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class AdminService {
  final String apiBaseUrl = kIsWeb ? 'http://localhost:8000/api' : 'http://10.197.25.244:8000/api';

  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService().getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Récupère les statistiques globales (Utilisateurs, Cours, Quiz, etc.)
  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/admin/stats/'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {};
    } catch (e) {
      print('Error fetching admin stats: $e');
      return {};
    }
  }

  /// Récupère la liste de tous les utilisateurs
  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  /// Récupère la liste de tous les cours
  Future<List<Map<String, dynamic>>> getCourses() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/courses/'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching courses: $e');
      return [];
    }
  }

  /// Supprime un utilisateur
  Future<bool> deleteUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/users/$userId/'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 204;
    } catch (e) {
      print('Error deleting user: $e');
      return false;
    }
  }

  /// Supprime un cours
  Future<bool> deleteCourse(int courseId) async {
    try {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/courses/$courseId/'),
        headers: await _getHeaders(),
      );
      return response.statusCode == 204;
    } catch (e) {
      print('Error deleting course: $e');
      return false;
    }
  }
}
