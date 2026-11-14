import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/session_manager.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../01_setup/company_setup_screen.dart';
import '../03_dashboard/admin_dashboard_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiClient.asyncLogin(
      _emailCtrl.text.trim(),
      _passwordCtrl.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      final data = result['data'];
      final user = data['user'];
      final token = data['token'] ?? '';

      // Save persistent session
      final permissions = (data['permissions'] is Map)
          ? Map<String, dynamic>.from(data['permissions'])
          : <String, dynamic>{};

      await SessionManager.saveSession(
        token: token,
        email: user['email'] ?? '',
        role: user['role'] ?? 'Super Admin',
        companyName: user['companyName'] ?? 'Manufacturing Co',
        userId: user['id'],
        companyId: user['companyId'],
        permissions: permissions, // <-- Yeh pass karo
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(
            companyName: user['companyName'] ?? 'Manufacturing Co',
            adminEmail: user['email'] ?? 'admin@erp.com',
            role: user['role'] ?? 'Super Admin',
          ),
        ),
      );
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Invalid credentials. Please try again.';
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width >= 860;

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        // 📱 1. MOBILE NATIVE (SCREEN KE BILKUL CENTER MEIN)
        if (!isDesktop) {
          return Scaffold(
            body: BotanicalBackground(
              showThemeToggle: false,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: _buildMobileLayout(isDark),
                  ),
                ),
              ),
            ),
          );
        }

        // 💻 2. DESKTOP / WEB LAYOUT (Unchanged - Wahi original 2-column frosted card)
        return Scaffold(
          body: BotanicalBackground(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 920,
                        minHeight: 540,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF030D08).withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.15),
                            blurRadius: 40,
                            spreadRadius: 8,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: _buildDesktopLayout(isDark),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(bool isDark) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(44),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF0FDF4).withValues(alpha: 0.6),
                border: Border(
                  right: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
              ),
              child: _buildHeroContent(isDark: isDark),
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 42),
              color: isDark
                  ? const Color(0xFF020906).withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.95),
              child: _buildFormContent(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }

  // 📱 MOBILE NATIVE: CENTERED ALL-IN-ONE LUXURY FROSTED CARD
  Widget _buildMobileLayout(bool isDark) {
    final cardBg = isDark ? const Color(0xFF111C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final textTitle = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.055),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Top Brand + Theme Toggle Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE4E4E7)),
                    ),
                    child: Icon(
                      Icons.precision_manufacturing_rounded,
                      color: isDark ? Colors.white : const Color(0xFF18181B),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'APEX ERP',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: textTitle,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => ThemeController.toggleTheme(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 13, color: isDark ? Colors.amber : const Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(isDark ? 'Light' : 'Dark', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textTitle)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. Greeting
          Text(
            'Welcome back',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: textTitle,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in to access your manufacturing workspace',
            style: TextStyle(fontSize: 13, color: textSub, height: 1.4),
          ),
          const SizedBox(height: 24),

          // 3. Form Fields & Action Button
          _buildFormContent(isDark: isDark, isMobile: true),
        ],
      ),
    );
  }
  Widget _buildHeroContent({required bool isDark, bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: isDark ? 0.2 : 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'APEX ERP',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 16 : 32),
        Text(
          "Let's Get\nStarted",
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Next-Generation Manufacturing & Biometric ERP. Monitor shop-floor operations, attendance logs, and multi-tier workflows in one unified hub.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF475569),
            height: 1.6,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 36),
          _buildFeatureBadge(Icons.fingerprint_rounded, 'Offline Biometric Excel Sync', isDark),
          const SizedBox(height: 12),
          _buildFeatureBadge(Icons.account_tree_outlined, 'Real-time BOM & Work Orders', isDark),
          const SizedBox(height: 12),
          _buildFeatureBadge(Icons.shield_outlined, 'Tier-1 Enterprise Access Control', isDark),
        ],
      ],
    );
  }

  Widget _buildFeatureBadge(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF059669)),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF334155),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFormContent({required bool isDark, bool isMobile = false}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mobile par redundant title skip karenge kyunki upar 'Welcome back' aa chuka hai!
          if (!isMobile) ...[
            Text(
              'Sign in',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your official credentials to access workspace',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildMinimalField(
            controller: _emailCtrl,
            hint: 'Your Email',
            icon: Icons.email_outlined,
            isDark: isDark,
            isMobile: isMobile,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v!.trim().isEmpty ? 'Official email is required' : null,
          ),
          const SizedBox(height: 18),

          _buildMinimalField(
            controller: _passwordCtrl,
            hint: 'Password',
            icon: Icons.lock_outline,
            isDark: isDark,
            isMobile: isMobile,
            isPassword: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8),
                size: 18,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (v) => v!.trim().isEmpty ? 'Password is required' : null,
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: isMobile ? const Color(0xFF18181B) : const Color(0xFF059669),
                      checkColor: Colors.white,
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) => setState(() => _rememberMe = val ?? true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remember me',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              Text(
                'Forgot password?',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B),
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Emerald Button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: isMobile ? (isDark ? const Color(0xFF27272A) : const Color(0xFF18181B)) : const Color(0xFF059669),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Sign in',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'OR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                  thickness: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have a workspace?",
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const CompanySetupScreen()),
                  );
                },
                child: Text(
                  'Sign up here',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isMobile
                        ? (isDark ? Colors.white : const Color(0xFF09090B))
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
    bool isMobile = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF0F172A),
        fontSize: 13.5,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.35) : const Color(0xFF94A3B8),
          fontSize: 13,
        ),
        prefixIcon: Icon(
          icon,
          color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF64748B),
          size: 18,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isMobile
                ? (isDark ? Colors.white : const Color(0xFF18181B))
                : const Color(0xFF059669),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
