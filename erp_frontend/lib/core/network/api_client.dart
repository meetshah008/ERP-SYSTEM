import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String _prodEnvUrl = String.fromEnvironment('API_URL', defaultValue: '');
  static String _currentHost = _resolveInitialHost();

  static String _resolveInitialHost() {
    if (_prodEnvUrl.isNotEmpty) {
      return _prodEnvUrl.endsWith('/') ? _prodEnvUrl.substring(0, _prodEnvUrl.length - 1) : _prodEnvUrl;
    }
    // 💻 When running locally in debug mode on your PC / laptop:
    if (kDebugMode) {
      if (kIsWeb) return 'http://localhost:5000';
      // 📱 When running on Android via USB / `adb reverse`
      return 'http://127.0.0.1:5000';
    }
    // 🌐 When deployed in production (Vercel Web or Production Release APK):
    return 'https://erp-system-ggdk.onrender.com';
  }

  /// Current working backend host (e.g. http://localhost:5000 or https://erp-system-ggdk.onrender.com)
  static String get apiHost => _currentHost;

  /// Current working backend API base url (e.g. http://localhost:5000/api or https://erp-system-ggdk.onrender.com/api)
  static String get baseUrl => '$_currentHost/api';

  static List<String> get _candidateHosts {
    if (_prodEnvUrl.isNotEmpty) {
      return [_prodEnvUrl, 'https://erp-system-ggdk.onrender.com', 'http://localhost:5000', _currentHost];
    }
    if (kDebugMode) {
      return [
        'http://localhost:5000',   // 1. Local PC Web / Desktop
        'http://127.0.0.1:5000',   // 2. Physical Android phone via USB (`adb reverse`)
        'http://10.0.2.2:5000',     // 3. Android Studio Virtual Emulator
        'http://192.168.1.19:5000', // 4. Direct Wi-Fi LAN IP
        'https://erp-system-ggdk.onrender.com', // 5. Cloud fallback if local server is not running
      ];
    }
    return [
      'https://erp-system-ggdk.onrender.com',
      'http://127.0.0.1:5000',
      'http://localhost:5000',
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
