import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/network/session_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/02_auth/login_screen.dart';
import 'features/03_dashboard/admin_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ManufacturingErpApp());
}

class ManufacturingErpApp extends StatelessWidget {
  const ManufacturingErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
        );

        return MaterialApp(
          title: 'Manufacturing ERP',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeAnimationDuration: const Duration(milliseconds: 380),
          themeAnimationCurve: Curves.easeOutCubic,
          // Keep system font scaling from shattering the dense ERP layouts
          // while still respecting users who prefer slightly larger text.
          builder: (context, child) {
            return MediaQuery.withClampedTextScaling(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.2,
              child: child ?? const SizedBox.shrink(),
            );
          },
          // Check session on start: Auto-login to Dashboard if token exists!
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Automatically checks if the user is already logged in
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: SessionManager.getUserSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF050B12),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            ),
          );
        }

        final data = snapshot.data;
        if (data != null &&
            data['isLoggedIn'] == true &&
            (data['token'] as String).isNotEmpty) {
          // Stored session found -> Jump straight to Dashboard!
          return AdminDashboardScreen(
            companyName: data['companyName'] ?? 'Manufacturing Co',
            adminEmail: data['email'] ?? 'admin@erp.com',
            role: data['role'] ?? 'Super Admin',
          );
        }

        // No session found -> Show Login Screen
        return const LoginScreen();
      },
    );
  }
}
