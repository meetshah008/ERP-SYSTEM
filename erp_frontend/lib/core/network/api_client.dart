import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String _prodEnvUrl = String.fromEnvironment('API_URL', defaultValue: 'https://erp-system-ggdk.onrender.com');
  static String _currentHost = _resolveInitialHost();

  static String _resolveInitialHost() {
    if (_prodEnvUrl.isNotEmpty) {
      return _prodEnvUrl.endsWith('/') ? _prodEnvUrl.substring(0, _prodEnvUrl.length - 1) : _prodEnvUrl;
    }
    if (kIsWeb) return 'https://erp-system-ggdk.onrender.com';
    // 📱 When running `adb reverse tcp:5000 tcp:5000`, 127.0.0.1 maps directly to PC backend
    return 'http://127.0.0.1:5000';
  }

  /// Current working backend host (e.g. https://erp-system-ggdk.onrender.com or http://127.0.0.1:5000)
  static String get apiHost => _currentHost;

  /// Current working backend API base url (e.g. https://erp-system-ggdk.onrender.com/api)
  static String get baseUrl => '$_currentHost/api';

  static List<String> get _candidateHosts {
    if (_prodEnvUrl.isNotEmpty) {
      return [_prodEnvUrl, 'https://erp-system-ggdk.onrender.com', _currentHost];
    }
    return [
      'https://erp-system-ggdk.onrender.com',
      'http://127.0.0.1:5000',   // 1. Physical Android phone via USB (`adb reverse`)
      'http://localhost:5000',   // 2. Web / Desktop
      'http://10.0.2.2:5000',     // 3. Android Studio Virtual Emulator fallback
      'http://192.168.1.19:5000', // 4. Direct Wi-Fi LAN IP fallback
    ];
  }

  // 1. Company Registration (First-Time Setup)
  static Future<Map<String, dynamic>> asyncRegisterCompany(Map<String, dynamic> data) async {
    final hostsToTry = <String>[
      _currentHost,
      ..._candidateHosts.where((h) => h != _currentHost),
    ];

    String lastError = '';
    for (final host in hostsToTry) {
      try {
        final response = await http.post(
          Uri.parse('$host/api/auth/register-company'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ).timeout(const Duration(milliseconds: 2500));

        _currentHost = host;
        return jsonDecode(response.body);
      } catch (e) {
        lastError = e.toString();
      }
    }
    return {'success': false, 'message': 'Network Connection Error: $lastError'};
  }

  // 2. User Login
  static Future<Map<String, dynamic>> asyncLogin(String email, String password) async {
    final hostsToTry = <String>[
      _currentHost,
      ..._candidateHosts.where((h) => h != _currentHost),
    ];

    String lastError = '';
    for (final host in hostsToTry) {
      try {
        final response = await http.post(
          Uri.parse('$host/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        ).timeout(const Duration(milliseconds: 2500));

        _currentHost = host;
        return jsonDecode(response.body);
      } catch (e) {
        lastError = e.toString();
      }
    }
    return {'success': false, 'message': 'Network Connection Error: $lastError'};
  }
}
