import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';

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

    // Auto-update deduction on salary change
    _salaryBaseController.addListener(() {
      _recalcDeduction(30);
    });
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
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    setState(() => _isLoadingDepartments = true);
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
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
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _formatDateDisplay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}";
  }

  int get _totalPaidLeaves {
    final c = int.tryParse(_casualLeaveController.text.trim()) ?? 0;
    final s = int.tryParse(_sickLeaveController.text.trim()) ?? 0;
    final p = int.tryParse(_paidLeaveController.text.trim()) ?? 0;
    return c + s + p;
  }

  Future<void> _submitOnboarding() async {
    // 1. Validate Company Details
    if (_empCodeController.text.trim().isEmpty) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an Employee Code in Step 1 (Company Details)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_designationController.text.trim().isEmpty) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Designation / Post in Step 1 (Company Details)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedDepartmentId == null) {
      setState(() => _activeTabIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Department in Step 1!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // 2. Validate Personal Details
    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _activeTabIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Full Name in Step 2 (Employee Details)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
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
        'biometric_emp_code': _biometricCodeController.text.trim().isEmpty ? null : _biometricCodeController.text.trim(),
        'designation': _designationController.text.trim(),
        'email': _officialEmailController.text.trim().isEmpty ? null : _officialEmailController.text.trim(),
        'employment_type': _selectedEmploymentType,
        'join_date': _formatDateDb(_joinDate),
        'weekly_off': _selectedWeeklyOff,
        'salary_grade': _selectedSalaryGrade,
        'salary_base': double.tryParse(_salaryBaseController.text.trim()) ?? 35000.0,

        // 2. Personal & Identity
        'full_name': _fullNameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 25,
        'gender': _selectedGender,
        'dob': _formatDateDb(_dob),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'emergency_contact': _emergencyContactController.text.trim().isEmpty ? null : _emergencyContactController.text.trim(),
        'aadhar_number': _aadharController.text.trim().isEmpty ? null : _aadharController.text.trim(),
        'pan_number': _panController.text.trim().isEmpty ? null : _panController.text.trim().toUpperCase(),
        'city': _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),

        // 3. Leaves & Deductions
        'leave_balance_casual': int.tryParse(_casualLeaveController.text.trim()) ?? 12,
        'leave_balance_sick': int.tryParse(_sickLeaveController.text.trim()) ?? 8,
        'leave_balance_paid': int.tryParse(_paidLeaveController.text.trim()) ?? 15,
        'unpaid_leave_limit': int.tryParse(_unpaidLimitController.text.trim()) ?? 10,
        'unpaid_leave_per_day_deduction': double.tryParse(_unpaidDeductionController.text.trim()) ?? 0.0,
      };

      final res = await http.post(
        Uri.parse('http://localhost:5000/api/hr/employees'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 201 || resData['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Employee ${payload['full_name']} onboarded successfully!'),
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
    final isMobile = MediaQuery.of(context).size.width < 700;
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : Form(
                    key: _formKey,
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
                                  _buildEmployeeTabContent(isDark, isMobile),       // Step 1: Employee Details
                                  _buildCompanyTabContent(isDark, isMobile),        // Step 2: Company Details
                                  _buildLeavesTabContent(isDark, isMobile),         // Step 3: Leaves & Deductions
                                  _buildSalaryTemplateTabContent(isDark, isMobile), // Step 4: Salary Template
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
                                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Data encrypted with 256-bit AES corporate security',
                                    style: TextStyle(
                                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
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
          : BotanicalBackground(
              showThemeToggle: false,
              child: mainContent,
            ),
    );
  }

  // ================= 1. TOP BAR =================
  Widget _buildTopBar(Color bg, Color textColor, Color subtextColor, bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : const Color(0xFF334155), size: 20),
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
                  'Step ${_activeTabIndex + 1} of 4: ${_getTabSubtitle(_activeTabIndex)}',
                  style: TextStyle(color: subtextColor, fontSize: isMobile ? 11.5 : 12),
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
                  color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSaving)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(color: Color(0xFF047857), strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.check_rounded, size: 14, color: Color(0xFF047857)),
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
      default:
        return '';
    }
  }

  // ================= 2. TOP OPTIONS BAR (4 STEPS) =================
  Widget _buildTopOptionsBar(bool isDark, bool isMobile) {
    final barBg = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.9) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

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
          constraints: const BoxConstraints(maxWidth: 960),
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
              const SizedBox(width: 10),
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
              const SizedBox(width: 10),
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
              const SizedBox(width: 10),
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
              ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
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
                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
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
      nextLabel = 'Complete Onboarding';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.98),
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
                side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                if (_activeTabIndex < 3) {
                  if (_activeTabIndex == 0) {
                    if (_fullNameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter Full Name before proceeding!'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                  } else if (_activeTabIndex == 1) {
                    if (_empCodeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter Employee Code before proceeding!'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                    if (_designationController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter Designation before proceeding!'),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSaving ? 'Saving...' : nextLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _activeTabIndex == 3 ? Icons.check_circle_outline : Icons.arrow_forward_rounded,
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
    final activeBg = isDark ? accentColor.withValues(alpha: 0.18) : accentColor.withValues(alpha: 0.1);
    final inactiveBg = isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC);
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
            color: isSelected ? accentColor : (isDark ? Colors.white10 : Colors.black12),
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
                color: isSelected ? accentColor : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
                initialValue: _departments.any((d) => d['department_id'] == _selectedDepartmentId)
                    ? _selectedDepartmentId
                    : (_departments.isNotEmpty ? _departments.first['department_id'] : null),
                decoration: _inputDecoration('Select Department', Icons.apartment, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
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
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('System Role *', isDark),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: _inputDecoration('Assign Role', Icons.shield_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Employee', child: Text('Employee (Standard Staff)')),
                  DropdownMenuItem(value: 'Module Manager', child: Text('Module Manager (Supervisor)')),
                  DropdownMenuItem(value: 'Super Admin', child: Text('Super Admin (Executive)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRole = val);
                },
              ),
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: _inputDecoration('e.g. EMP-101', Icons.badge_outlined, isDark),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Employee Code required' : null,
              ),
            ],
          ),
          second: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('Biometric Machine ID (Face Scanner)', isDark),
              TextFormField(
                controller: _biometricCodeController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: _inputDecoration('e.g. 1001 (Face Scanner Device ID)', Icons.fingerprint, isDark),
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: _inputDecoration('e.g. Production Manager / Senior Operator', Icons.work_outline, isDark),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Designation required' : null,
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: _inputDecoration('e.g. staff@company.com', Icons.alternate_email, isDark),
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
                decoration: _inputDecoration('Type', Icons.assignment_ind_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Permanent', child: Text('Permanent (Full Time)')),
                  DropdownMenuItem(value: 'Probation', child: Text('Probation (Trial)')),
                  DropdownMenuItem(value: 'Contractual', child: Text('Contractual')),
                  DropdownMenuItem(value: 'Intern', child: Text('Intern / Trainee')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedEmploymentType = val);
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
                decoration: _inputDecoration('Off Day', Icons.weekend_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Sunday', child: Text('Sunday')),
                  DropdownMenuItem(value: 'Saturday & Sunday', child: Text('Saturday & Sunday')),
                  DropdownMenuItem(value: 'Monday', child: Text('Monday')),
                  DropdownMenuItem(value: 'Friday', child: Text('Friday')),
                  DropdownMenuItem(value: 'Rotational', child: Text('Rotational')),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, color: Color(0xFF3B82F6), size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _formatDateDisplay(_joinDate),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
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
                decoration: _inputDecoration('Grade', Icons.grade_outlined, isDark),
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'Grade A (Executive)', child: Text('Grade A (Executive)')),
                  DropdownMenuItem(value: 'Grade B (Senior Staff)', child: Text('Grade B (Senior Staff)')),
                  DropdownMenuItem(value: 'Grade C (Standard)', child: Text('Grade C (Standard Staff)')),
                  DropdownMenuItem(value: 'Grade D (Junior)', child: Text('Grade D (Junior / Trainee)')),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontWeight: FontWeight.bold),
              decoration: _inputDecoration('35000', Icons.currency_rupee, isDark).copyWith(
                helperText: 'Base salary is automatically linked to daily unpaid leave deduction rate in Tab 3.',
                helperStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 11),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Base Salary is required' : null,
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
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
              decoration: _inputDecoration('e.g. Ramesh Patel', Icons.person_outline, isDark),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Full Name is required' : null,
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
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
              decoration: _inputDecoration('e.g. 9876543210', Icons.phone_outlined, isDark),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
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
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                    decoration: _inputDecoration('28', Icons.cake_outlined, isDark),
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
                    decoration: _inputDecoration('Gender', Icons.wc_outlined, isDark),
                    dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
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
                    final diffYears = DateTime.now().year - picked.year;
                    _ageController.text = diffYears.toString();
                  });
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                  border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, color: isDark ? Colors.white38 : const Color(0xFF94A3B8), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _formatDateDisplay(_dob),
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, color: isDark ? Colors.white38 : const Color(0xFF94A3B8), size: 20),
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
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
              decoration: _inputDecoration('e.g. 9812345678 (Father / Spouse)', Icons.contact_phone_outlined, isDark),
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
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13.5,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
              decoration: _inputDecoration('12 Digit Aadhar (e.g. 1234 5678 9012)', Icons.credit_card_outlined, isDark),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 7. PAN Card Number Field
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('PAN Card Number', isDark, tag: '10-DIGIT ALPHANUMERIC'),
            TextFormField(
              controller: _panController,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 13.5,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
              decoration: _inputDecoration('e.g. ABCDE1234F', Icons.badge_outlined, isDark),
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
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
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
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                    decoration: _inputDecoration('e.g. Maharashtra', null, isDark),
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
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
              decoration: _inputDecoration('Flat No, Building Name, Street Address, Landmark & Pincode...', null, isDark),
            ),
          ],
        ),
      ],
    );
  }

  // ================= TAB 3: LEAVES & DEDUCTIONS =================
  Widget _buildLeavesTabContent(bool isDark, bool isMobile) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final baseSalary = double.tryParse(_salaryBaseController.text.trim()) ?? 0.0;
    final perDayDeduction = double.tryParse(_unpaidDeductionController.text.trim()) ?? 0.0;

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
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Configure annual paid leave quotas (Casual, Sick, Annual) and per-day salary deduction for unpaid leaves (LWP).',
                  style: TextStyle(color: textColor, fontSize: isMobile ? 11.5 : 12.5, height: 1.3),
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: _inputDecoration('12', Icons.event_available, isDark),
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: _inputDecoration('8', Icons.healing_outlined, isDark),
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: _inputDecoration('12', Icons.event_available, isDark),
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: _inputDecoration('8', Icons.healing_outlined, isDark),
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                      decoration: _inputDecoration('15', Icons.star_border, isDark),
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
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total Paid Quota: $_totalPaidLeaves Days / Year (Casual + Sick + Annual)',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12.5),
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
            _buildLabel('Maximum Allowed Unpaid Leaves Limit (Days / Year)', isDark),
            TextFormField(
              controller: _unpaidLimitController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: _inputDecoration('e.g. 10 (Allowed Unpaid Leaves limit before action)', Icons.event_busy_outlined, isDark),
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
                    _buildQuickCalcButton('Auto (Base / 30)', () => _recalcDeduction(30), isDark),
                    const SizedBox(width: 8),
                    _buildQuickCalcButton('Auto (Base / 26 Days)', () => _recalcDeduction(26), isDark),
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
                  _buildQuickCalcButton('Auto (Base / 30)', () => _recalcDeduction(30), isDark),
                  const SizedBox(width: 8),
                  _buildQuickCalcButton('Auto (Base / 26 Working Days)', () => _recalcDeduction(26), isDark),
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
          decoration: _inputDecoration('1166.67', Icons.currency_rupee, isDark).copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calculate_outlined, color: Color(0xFF3B82F6)),
              tooltip: 'Recalculate based on base salary (₹$baseSalary)',
              onPressed: () => _recalcDeduction(30),
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Deduction amount required' : null,
        ),
        const SizedBox(height: 20),

        // Payroll Live Deduction Preview Card
        Container(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Payroll Deduction Rule Preview',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPreviewRow('Monthly Base Salary', '₹${baseSalary.toStringAsFixed(2)}', isDark),
              const SizedBox(height: 8),
              _buildPreviewRow('Daily Deduction Rate', '₹${perDayDeduction.toStringAsFixed(2)} / Day', isDark, isDeduction: true),
              const Divider(height: 20),
              Text(
                '• If the employee has 1 unapproved / unpaid leave (LWP), ₹${perDayDeduction.toStringAsFixed(2)} will be deducted from monthly payroll.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                '• Taking 3 unpaid leaves results in a total salary deduction of ₹${(perDayDeduction * 3).toStringAsFixed(2)}.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, height: 1.4),
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
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
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

  // ================= TAB 4: SALARY TEMPLATE (COMING SOON) =================
  Widget _buildSalaryTemplateTabContent(bool isDark, bool isMobile) {
    return _buildTabCardContainer(
      title: 'Salary Template & Structure',
      subtitle: 'Configurable compensation template, allowances & bonus breakdown (Coming Soon)',
      icon: Icons.receipt_long_outlined,
      accentColor: const Color(0xFF8B5CF6),
      isDark: isDark,
      isMobile: isMobile,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: isMobile ? 24 : 40, horizontal: isMobile ? 14 : 20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12, style: BorderStyle.solid),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.account_balance_wallet_outlined, size: isMobile ? 28 : 36, color: const Color(0xFF8B5CF6)),
              ),
              const SizedBox(height: 12),
              Text(
                'Salary Template Configuration',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: isMobile ? 14 : 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Custom allowances (HRA, DA, Medical), PF deductions and gross CTC templates will be added here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white60 : const Color(0xFF64748B), fontSize: isMobile ? 11 : 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= STEP NAVIGATION BUTTONS (PREV / NEXT / SAVE) =================
  Widget _buildStepNavigationRow(bool isDark, bool isMobile) {
    String prevLabel = 'Previous';
    if (!isMobile) {
      prevLabel = _activeTabIndex == 1
          ? 'Previous: Employee Details'
          : _activeTabIndex == 2
              ? 'Previous: Company Details'
              : 'Previous: Leaves & Deductions';
    }

    String nextLabel = 'Next';
    if (!isMobile) {
      nextLabel = _activeTabIndex == 0
          ? 'Next: Company Details'
          : _activeTabIndex == 1
              ? 'Next: Leaves & Deductions'
              : 'Next: Salary Template';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left Action Button
        if (_activeTabIndex > 0)
          OutlinedButton.icon(
            onPressed: () => setState(() => _activeTabIndex--),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 13),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.arrow_back, size: 15),
            label: Text(
              prevLabel,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: isMobile ? 12 : 13),
            ),
          )
        else
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 13),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              isMobile ? 'Discard' : 'Cancel & Discard',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: isMobile ? 12 : 13),
            ),
          ),

        // Right Action Button (4 Steps total: 0, 1, 2, 3)
        if (_activeTabIndex < 3)
          ElevatedButton.icon(
            onPressed: () {
              if (_activeTabIndex == 0) {
                // Step 0 is now Employee Details -> Validate Full Name
                if (_fullNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter Full Name before proceeding!'), backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
              } else if (_activeTabIndex == 1) {
                // Step 1 is now Company Details -> Validate Emp Code & Designation
                if (_empCodeController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter Employee Code before proceeding!'), backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
                if (_designationController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter Designation before proceeding!'), backgroundColor: Colors.orangeAccent),
                  );
                  return;
                }
              }
              setState(() => _activeTabIndex++);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 10 : 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            icon: const Icon(Icons.arrow_forward, size: 15),
            label: Text(
              nextLabel,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _submitOnboarding,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28, vertical: isMobile ? 10 : 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 3,
            ),
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle, size: 16),
            label: Text(
              _isSaving ? 'Saving...' : (isMobile ? 'Complete' : 'Save & Complete Onboarding'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12.5 : 14),
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
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String title, String value, bool isDark, {bool isDeduction = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12.5)),
        Text(
          value,
          style: TextStyle(
            color: isDeduction ? const Color(0xFFEF4444) : (isDark ? Colors.white : Colors.black87),
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
      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
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
