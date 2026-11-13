import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  // Local backend server running on port 5000
  static const String baseUrl = 'http://localhost:5000/api';

  // 1. Company Registration (First-Time Setup)
  static Future<Map<String, dynamic>> asyncRegisterCompany(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register-company'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network Connection Error: $e'};
    }
  }

  // 2. User Login
  static Future<Map<String, dynamic>> asyncLogin(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network Connection Error: $e'};
    }
  }
}
