import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../02_auth/login_screen.dart';

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _companyCodeCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _companyNameCtrl.dispose();
    _companyCodeCtrl.dispose();
    _taxIdCtrl.dispose();
    _adminPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSetup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final payload = {
      'company_name': _companyNameCtrl.text.trim(),
      'company_code': _companyCodeCtrl.text.trim().toUpperCase(),
      'tax_id': _taxIdCtrl.text.trim(),
      'currency': 'INR',
      'financial_year_start': '2026-04-01',
      'admin_name': _adminNameCtrl.text.trim(),
      'admin_email': _adminEmailCtrl.text.trim(),
      'admin_password': _adminPassCtrl.text.trim(),
      'first_branch_name': 'Main Plant / Headquarter',
    };

    final result = await ApiClient.asyncRegisterCompany(payload);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Company Workspace Initialized Successfully! Please Login.'),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Failed to setup company.';
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width >= 920;

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

        // 💻 2. DESKTOP / WEB LAYOUT (Unchanged)
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
                        maxWidth: 980,
                        minHeight: 620,
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
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 38),
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

  // 📱 MOBILE NATIVE: CENTERED ALL-IN-ONE CARD
  Widget _buildMobileLayout(bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A).withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.94);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.precision_manufacturing_rounded, color: Color(0xFF10B981), size: 19),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'APEX ERP',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 1.4, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => ThemeController.toggleTheme(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 13, color: isDark ? Colors.amber : const Color(0xFF0F172A)),
                          const SizedBox(width: 4),
                          Text(isDark ? 'Light' : 'Dark', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textTitle)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              Text(
                'Create Workspace',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: textTitle, letterSpacing: -0.5),
              ),
              const SizedBox(height: 3),
              Text('Register your company & Super Admin account', style: TextStyle(fontSize: 12.5, color: textSub)),
              const SizedBox(height: 22),

              _buildFormContent(isDark: isDark, isMobile: true),
            ],
          ),
        ),
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
              child: const Icon(Icons.factory_outlined, color: Color(0xFF059669), size: 22),
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
          'Initialize your company workspace, configure Tier-1 Super Admin access, and deploy multi-branch manufacturing operations.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF475569),
            height: 1.6,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 36),
          _buildFeatureBadge(Icons.business_outlined, 'Multi-Branch & Factory Hierarchy', isDark),
          const SizedBox(height: 12),
          _buildFeatureBadge(Icons.fingerprint_rounded, 'Seamless Biometric Machine Link', isDark),
          const SizedBox(height: 12),
          _buildFeatureBadge(Icons.admin_panel_settings_outlined, 'Isolated Multi-Tenant Security', isDark),
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
        if (!isMobile) ...[
          Text(
            'Sign up',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create your master company workspace & Super Admin account',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
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

          // Admin Name
          _buildMinimalField(
            controller: _adminNameCtrl,
            hint: 'Your name (Admin Full Name)',
            icon: Icons.person_outline,
            isDark: isDark,
            validator: (v) => v!.trim().isEmpty ? 'Admin name is required' : null,
          ),
          const SizedBox(height: 14),

          // Admin Email
          _buildMinimalField(
            controller: _adminEmailCtrl,
            hint: 'Your Email (Official)',
            icon: Icons.email_outlined,
            isDark: isDark,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => v!.trim().isEmpty ? 'Valid official email required' : null,
          ),
          const SizedBox(height: 14),

          // Company Legal Name
          _buildMinimalField(
            controller: _companyNameCtrl,
            hint: 'Company Legal Name (e.g. Apex Mfg Ltd)',
            icon: Icons.business,
            isDark: isDark,
            validator: (v) => v!.trim().isEmpty ? 'Company name required' : null,
          ),
          const SizedBox(height: 14),

          // Company Code & Tax ID (Row)
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _buildMinimalField(
                  controller: _companyCodeCtrl,
                  hint: 'Company Code (e.g. APEX)',
                  icon: Icons.tag,
                  isDark: isDark,
                  validator: (v) => v!.trim().isEmpty ? 'Code required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: _buildMinimalField(
                  controller: _taxIdCtrl,
                  hint: 'GST / Tax ID (Optional)',
                  icon: Icons.receipt_long_outlined,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Master Password
          _buildMinimalField(
            controller: _adminPassCtrl,
            hint: 'Create Password',
            icon: Icons.lock_outline,
            isDark: isDark,
            isPassword: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8),
                size: 18,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
          ),
          const SizedBox(height: 22),

          // Sign up button (Emerald Green)
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
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
                      'Sign up & Launch Workspace',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),

          // Switch to Sign in
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already a Member?',
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
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'Sign in here',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
          borderSide: const BorderSide(color: Color(0xFF059669), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
