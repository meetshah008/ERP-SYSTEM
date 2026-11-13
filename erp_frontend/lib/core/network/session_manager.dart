import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// SessionManager handles storing and retrieving user login state, JWT tokens,
/// and profile info across Web LocalStorage, Windows, and Mobile.
class SessionManager {
  static const String keyToken = 'jwt_token';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyEmail = 'user_email';
  static const String keyRole = 'user_role';
  static const String keyCompanyName = 'company_name';
  static const String keyUserId = 'user_id';
  static const String keyCompanyId = 'company_id';
  static const String keyPermissions = 'user_permissions';

  // 1. LOGIN HONE PAR DATA SAVE KARNA
  static Future<void> saveSession({
    required String token,
    required String email,
    required String role,
    required String companyName,
    int? userId,
    int? companyId,
    Map<String, dynamic>? permissions, // <-- Naya parameter
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyToken, token);
    await prefs.setBool(keyIsLoggedIn, true);
    await prefs.setString(keyEmail, email);
    await prefs.setString(keyRole, role);
    await prefs.setString(keyCompanyName, companyName);
    if (userId != null) await prefs.setInt(keyUserId, userId);
    if (companyId != null) await prefs.setInt(keyCompanyId, companyId);
    if (permissions != null) {
      await prefs.setString(keyPermissions, jsonEncode(permissions));
    }
  }

  // Saari permissions get karna
  static Future<Map<String, bool>> getPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(keyRole) ?? '';
    if (role == 'Super Admin') return {}; // Super admin has full access

    final raw = prefs.getString(keyPermissions);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v == true || v == 1));
    } catch (_) {
      return {};
    }
  }

  // Kisi specific permission ko check karna
  static Future<bool> hasPermission(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(keyRole) ?? '';
    if (role == 'Super Admin') return true;

    final perms = await getPermissions();
    return perms[key] ?? false;
  }

  // 2. CHECK KARNA KI KYA PEHLE SE LOGGED IN HAI?
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsLoggedIn) ?? false;
  }

  // 3. STORED USER DATA RETRIEVE KARNA
  static Future<Map<String, dynamic>> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString(keyToken) ?? '',
      'isLoggedIn': prefs.getBool(keyIsLoggedIn) ?? false,
      'email': prefs.getString(keyEmail) ?? '',
      'role': prefs.getString(keyRole) ?? '',
      'companyName': prefs.getString(keyCompanyName) ?? '',
      'userId': prefs.getInt(keyUserId),
      'companyId': prefs.getInt(keyCompanyId),
    };
  }

  // 4. LOGOUT KARNE PAR DATA CLEAR KARNA
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyToken);
    await prefs.remove(keyIsLoggedIn);
    await prefs.remove(keyEmail);
    await prefs.remove(keyRole);
    await prefs.remove(keyCompanyName);
    await prefs.remove(keyUserId);
    await prefs.remove(keyCompanyId);
    await prefs.remove(keyPermissions);
  }
}
