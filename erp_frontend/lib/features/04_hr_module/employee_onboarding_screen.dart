import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../../core/network/api_client.dart';

class EmployeeOnboardingScreen extends StatefulWidget {
  final List<dynamic>? departments;
  final VoidCallback? onEmployeeAdded;

  const EmployeeOnboardingScreen({
    super.key,
    this.departments,
    this.onEmployeeAdded,
  });

  @override
  State<EmployeeOnboardingScreen> createState() => _EmployeeOnboardingScreenState();
}

class _EmployeeOnboardingScreenState extends State<EmployeeOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isLoadingDepartments = false;
  List<dynamic> _departments = [];

  // Active top tab: 0 = Company Details, 1 = Employee Details, 2 = Leaves & Deductions
  int _activeTabIndex = 0;

  // ================= 1. COMPANY DETAILS =================
  int? _selectedDepartmentId;
  String _selectedRole = 'Employee';
  String _selectedManagerModule = 'hr';
  String _selectedEmploymentType = 'Permanent';
  String _selectedWeeklyOff = 'Sunday';
  String _selectedSalaryGrade = 'Grade B (Senior Staff)';
  DateTime _joinDate = DateTime.now();

  final _empCodeController = TextEditingController();
  final _biometricCodeController = TextEditingController();
  final _officialEmailController = TextEditingController();
  final _designationController = TextEditingController();
  final _salaryBaseController = TextEditingController(text: '35000');

  // ================= 2. EMPLOYEE DETAILS (PERSONAL & IDENTITY) =================
  String _selectedGender = 'Male';
  DateTime _dob = DateTime(1998, 1, 1);
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController(text: '28');
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _aadharController = TextEditingController();
  final _panController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _addressController = TextEditingController();

  // ================= 3. LEAVES POLICY & SALARY DEDUCTIONS =================
  final _casualLeaveController = TextEditingController(text: '12');
  final _sickLeaveController = TextEditingController(text: '8');
  final _paidLeaveController = TextEditingController(text: '15');
  final _unpaidLimitController = TextEditingController(text: '10');
  final _unpaidDeductionController = TextEditingController(text: '1166.67');

  // ================= 4. SALARY TEMPLATE (STEP 4) =================
  List<dynamic> _salaryTemplates = [];
  int? _selectedTemplateId;
  bool _loadingTemplates = false;
  List<dynamic> _hrCategories = [];
  int? _selectedHrCategoryId;

  // ================= 5. LOGIN ACCOUNT DETAILS (STEP 5) =================
  bool _enableLoginAccount = false;
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController(text: '123456');
  String _selectedLoginRole = 'Employee';
  String _selectedLoginStatus = 'Active'; // Active, Frozen, Banned
  bool _obscureLoginPassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.departments != null && widget.departments!.isNotEmpty) {
      _departments = widget.departments!;
      _selectedDepartmentId = _departments.first['department_id'];
    } else {
      _fetchDepartments();
    }

    _recalcDeduction(30);
    _fetchSalaryTemplates();
    _fetchHrCategories();

    // Auto-update deduction on salary change
    _salaryBaseController.addListener(() {
      _recalcDeduction(30);
    });
  }

  Future<void> _fetchHrCategories() async {
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiClient.apiHost}/api/hr/categories?status=ACTIVE'),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _hrCategories = (body['data'] as List?) ?? [];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchSalaryTemplates() async {
    setState(() => _loadingTemplates = true);
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiClient.apiHost}/api/payroll/templates'),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body['data'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _salaryTemplates = list;
            if (list.isNotEmpty && _selectedTemplateId == null) {
              _selectedTemplateId = list.first['template_id'] as int?;
            }
            _loadingTemplates = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingTemplates = false);
  }

  @override
  void dispose() {
    _empCodeController.dispose();
    _biometricCodeController.dispose();
    _officialEmailController.dispose();
    _designationController.dispose();
    _salaryBaseController.dispose();

    _fullNameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _aadharController.dispose();
    _panController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _addressController.dispose();

    _casualLeaveController.dispose();
    _sickLeaveController.dispose();
    _paidLeaveController.dispose();
    _unpaidLimitController.dispose();
    _unpaidDeductionController.dispose();

    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    setState(() => _isLoadingDepartments = true);
    try {
      final res = await ApiClient.get(
          Uri.parse('${ApiClient.apiHost}/api/hr/departments'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['departments'] != null) {
          setState(() {
            _departments = data['departments'];
            if (_departments.isNotEmpty) {
              _selectedDepartmentId = _departments.first['department_id'];
            }
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingDepartments = false);
  }

  void _recalcDeduction(int daysInMonth) {
    final base = double.tryParse(_salaryBaseController.text.trim()) ?? 0.0;
    if (base > 0) {
      final perDay = (base / daysInMonth).toStringAsFixed(2);
      _unpaidDeductionController.text = perDay;
      setState(() {});
    }
  }

  String _formatDateDb(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(
        2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _formatDateDisplay(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d
        .year}";
  }

  int get _totalPaidLeaves {
    final c = int.tryParse(_casualLeaveController.text.trim()) ?? 0;
    final s = int.tryParse(_sickLeaveController.text.trim()) ?? 0;
    final p = int.tryParse(_paidLeaveController.text.trim()) ?? 0;
    return c + s + p;
  }

  Future<void> _submitOnboarding() async {
    // 1. Validate Company Details
    if (_empCodeController.text
        .trim()
        .isEmpty) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please enter an Employee Code in Step 1 (Company Details)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_designationController.text.trim().length < 2 ||
        !RegExp(r'[a-zA-Z]').hasMatch(_designationController.text.trim())) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please enter a valid Designation / Post in Company Details!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final salaryVal = double.tryParse(_salaryBaseController.text.trim());
    if (salaryVal == null || salaryVal <= 0) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please enter a valid Monthly Base Salary (> 0) in Company Details!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedDepartmentId == null) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Department in Company Details!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // 2. Validate Personal Details
    final fullName = _fullNameController.text.trim();
    if (!RegExp(r"^[a-zA-Z][a-zA-Z\s.\-']{1,59}$").hasMatch(fullName)) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Full Name (letters only) in Personal Details!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final phone = _phoneController.text.trim();
    if (!RegExp(r'^\d{10,15}$').hasMatch(phone)) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-15 digit Contact Phone Number!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 3. Validate Login Account (Step 5 - Optional)
    if (_enableLoginAccount) {
      final loginEmail = _loginEmailController.text.trim();
      if (!RegExp(r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$').hasMatch(loginEmail)) {
        setState(() => _activeTabIndex = 4);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please enter a valid Login Email in Step 5 (Login Account)!'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_loginPasswordController.text
          .trim()
          .length < 6) {
        setState(() => _activeTabIndex = 4);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Initial password must be at least 6 characters in Step 5 (Login Account)!'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields accurately!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Determine effective branch_id
      int effBranchId = 1;
      if (_selectedDepartmentId != null && _departments.isNotEmpty) {
        final dept = _departments.firstWhere(
              (d) => d['department_id'] == _selectedDepartmentId,
          orElse: () => null,
        );
        if (dept != null && dept['branch_id'] != null) {
          effBranchId = int.tryParse(dept['branch_id'].toString()) ?? 1;
        }
      }

      final payload = {
        // 1. Company
        'company_id': 1,
        'branch_id': effBranchId,
        'department_id': _selectedDepartmentId,
        'role': _selectedRole,
        'emp_code': _empCodeController.text.trim().toUpperCase(),
        'biometric_emp_code': _biometricCodeController.text
            .trim()
            .isEmpty ? null : _biometricCodeController.text.trim(),
        'designation': _designationController.text.trim(),
        'email': _officialEmailController.text
            .trim()
            .isEmpty ? null : _officialEmailController.text.trim(),
        'employment_type': _selectedEmploymentType,
        'join_date': _formatDateDb(_joinDate),
        'weekly_off': _selectedWeeklyOff,
        'salary_grade': _selectedSalaryGrade,
        'salary_base': double.tryParse(_salaryBaseController.text.trim()) ??
            35000.0,
        'hr_category_id': _selectedHrCategoryId,

        // 2. Personal & Identity
        'full_name': _fullNameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 25,
        'gender': _selectedGender,
        'dob': _formatDateDb(_dob),
        'phone': _phoneController.text
            .trim()
            .isEmpty ? null : _phoneController.text.trim(),
        'emergency_contact': _emergencyContactController.text
            .trim()
            .isEmpty ? null : _emergencyContactController.text.trim(),
        'aadhar_number': _aadharController.text
            .trim()
            .isEmpty ? null : _aadharController.text.trim(),
        'pan_number': _panController.text
            .trim()
            .isEmpty ? null : _panController.text.trim().toUpperCase(),
        'city': _cityController.text
            .trim()
            .isEmpty ? null : _cityController.text.trim(),
        'state': _stateController.text
            .trim()
            .isEmpty ? null : _stateController.text.trim(),
        'address': _addressController.text
            .trim()
            .isEmpty ? null : _addressController.text.trim(),

        // 3. Leaves & Deductions
        'leave_balance_casual': int.tryParse(
            _casualLeaveController.text.trim()) ?? 12,
        'leave_balance_sick': int.tryParse(_sickLeaveController.text.trim()) ??
            8,
        'leave_balance_paid': int.tryParse(_paidLeaveController.text.trim()) ??
            15,
        'unpaid_leave_limit': int.tryParse(
            _unpaidLimitController.text.trim()) ?? 10,
        'unpaid_leave_per_day_deduction': double.tryParse(
            _unpaidDeductionController.text.trim()) ?? 0.0,

        // 4. Optional Login Account (Step 5)
        'create_login': _enableLoginAccount,
        'login_email': _enableLoginAccount
            ? _loginEmailController.text.trim()
            : null,
        'login_password': _enableLoginAccount ? _loginPasswordController.text
            .trim() : null,
        'login_role': _enableLoginAccount ? _selectedRole : null,
        'login_status': _enableLoginAccount ? _selectedLoginStatus : null,
        'manager_module': _selectedRole == 'Module Manager' ? _selectedManagerModule : null,
      };

      final res = await ApiClient.post(
        Uri.parse('${ApiClient.apiHost}/api/hr/employees'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 201 || resData['success'] == true) {
        final newEmpId = resData['employee_id'];
        if (newEmpId != null && _selectedTemplateId != null) {
          try {
            await ApiClient.post(
              Uri.parse('${ApiClient.apiHost}/api/payroll/templates/apply'),
              body: jsonEncode({
                'employee_id': newEmpId,
                'template_id': _selectedTemplateId,
                'gross_monthly': double.tryParse(_salaryBaseController.text.trim()) ?? 35000.0,
                'effective_from': _formatDateDb(_joinDate),
              }),
            );
          } catch (_) {}
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    resData['message'] ??
                        'Employee ${payload['full_name']} onboarded successfully!',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onEmployeeAdded?.call();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resData['message'] ?? 'Failed to onboard employee!'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final isMobile = MediaQuery
        .of(context)
        .size
        .width < 700;
    final headerBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    final Widget mainContent = SafeArea(
      child: Column(
        children: [
          // 1. Top Bar Header
          _buildTopBar(headerBg, textColor, subtextColor, isDark, isMobile),

          // 2. Interactive Navigation Options Bar (4 Steps)
          _buildTopOptionsBar(isDark, isMobile),

          // 3. Tab Content View
          Expanded(
            child: _isLoadingDepartments
                ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 24,
                  vertical: isMobile ? 14 : 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tab Content View (IndexedStack preserves state & allows full validation)
                        IndexedStack(
                          index: _activeTabIndex,
                          children: [
                            _buildEmployeeTabContent(isDark, isMobile),
                            // Step 1: Employee Details
                            _buildCompanyTabContent(isDark, isMobile),
                            // Step 2: Company Details
                            _buildLeavesTabContent(isDark, isMobile),
                            // Step 3: Leaves & Deductions
                            _buildSalaryTemplateTabContent(isDark, isMobile),
                            // Step 4: Salary Template
                            _buildLoginAccountTabContent(isDark, isMobile),
                            // Step 5: Login Account
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Security notice below card (matches mockup)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: isDark ? Colors.white38 : const Color(
                                  0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Data encrypted with 256-bit AES corporate security',
                              style: TextStyle(
                                color: isDark ? Colors.white38 : const Color(
                                    0xFF94A3B8),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),

                        if (!isMobile) ...[
                          const SizedBox(height: 24),
                          // Tab Step Navigation Bottom Row (Desktop only)
                          _buildStepNavigationRow(isDark, isMobile),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. Fixed Sticky Bottom Action Bar on Mobile
          if (isMobile)
            _buildMobileStickyBottomBar(isDark),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: isMobile
          ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))
          : null,
      body: isMobile
          ? mainContent
          : BotanicalBackground(cleanDesktop: MediaQuery.sizeOf(context).width >= 900, 
        showThemeToggle: false,
        child: mainContent,
      ),
    );
  }

  // ================= 1. TOP BAR =================
  Widget _buildTopBar(Color bg, Color textColor, Color subtextColor,
      bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(
                0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
                size: 20),
            tooltip: 'Go Back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Onboard Employee',
                  style: TextStyle(
                    color: textColor,
                    fontSize: isMobile ? 16 : 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Step ${_activeTabIndex + 1} of 5: ${_getTabSubtitle(
                      _activeTabIndex)}',
                  style: TextStyle(
                      color: subtextColor, fontSize: isMobile ? 11.5 : 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Save Draft pill button (matches user prototype)
          InkWell(
            onTap: _isSaving ? null : _submitOnboarding,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                    : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF059669) : const Color(
                      0xFFA7F3D0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSaving)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          color: Color(0xFF047857), strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.check_rounded, size: 14,
                        color: Color(0xFF047857)),
                  const SizedBox(width: 5),
                  Text(
                    _isSaving ? 'Saving...' : 'Save Draft',
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getModuleName(String modKey) {
    switch (modKey) {
      case 'hr':
        return 'HR & Workforce Management';
      case 'projects':
        return 'Projects & Engineering';
      case 'inventory':
        return 'Inventory & Warehouse';
      case 'manufacturing':
        return 'Manufacturing & Production';
      case 'finance':
        return 'Finance & Accounts';
      default:
        return 'HR & Workforce Management';
    }
  }

  Future<void> _showModuleSelectionDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modules = [
      {
        'key': 'hr',
        'title': 'HR & Workforce Management',
        'desc': 'Supervise staff directory, leaves approvals, attendance logs and punch records',
        'icon': Icons.people_alt_outlined,
        'color': const Color(0xFF10B981),
      },
      {
        'key': 'projects',
        'title': 'Projects & Engineering',
        'desc': 'Create & manage projects, assign tasks to workers, kanban workflows & timesheets',
        'icon': Icons.assignment_outlined,
        'color': const Color(0xFF3B82F6),
      },
      {
        'key': 'inventory',
        'title': 'Inventory & Warehouse',
        'desc': 'Track stock levels, monitor material requisitions and inward/outward records',
        'icon': Icons.inventory_2_outlined,
        'color': const Color(0xFFF59E0B),
      },
      {
        'key': 'manufacturing',
        'title': 'Manufacturing & Production',
        'desc': 'Bill of materials (BOM), production work orders, plant scheduling & scrap control',
        'icon': Icons.precision_manufacturing_outlined,
        'color': const Color(0xFF8B5CF6),
      },
      {
        'key': 'finance',
        'title': 'Finance & Accounts',
        'desc': 'Review financial statements, manage appraisals, salary increments & payroll audit logs',
        'icon': Icons.account_balance_wallet_outlined,
        'color': const Color(0xFF06B6D4),
      },
    ];

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.manage_accounts_outlined,
                              color: Color(0xFF10B981),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Operational Module',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Assign this Module Manager strictly to their supervisory domain',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            color: isDark ? Colors.white54 : Colors.black45,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: modules.map((m) {
                              final isSelected = _selectedManagerModule == m['key'];
                              final modColor = m['color'] as Color;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedManagerModule = m['key'] as String;
                                    });
                                    setDialogState(() {});
                                    Navigator.pop(ctx);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? modColor.withValues(alpha: isDark ? 0.2 : 0.08)
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.04)
                                              : const Color(0xFFF8FAFC)),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? modColor
                                            : (isDark ? Colors.white10 : Colors.black12),
                                        width: isSelected ? 1.8 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: modColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            m['icon'] as IconData,
                                            color: modColor,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    m['title'] as String,
                                                    style: TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  if (isSelected) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: modColor,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        'SELECTED',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                m['desc'] as String,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: isDark ? Colors.white60 : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          color: isSelected ? modColor : (isDark ? Colors.white30 : Colors.black26),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            child: const Text('Confirm Module Selection'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getTabSubtitle(int index) {
    switch (index) {
      case 0:
        return 'Personal Identity & Residential';
      case 1:
        return 'Company & Department Credentials';
      case 2:
        return 'Leave Policy & Salary Deductions';
      case 3:
        return 'Salary Template & Structure';
      case 4:
        return 'Portal Credentials & System Role';
      default:
        return '';
    }
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Personal Identity & Residential Details';
      case 1:
        return 'Company & Department Credentials';
      case 2:
        return 'Leave Policy & Salary Deductions';
      case 3:
        return 'Salary Template & Structure';
      case 4:
        return 'ERP Login Account Creation';
      default:
        return '';
    }
  }

  // ================= 2. TOP OPTIONS BAR (4 STEPS) =================
  Widget _buildTopOptionsBar(bool isDark, bool isMobile) {
    final barBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.9)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);

    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: barBg,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildMobileStepItem(0, 'Personal', isDark),
              const SizedBox(width: 8),
              _buildMobileStepItem(1, 'Company', isDark),
              const SizedBox(width: 8),
              _buildMobileStepItem(2, 'Leaves', isDark),
              const SizedBox(width: 8),
              _buildMobileStepItem(3, 'Salary', isDark),
              const SizedBox(width: 8),
              _buildMobileStepItem(4, 'Login', isDark),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Row(
            children: [
              Expanded(
                child: _buildOptionTabItem(
                  index: 0,
                  icon: Icons.person_outline,
                  title: '1. Personal Details',
                  subtitle: 'Name, Age, DOB, Aadhar',
                  accentColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionTabItem(
                  index: 1,
                  icon: Icons.business_outlined,
                  title: '2. Company Details',
                  subtitle: 'Dept, Role, Codes & Post',
                  accentColor: const Color(0xFF3B82F6),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionTabItem(
                  index: 2,
                  icon: Icons.beach_access_outlined,
                  title: '3. Leaves & Deductions',
                  subtitle: 'Paid Quota & Per-Day Cut (₹)',
                  accentColor: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionTabItem(
                  index: 3,
                  icon: Icons.receipt_long_outlined,
                  title: '4. Salary Template',
                  subtitle: 'Future Compensation (Blank)',
                  accentColor: const Color(0xFF8B5CF6),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionTabItem(
                  index: 4,
                  icon: Icons.vpn_key_outlined,
                  title: '5. Login Account',
                  subtitle: 'Credentials & Role (Optional)',
                  accentColor: const Color(0xFF06B6D4),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStepItem(int index, String label, bool isDark) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
              ? const Color(0xFF064E3B).withValues(alpha: 0.35)
              : const Color(0xFFECFDF5))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(
              0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF10B981) : const Color(0xFFA7F3D0))
                : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF059669)
                    : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (isDark ? const Color(0xFF34D399) : const Color(
                    0xFF047857))
                    : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileStickyBottomBar(bool isDark) {
    String nextLabel = 'Next: Company Details';
    if (_activeTabIndex == 1) {
      nextLabel = 'Next: Leaves Details';
    } else if (_activeTabIndex == 2) {
      nextLabel = 'Next: Salary Template';
    } else if (_activeTabIndex == 3) {
      nextLabel = 'Next: Login Account';
    } else if (_activeTabIndex == 4) {
      nextLabel = 'Complete Onboarding';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.95) : Colors
            .white.withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Discard Button (1/3)
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () {
                if (_activeTabIndex > 0) {
                  setState(() => _activeTabIndex--);
                } else {
                  Navigator.pop(context);
                }
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: BorderSide(
                    color: isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: isDark ? Colors.transparent : Colors.white,
              ),
              child: Text(
                _activeTabIndex > 0 ? 'Previous' : 'Discard',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Primary Action Button (2/3)
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                if (_activeTabIndex < 4) {
                  if (_activeTabIndex == 0) {
                    if (_fullNameController.text
                        .trim()
                        .isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter Full Name before proceeding!'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                  } else if (_activeTabIndex == 1) {
                    if (_empCodeController.text
                        .trim()
                        .isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter Employee Code before proceeding!'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                    if (_designationController.text
                        .trim()
                        .isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter Designation before proceeding!'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                  }
                  setState(() => _activeTabIndex++);
                } else {
                  _submitOnboarding();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSaving ? 'Saving...' : nextLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _activeTabIndex == 3 ? Icons.check_circle_outline : Icons
                        .arrow_forward_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTabItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = _activeTabIndex == index;
    final activeBg = isDark ? accentColor.withValues(alpha: 0.18) : accentColor
        .withValues(alpha: 0.1);
    final inactiveBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF8FAFC);
    final textColor = isSelected
        ? accentColor
        : (isDark ? Colors.white70 : const Color(0xFF475569));

    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : (isDark ? Colors.white10 : Colors
                .black12),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : (isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : (isDark
                    ? Colors.white60
                    : Colors.black54),
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight
                          .w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.arrow_drop_down_circle, color: accentColor, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveRow({
    required Widget first,
    required Widget second,
    required bool isMobile,
    int firstFlex = 1,
    int secondFlex = 1,
  }) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          first,
          const SizedBox(height: 16),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: firstFlex, child: first),
        const SizedBox(width: 16),
        Expanded(flex: secondFlex, child: second),
      ],
    );
  }

  // ================= TAB 1: COMPANY DETAILS =================
  Widget _buildCompanyTabContent(bool isDark, bool isMobile) {
    return _buildTabCardContainer(
      title: 'Company & Department Credentials',
      subtitle: 'Configure department, system role, biometric scanner ID, post & base salary',
      icon: Icons.business_outlined,
      accentColor: const Color(0xFF3B82F6),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        // Row 1: Assign Department & System Role
        _buildResponsiveRow(
          isMobile: isMobile,
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Assign Department *', isDark),
              DropdownButtonFormField<int>(
                initialValue: _departments.any((d) =>
                d['department_id'] == _selectedDepartmentId)
                    ? _selectedDepartmentId
                    : (_departments.isNotEmpty ? _departments
                    .first['department_id'] : null),
                decoration: _inputDecoration(
                    'Select Department', Icons.apartment, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: _departments.map((d) {
                  return DropdownMenuItem<int>(
                    value: d['department_id'],
                    child: Text(d['name'] ?? 'Dept ${d['department_id']}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDepartmentId = val);
                },
              ),
              const SizedBox(height: 14),
              _buildLabel('HR Category (Auto-selects Salary Template)', isDark),
              const SizedBox(height: 6),
              DropdownButtonFormField<int?>(
                key: ValueKey('comp_cat_$_selectedHrCategoryId'),
                initialValue: _hrCategories.any((c) => c['category_id'] == _selectedHrCategoryId)
                    ? _selectedHrCategoryId
                    : null,
                decoration: _inputDecoration('Select HR Category', Icons.badge_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None / Custom')),
                  ..._hrCategories.map<DropdownMenuItem<int?>>((c) {
                    return DropdownMenuItem<int?>(
                      value: c['category_id'] as int,
                      child: Text('${c['category_name']} (${c['category_code']})'),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedHrCategoryId = val;
                    if (val != null) {
                      final cat = _hrCategories.cast<dynamic>().firstWhere(
                            (c) => c['category_id'] == val,
                        orElse: () => null,
                      );
                      if (cat != null) {
                        final defTplId = cat['default_template_id'];
                        if (defTplId != null &&
                            _salaryTemplates.any((t) => t['template_id'] == defTplId)) {
                          _selectedTemplateId = defTplId as int;
                        }
                        final defGross = double.tryParse('${cat['default_gross'] ?? ''}');
                        if (defGross != null && defGross > 0) {
                          _salaryBaseController.text = defGross.toStringAsFixed(0);
                        }
                      }
                    }
                  });
                },
              ),

            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('System Role *', isDark),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: _inputDecoration(
                    'Assign Role', Icons.shield_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Employee',
                      child: Text('Employee (Standard Staff)')),
                  DropdownMenuItem(value: 'Module Manager',
                      child: Text('Module Manager (Supervisor)')),
                  DropdownMenuItem(value: 'Super Admin',
                      child: Text('Super Admin (Executive)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedRole = val);
                    if (val == 'Module Manager') {
                      _showModuleSelectionDialog();
                    }
                  }
                },
              ),
              if (_selectedRole == 'Module Manager') ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: _showModuleSelectionDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Supervising: ${_getModuleName(_selectedManagerModule)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Row 2: Employee Code & Biometric Machine ID
        _buildResponsiveRow(
          isMobile: isMobile,
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Employee Code *', isDark),
              TextFormField(
                controller: _empCodeController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                decoration: _inputDecoration(
                    'e.g. EMP-101', Icons.badge_outlined, isDark),
                validator: (v) =>
                (v == null || v
                    .trim()
                    .isEmpty) ? 'Employee Code required' : null,
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Biometric Machine ID (Face Scanner)', isDark),
              TextFormField(
                controller: _biometricCodeController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                decoration: _inputDecoration(
                    'e.g. 1001 (Face Scanner Device ID)', Icons.fingerprint,
                    isDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Row 3: Designation & Official Work Email
        _buildResponsiveRow(
          isMobile: isMobile,
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Designation / Post *', isDark),
              TextFormField(
                controller: _designationController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                decoration: _inputDecoration(
                    'e.g. Production Manager / Senior Operator',
                    Icons.work_outline, isDark),
                validator: (v) {
                  final val = (v ?? '').trim();
                  if (val.isEmpty) return 'Designation required';
                  if (val.length < 2 || !RegExp(r'[a-zA-Z]').hasMatch(val)) {
                    return 'Enter a valid designation';
                  }
                  return null;
                },
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Official Work Email', isDark),
              TextFormField(
                controller: _officialEmailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                decoration: _inputDecoration(
                    'e.g. staff@company.com', Icons.alternate_email, isDark),
                validator: (v) {
                  final val = (v ?? '').trim();
                  if (val.isEmpty) return null;
                  if (!RegExp(r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$').hasMatch(val)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Row 4: Employment Type & Weekly Off
        _buildResponsiveRow(
          isMobile: isMobile,
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Employment Type', isDark),
              DropdownButtonFormField<String>(
                initialValue: _selectedEmploymentType,
                decoration: _inputDecoration(
                    'Type', Icons.assignment_ind_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(
                      value: 'Permanent', child: Text('Permanent (Full Time)')),
                  DropdownMenuItem(
                      value: 'Probation', child: Text('Probation (Trial)')),
                  DropdownMenuItem(
                      value: 'Contractual', child: Text('Contractual')),
                  DropdownMenuItem(
                      value: 'Intern', child: Text('Intern / Trainee')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() =>
                  _selectedEmploymentType = val);
                },
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Weekly Off Day', isDark),
              DropdownButtonFormField<String>(
                initialValue: _selectedWeeklyOff,
                decoration: _inputDecoration(
                    'Off Day', Icons.weekend_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Sunday', child: Text('Sunday')),
                  DropdownMenuItem(value: 'Saturday & Sunday',
                      child: Text('Saturday & Sunday')),
                  DropdownMenuItem(value: 'Monday', child: Text('Monday')),
                  DropdownMenuItem(value: 'Friday', child: Text('Friday')),
                  DropdownMenuItem(
                      value: 'Rotational', child: Text('Rotational')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedWeeklyOff = val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Row 5: Joining Date & Salary Grade
        _buildResponsiveRow(
          isMobile: isMobile,
          first: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Joining Date', isDark),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _joinDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) setState(() => _joinDate = picked);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined,
                          color: Color(0xFF3B82F6), size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _formatDateDisplay(_joinDate),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Salary Grade', isDark),
              DropdownButtonFormField<String>(
                initialValue: _selectedSalaryGrade,
                decoration: _inputDecoration(
                    'Grade', Icons.grade_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Grade A (Executive)',
                      child: Text('Grade A (Executive)')),
                  DropdownMenuItem(value: 'Grade B (Senior Staff)',
                      child: Text('Grade B (Senior Staff)')),
                  DropdownMenuItem(value: 'Grade C (Standard)',
                      child: Text('Grade C (Standard Staff)')),
                  DropdownMenuItem(value: 'Grade D (Junior)',
                      child: Text('Grade D (Junior / Trainee)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedSalaryGrade = val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Row 6: Base Monthly Salary (Full width)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Monthly Base Salary (₹) *', isDark),
            TextFormField(
              controller: _salaryBaseController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
              decoration: _inputDecoration(
                  '35000', Icons.currency_rupee, isDark).copyWith(
                helperText: 'Base salary is automatically linked to daily unpaid leave deduction rate in Tab 3.',
                helperStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black45,
                    fontSize: 11),
              ),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return 'Base Salary is required';
                final numVal = double.tryParse(val);
                if (numVal == null || numVal <= 0) {
                  return 'Enter a valid salary (> 0)';
                }
                return null;
              },
            ),
          ],
        ),
      ],
    );
  }

  // ================= TAB 1: EMPLOYEE DETAILS =================
  Widget _buildEmployeeTabContent(bool isDark, bool isMobile) {
    return _buildTabCardContainer(
      title: 'Employee Personal & Identity Details',
      subtitle: 'Identity verification, age, gender, Aadhar, PAN & permanent address.',
      icon: Icons.badge_outlined,
      accentColor: const Color(0xFF059669),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        // 1. Full Name Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Full Name *', isDark),
            TextFormField(
              controller: _fullNameController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s.\-']")),
              ],
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 13.5),
              decoration: _inputDecoration(
                  'e.g. Ramesh Patel', Icons.person_outline, isDark),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return 'Full Name is required';
                if (!RegExp(r"^[a-zA-Z][a-zA-Z\s.\-']{1,59}$").hasMatch(val)) {
                  return 'Enter a valid name (letters only)';
                }
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. Contact Phone Number Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Contact Phone Number *', isDark),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 13.5),
              decoration: _inputDecoration(
                  'e.g. 9876543210', Icons.phone_outlined, isDark),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return 'Phone number is required';
                if (!RegExp(r'^\d{10,15}$').hasMatch(val)) {
                  return 'Enter valid 10–15 digit phone number';
                }
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 3. 2-Column: Age and Gender
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Age (Years)', isDark),
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13.5),
                    decoration: _inputDecoration(
                        '28', Icons.cake_outlined, isDark),
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isEmpty) return null;
                      final age = int.tryParse(val);
                      if (age == null || age < 16 || age > 80) {
                        return 'Age 16–80';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Gender', isDark),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedGender,
                    decoration: _inputDecoration(
                        'Gender', Icons.wc_outlined, isDark),
                    dropdownColor: isDark ? const Color(0xFF0F172A) : Colors
                        .white,
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13.5),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedGender = val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 4. Date of Birth (DOB) Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Date of Birth (DOB)', isDark),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob,
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    _dob = picked;
                    final diffYears = DateTime
                        .now()
                        .year - picked.year;
                    _ageController.text = diffYears.toString();
                  });
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF8FAFC),
                  border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: isDark ? Colors.white38 : const Color(
                            0xFF94A3B8), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _formatDateDisplay(_dob),
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(
                              0xFF0F172A),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: isDark ? Colors.white38 : const Color(
                            0xFF94A3B8), size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 5. Emergency Contact (Kin) Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Emergency Contact (Kin)', isDark),
            TextFormField(
              controller: _emergencyContactController,
              keyboardType: TextInputType.phone,
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 13.5),
              decoration: _inputDecoration('e.g. 9812345678 (Father / Spouse)',
                  Icons.contact_phone_outlined, isDark),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 6. Aadhar Card Number Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Aadhar Card Number', isDark, tag: '12-DIGIT'),
            TextFormField(
              controller: _aadharController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13.5,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
              decoration: _inputDecoration(
                  '12 Digit Aadhar (e.g. 123456789012)',
                  Icons.credit_card_outlined, isDark),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return null;
                if (!RegExp(r'^\d{12}$').hasMatch(val)) {
                  return 'Aadhar number must be exactly 12 digits';
                }
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 7. PAN Card Number Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel(
                'PAN Card Number', isDark, tag: '10-DIGIT ALPHANUMERIC'),
            TextFormField(
              controller: _panController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(10),
                TextInputFormatter.withFunction(
                  (oldValue, newValue) => newValue.copyWith(
                    text: newValue.text.toUpperCase(),
                  ),
                ),
              ],
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13.5,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
              decoration: _inputDecoration(
                  'e.g. ABCDE1234F', Icons.badge_outlined, isDark),
              validator: (v) {
                final val = (v ?? '').trim().toUpperCase();
                if (val.isEmpty) return null;
                if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(val)) {
                  return 'Enter valid 10-char PAN (e.g. ABCDE1234F)';
                }
                return null;
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 8. 2-Column: City and State
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('City', isDark),
                  TextFormField(
                    controller: _cityController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s.\-']")),
                    ],
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13.5),
                    decoration: _inputDecoration('e.g. Mumbai', null, isDark),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('State', isDark),
                  TextFormField(
                    controller: _stateController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s.\-']")),
                    ],
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13.5),
                    decoration: _inputDecoration(
                        'e.g. Maharashtra', null, isDark),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 9. Full Residential Address Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Full Residential Address', isDark),
            TextFormField(
              controller: _addressController,
              maxLines: 3,
              style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 13.5),
              decoration: _inputDecoration(
                  'Flat No, Building Name, Street Address, Landmark & Pincode...',
                  null, isDark),
            ),
          ],
        ),
      ],
    );
  }

  // ================= TAB 3: LEAVES & DEDUCTIONS =================
  Widget _buildLeavesTabContent(bool isDark, bool isMobile) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final baseSalary = double.tryParse(_salaryBaseController.text.trim()) ??
        0.0;
    final perDayDeduction = double.tryParse(
        _unpaidDeductionController.text.trim()) ?? 0.0;

    return _buildTabCardContainer(
      title: 'Leave Policy & Salary Deduction Rules',
      subtitle: 'Annual paid leave quotas and automated per-day unpaid absence deductions',
      icon: Icons.beach_access_outlined,
      accentColor: const Color(0xFFF59E0B),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        // Helper Announcement Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(
                  Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configure annual paid leave quotas (Casual, Sick, Annual) and per-day salary deduction for unpaid leaves (LWP).',
                  style: TextStyle(color: textColor,
                      fontSize: isMobile ? 11.5 : 12.5,
                      height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Row 1: 3 Paid Leave Categories (Responsive)
        if (isMobile) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Casual Leave (Days)', isDark),
                    TextFormField(
                      controller: _casualLeaveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13),
                      decoration: _inputDecoration(
                          '12', Icons.event_available, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Sick Leave (Days)', isDark),
                    TextFormField(
                      controller: _sickLeaveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13),
                      decoration: _inputDecoration(
                          '8', Icons.healing_outlined, isDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Paid / Annual Leave (Days)', isDark),
              TextFormField(
                controller: _paidLeaveController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                decoration: _inputDecoration('15', Icons.star_border, isDark),
              ),
            ],
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Casual Leave (Days / Year)', isDark),
                    TextFormField(
                      controller: _casualLeaveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13),
                      decoration: _inputDecoration(
                          '12', Icons.event_available, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Sick Leave (Days / Year)', isDark),
                    TextFormField(
                      controller: _sickLeaveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13),
                      decoration: _inputDecoration(
                          '8', Icons.healing_outlined, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Paid / Annual Leave (Days)', isDark),
                    TextFormField(
                      controller: _paidLeaveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13),
                      decoration: _inputDecoration(
                          '15', Icons.star_border, isDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),

        // Total Paid Leaves Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(
                  Icons.verified_outlined, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total Paid Quota: $_totalPaidLeaves Days / Year (Casual + Sick + Annual)',
                  style: const TextStyle(color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Row 2: Maximum Allowed Unpaid Leaves Limit
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel(
                'Maximum Allowed Unpaid Leaves Limit (Days / Year)', isDark),
            TextFormField(
              controller: _unpaidLimitController,
              keyboardType: TextInputType.number,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: _inputDecoration(
                  'e.g. 10 (Allowed Unpaid Leaves limit before action)',
                  Icons.event_busy_outlined, isDark),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Row 3: Unpaid Leave Deduction Per Day (₹) with Calculation Buttons (Responsive)
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Unpaid Leave Deduction Per Day (₹) *', isDark),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickCalcButton(
                        'Auto (Base / 30)', () => _recalcDeduction(30), isDark),
                    const SizedBox(width: 8),
                    _buildQuickCalcButton(
                        'Auto (Base / 26 Days)', () => _recalcDeduction(26),
                        isDark),
                  ],
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel('Unpaid Leave Deduction Per Day (₹) *', isDark),
              Row(
                children: [
                  _buildQuickCalcButton(
                      'Auto (Base / 30)', () => _recalcDeduction(30), isDark),
                  const SizedBox(width: 8),
                  _buildQuickCalcButton('Auto (Base / 26 Working Days)', () =>
                      _recalcDeduction(26), isDark),
                ],
              ),
            ],
          ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _unpaidDeductionController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            color: Color(0xFFEF4444),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          decoration: _inputDecoration('1166.67', Icons.currency_rupee, isDark)
              .copyWith(
            suffixIcon: IconButton(
              icon: const Icon(
                  Icons.calculate_outlined, color: Color(0xFF3B82F6)),
              tooltip: 'Recalculate based on base salary (₹$baseSalary)',
              onPressed: () => _recalcDeduction(30),
            ),
          ),
          validator: (v) =>
          (v == null || v
              .trim()
              .isEmpty) ? 'Deduction amount required' : null,
        ),
        const SizedBox(height: 20),

        // Payroll Live Deduction Preview Card
        Container(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors
                  .black.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                      Icons.receipt_long_outlined, color: Color(0xFF10B981),
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Payroll Deduction Rule Preview',
                    style: TextStyle(color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPreviewRow(
                  'Monthly Base Salary', '₹${baseSalary.toStringAsFixed(2)}',
                  isDark),
              const SizedBox(height: 8),
              _buildPreviewRow('Daily Deduction Rate',
                  '₹${perDayDeduction.toStringAsFixed(2)} / Day', isDark,
                  isDeduction: true),
              const Divider(height: 20),
              Text(
                '• If the employee has 1 unapproved / unpaid leave (LWP), ₹${perDayDeduction
                    .toStringAsFixed(
                    2)} will be deducted from monthly payroll.',
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                    height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                '• Taking 3 unpaid leaves results in a total salary deduction of ₹${(perDayDeduction *
                    3).toStringAsFixed(2)}.',
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                    height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= TAB CARD CONTAINER HELPER =================
  Widget _buildTabCardContainer({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    bool isMobile = false,
    required List<Widget> children,
  }) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner & Header
          Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF059669)
                          : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Icon(icon, color: const Color(0xFF059669), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: isMobile ? 11.5 : 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
          ),
          Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 4: SALARY TEMPLATE =================
  Widget _buildSalaryTemplateTabContent(bool isDark, bool isMobile) {
    final gross = double.tryParse(_salaryBaseController.text.trim()) ?? 35000.0;
    final tpl = _salaryTemplates.cast<dynamic>().firstWhere(
          (t) => t['template_id'] == _selectedTemplateId,
          orElse: () => null,
        );

    double d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0.0;
    final basicPct = d(tpl?['basic_percent'] ?? 50);
    final hraPct = d(tpl?['hra_percent'] ?? 40);
    final convFixed = d(tpl?['conveyance_fixed'] ?? 1600);
    final pfOn = (tpl?['pf_applicable'] ?? 1) == 1;
    final esiOn = (tpl?['esi_applicable'] ?? 1) == 1;
    final ptOn = (tpl?['pt_applicable'] ?? 1) == 1;

    final basic = (gross * basicPct) / 100.0;
    final hra = (basic * hraPct) / 100.0;
    final conv = convFixed.clamp(0.0, (gross - basic - hra).clamp(0.0, gross));
    final special = (gross - basic - hra - conv).clamp(0.0, gross);
    final pfCut = pfOn ? (basic.clamp(0.0, 15000.0) * 0.12) : 0.0;
    final esiCut = (esiOn && gross <= 21000.0) ? (gross * 0.0075) : 0.0;
    final ptCut = ptOn ? (gross > 10000 ? 200.0 : (gross > 7500 ? 175.0 : 0.0)) : 0.0;
    final netPay = (gross - pfCut - esiCut - ptCut).clamp(0.0, gross);

    return _buildTabCardContainer(
      title: 'Salary Template & Structure',
      subtitle: 'Select a company salary template to preview and assign breakup for this employee',
      icon: Icons.receipt_long_outlined,
      accentColor: const Color(0xFF0F766E),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        if (_loadingTemplates)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_salaryTemplates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No salary templates found. Create one in Salary Templates first.'),
          )
        else ...[
          if (_hrCategories.isNotEmpty) ...[
            DropdownButtonFormField<int?>(
              initialValue: _hrCategories.any((c) => c['category_id'] == _selectedHrCategoryId)
                  ? _selectedHrCategoryId
                  : null,
              decoration: InputDecoration(
                labelText: 'HR Category (Auto-selects Salary Template)',
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('-- None / Select Manually --'),
                ),
                ..._hrCategories.map<DropdownMenuItem<int?>>(
                  (c) => DropdownMenuItem<int?>(
                    value: c['category_id'] as int,
                    child: Text('${c['category_name']} (${c['category_code']})'),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedHrCategoryId = val;
                  if (val != null) {
                    final cat = _hrCategories.cast<dynamic>().firstWhere(
                          (c) => c['category_id'] == val,
                          orElse: () => null,
                        );
                    if (cat != null) {
                      final defTplId = cat['default_template_id'];
                      if (defTplId != null &&
                          _salaryTemplates.any((t) => t['template_id'] == defTplId)) {
                        _selectedTemplateId = defTplId as int;
                      }
                      final defGross = cat['default_gross'];
                      if (defGross != null && (double.tryParse('$defGross') ?? 0) > 0) {
                        _salaryBaseController.text = '$defGross';
                      }
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int?>(
            key: ValueKey('onboard_tpl_$_selectedTemplateId'),
            initialValue: _salaryTemplates.any((t) => t['template_id'] == _selectedTemplateId)
                ? _selectedTemplateId
                : null,
            decoration: InputDecoration(
              labelText: 'Select Salary Template',
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _salaryTemplates
                .map<DropdownMenuItem<int?>>(
                  (t) => DropdownMenuItem<int?>(
                    value: t['template_id'] as int,
                    child: Text('${t['template_name']}'),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _selectedTemplateId = val),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFF99F6E4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Breakup Preview (Monthly Gross: ₹${gross.toStringAsFixed(0)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 10),
                _buildTemplateRow('Basic ($basicPct% of Gross)', '₹${basic.toStringAsFixed(2)}', isDark),
                _buildTemplateRow('HRA ($hraPct% of Basic)', '₹${hra.toStringAsFixed(2)}', isDark),
                _buildTemplateRow('Conveyance Allowance', '₹${conv.toStringAsFixed(2)}', isDark),
                _buildTemplateRow('Special Allowance', '₹${special.toStringAsFixed(2)}', isDark),
                const Divider(height: 18),
                _buildTemplateRow('PF Deduction (Employee)', '- ₹${pfCut.toStringAsFixed(2)}', isDark),
                _buildTemplateRow('ESI Deduction (Employee)', '- ₹${esiCut.toStringAsFixed(2)}', isDark),
                _buildTemplateRow('Professional Tax (PT)', '- ₹${ptCut.toStringAsFixed(2)}', isDark),
                const Divider(height: 18),
                _buildTemplateRow('Estimated Net In-Hand', '₹${netPay.toStringAsFixed(2)}', isDark, isBold: true),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTemplateRow(String label, String value, bool isDark, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: isBold ? const Color(0xFF0F766E) : (isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 5: LOGIN ACCOUNT CREATION (OPTIONAL) =================
  Widget _buildLoginAccountTabContent(bool isDark, bool isMobile) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE2E8F0);
    final boxBg = isDark ? Colors.white.withValues(alpha: 0.03) : const Color(
        0xFFF8FAFC);

    return _buildTabCardContainer(
      title: 'ERP Login Account Creation',
      subtitle: 'Setup employee ERP portal access, credentials, assigned role & account status (Optional)',
      icon: Icons.vpn_key_outlined,
      accentColor: const Color(0xFF06B6D4),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        // Master Toggle Card (Allows creating account now or skipping for later)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _enableLoginAccount
                ? (isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                : const Color(0xFFECFDF5))
                : boxBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _enableLoginAccount
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white10 : Colors.black12),
              width: _enableLoginAccount ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _enableLoginAccount
                      ? const Color(0xFF059669)
                      : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.vpn_key_rounded,
                  color: _enableLoginAccount ? Colors.white : (isDark ? Colors
                      .white60 : Colors.black54),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create ERP Login Account for this Employee',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Optional. When enabled, this employee will be able to log in to the ERP portal immediately.',
                      style: TextStyle(color: textSub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enableLoginAccount,
                activeColor: const Color(0xFF059669),
                onChanged: (val) {
                  setState(() {
                    _enableLoginAccount = val;
                    if (val && _loginEmailController.text.isEmpty &&
                        _officialEmailController.text.isNotEmpty) {
                      _loginEmailController.text =
                          _officialEmailController.text.trim();
                    }
                  });
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        if (_enableLoginAccount) ...[
          // Row 1: Login Email / Username & Initial Password
          _buildResponsiveRow(
            isMobile: isMobile,
            first: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Login Email / Username *', isDark),
                TextFormField(
                  controller: _loginEmailController,
                  decoration: _inputDecoration(
                      'e.g. employee@company.com', Icons.email_outlined,
                      isDark),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13),
                  validator: (val) {
                    if (!_enableLoginAccount) return null;
                    final v = (val ?? '').trim();
                    if (v.isEmpty) return 'Login Email/Username is required';
                    if (!RegExp(r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$').hasMatch(v)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
              ],
            ),
            second: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Initial Password *', isDark),
                TextFormField(
                  controller: _loginPasswordController,
                  obscureText: _obscureLoginPassword,
                  decoration: _inputDecoration(
                      'Enter minimum 6 characters', Icons.lock_outline, isDark)
                      .copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureLoginPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() =>
                      _obscureLoginPassword = !_obscureLoginPassword),
                    ),
                  ),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13),
                  validator: (val) {
                    if (!_enableLoginAccount) return null;
                    if (val == null || val
                        .trim()
                        .isEmpty) return 'Initial password is required';
                    if (val
                        .trim()
                        .length < 6)
                      return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Account Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Account Status *', isDark),
              DropdownButtonFormField<String>(
                value: _selectedLoginStatus,
                decoration: _inputDecoration(
                    'Select Status', Icons.toggle_on_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors
                    .white,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Active',
                      child: Text('Active (Can login immediately)')),
                  DropdownMenuItem(value: 'Frozen',
                      child: Text('Frozen (Temporary hold)')),
                  DropdownMenuItem(value: 'Banned',
                      child: Text('Banned (Access blocked)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedLoginStatus = val);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF06B6D4),
                    size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This login account will be automatically linked to this employee profile upon completion.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF0F766E),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
              decoration: BoxDecoration(
                color: boxBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 38,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No ERP Login Account Configured',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Login account creation is optional during onboarding. You can onboard this employee now and create their login account anytime later from their Employee Profile under "System Login & Account Status".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSub, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _enableLoginAccount = true;
                        if (_loginEmailController.text.isEmpty &&
                            _officialEmailController.text.isNotEmpty) {
                          _loginEmailController.text = _officialEmailController
                              .text.trim();
                        }
                      });
                    },
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Enable Login Account Now',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF059669)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  // ================= STEP NAVIGATION BUTTONS (PREV / NEXT / SAVE) =================
  Widget _buildStepNavigationRow(bool isDark, bool isMobile) {
    String prevLabel = 'Previous';
    if (!isMobile) {
      prevLabel = _activeTabIndex == 1
          ? 'Previous: Personal Details'
          : _activeTabIndex == 2
          ? 'Previous: Company Details'
          : _activeTabIndex == 3
          ? 'Previous: Leaves & Deductions'
          : 'Previous: Salary Template';
    }

    String nextLabel = 'Next';
    if (!isMobile) {
      nextLabel = _activeTabIndex == 0
          ? 'Next: Company Details'
          : _activeTabIndex == 1
          ? 'Next: Leaves & Deductions'
          : _activeTabIndex == 2
          ? 'Next: Salary Template'
          : _activeTabIndex == 3
          ? 'Next: Login Account'
          : 'Complete Onboarding';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Action Button
        if (_activeTabIndex > 0)
          OutlinedButton.icon(
            onPressed: () => setState(() => _activeTabIndex--),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 13),
              side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.arrow_back, size: 15),
            label: Text(
              prevLabel,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: isMobile ? 12 : 13),
            ),
          )
        else
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 13),
              side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              isMobile ? 'Discard' : 'Cancel & Discard',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: isMobile ? 12 : 13),
            ),
          ),

        // Right Action Button (5 Steps total: 0, 1, 2, 3, 4)
        if (_activeTabIndex < 4)
          ElevatedButton.icon(
            onPressed: () {
              if (_activeTabIndex == 0) {
                // Step 0 is Personal Details -> Validate Full Name
                if (_fullNameController.text
                    .trim()
                    .isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(
                        'Please enter Full Name before proceeding!'),
                        backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
              } else if (_activeTabIndex == 1) {
                // Step 1 is Company Details -> Validate Emp Code & Designation
                if (_empCodeController.text
                    .trim()
                    .isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(
                        'Please enter Employee Code before proceeding!'),
                        backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
                if (_designationController.text
                    .trim()
                    .isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(
                        'Please enter Designation before proceeding!'),
                        backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
              }
              setState(() => _activeTabIndex++);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24, vertical: isMobile ? 10 : 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            icon: const Icon(Icons.arrow_forward, size: 15),
            label: Text(
              nextLabel,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _submitOnboarding,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 28, vertical: isMobile ? 10 : 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 3,
            ),
            icon: _isSaving
                ? const SizedBox(width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle, size: 16),
            label: Text(
              _isSaving ? 'Saving...' : (isMobile
                  ? 'Complete'
                  : 'Save & Complete Onboarding'),
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: isMobile ? 12.5 : 14),
            ),
          ),
      ],
    );
  }


  Widget _buildQuickCalcButton(String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF3B82F6),
              fontSize: 11,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String title, String value, bool isDark,
      {bool isDeduction = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54, fontSize: 12.5)),
        Text(
          value,
          style: TextStyle(
            color: isDeduction ? const Color(0xFFEF4444) : (isDark ? Colors
                .white : Colors.black87),
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, bool isDark, {String? tag}) {
    final bool hasAsterisk = text.contains('*');
    final String cleanText = text.replaceAll('*', '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: TextSpan(
              text: cleanText,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              children: [
                if (hasAsterisk)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Color(0xFFF43F5E), // rose-500
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          if (tag != null)
            Text(
              tag,
              style: TextStyle(
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData? icon, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
        fontSize: 13,
      ),
      prefixIcon: icon != null
          ? Icon(
        icon,
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
        size: 18,
      )
          : null,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(
          0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF059669),
          width: 1.5,
        ),
      ),
    );
  }
}
