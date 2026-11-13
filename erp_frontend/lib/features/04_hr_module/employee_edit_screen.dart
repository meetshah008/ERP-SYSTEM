import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';

class EmployeeEditScreen extends StatefulWidget {
  final dynamic employeeId;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onEmployeeUpdated;

  const EmployeeEditScreen({
    super.key,
    required this.employeeId,
    this.initialData,
    this.onEmployeeUpdated,
  });

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _departments = [];

  // Active Tab Index: 0 = Employee Details, 1 = Company Details, 2 = Leaves & Deductions, 3 = Salary Preview
  int _activeTabIndex = 0;

  // ================= 1. EMPLOYEE DETAILS (PERSONAL & KYC) =================
  String _selectedGender = 'Male';
  DateTime? _dob;
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _aadharController = TextEditingController();
  final _panController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _addressController = TextEditingController();

  // ================= 2. COMPANY DETAILS =================
  int? _selectedDepartmentId;
  String _selectedRole = 'Employee';
  String _selectedEmploymentType = 'Permanent';
  String _selectedWeeklyOff = 'Sunday';
  String _selectedStatus = 'active';
  String _selectedSalaryGrade = 'Grade B';
  DateTime? _joinDate;

  final _empCodeController = TextEditingController();
  final _biometricCodeController = TextEditingController();
  final _officialEmailController = TextEditingController();
  final _designationController = TextEditingController();
  final _salaryBaseController = TextEditingController();

  // ================= 3. LEAVES POLICY & SALARY DEDUCTIONS =================
  final _casualLeaveController = TextEditingController();
  final _sickLeaveController = TextEditingController();
  final _paidLeaveController = TextEditingController();
  final _unpaidLimitController = TextEditingController();
  final _unpaidDeductionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _fetchDepartments();
    if (widget.initialData != null && widget.initialData!['employee'] != null) {
      _populateFromMap(widget.initialData!['employee']);
      setState(() => _isLoading = false);
    } else {
      await _fetchFullProfile();
    }
  }

  void _populateFromMap(Map<String, dynamic> emp) {
    _fullNameController.text = emp['full_name']?.toString() ?? '';
    _ageController.text = emp['age']?.toString() ?? '';
    _selectedGender = (emp['gender'] ?? 'Male').toString();
    if (_selectedGender != 'Male' &&
        _selectedGender != 'Female' &&
        _selectedGender != 'Other') {
      _selectedGender = 'Male';
    }

    if (emp['dob'] != null) {
      _dob = DateTime.tryParse(emp['dob'].toString());
    }
    _phoneController.text = emp['phone']?.toString() ?? '';
    _emergencyContactController.text =
        emp['emergency_contact']?.toString() ?? '';
    _aadharController.text = emp['aadhar_number']?.toString() ?? '';
    _panController.text = emp['pan_number']?.toString() ?? '';
    _addressController.text = emp['address']?.toString() ?? '';
    _cityController.text = emp['city']?.toString() ?? '';
    _stateController.text = emp['state']?.toString() ?? '';

    // Company & Contract
    _empCodeController.text = emp['emp_code']?.toString() ?? '';
    _biometricCodeController.text =
        emp['biometric_emp_code']?.toString() ?? '';
    _officialEmailController.text =
        emp['email']?.toString() ?? emp['user_email']?.toString() ?? '';
    _designationController.text = emp['designation']?.toString() ?? 'Staff';
    _selectedRole = emp['role_name']?.toString() ??
        emp['role']?.toString() ??
        'Employee';
    _selectedEmploymentType =
        emp['employment_type']?.toString() ?? 'Permanent';
    _selectedWeeklyOff = emp['weekly_off']?.toString() ?? 'Sunday';
    _selectedStatus = (emp['status'] ?? 'active').toString().toLowerCase();
    _selectedSalaryGrade = emp['salary_grade']?.toString() ?? 'Grade B';
    _selectedDepartmentId = emp['department_id'] != null
        ? int.tryParse(emp['department_id'].toString())
        : null;

    if (emp['join_date'] != null) {
      _joinDate = DateTime.tryParse(emp['join_date'].toString());
    }

    _salaryBaseController.text = emp['salary_base']?.toString() ?? '35000';

    // Leaves
    _casualLeaveController.text =
        (emp['leave_balance_casual'] ?? 12).toString();
    _sickLeaveController.text = (emp['leave_balance_sick'] ?? 8).toString();
    _paidLeaveController.text = (emp['leave_balance_paid'] ?? 15).toString();
    _unpaidLimitController.text = (emp['unpaid_leave_limit'] ?? 10).toString();

    final customDeduction =
    double.tryParse(emp['unpaid_leave_per_day_deduction']?.toString() ?? '');
    final base = double.tryParse(_salaryBaseController.text) ?? 35000.0;
    if (customDeduction != null && customDeduction > 0) {
      _unpaidDeductionController.text = customDeduction.toStringAsFixed(2);
    } else {
      _unpaidDeductionController.text = (base / 30.0).toStringAsFixed(2);
    }

    _salaryBaseController.addListener(_onSalaryChanged);
  }

  void _onSalaryChanged() {
    final base = double.tryParse(_salaryBaseController.text.trim()) ?? 0.0;
    if (base > 0) {
      _unpaidDeductionController.text = (base / 30.0).toStringAsFixed(2);
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await http
          .get(Uri.parse('http://localhost:5000/api/hr/departments'));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        _departments = json['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  Future<void> _fetchFullProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse(
          'http://localhost:5000/api/hr/employees/${widget.employeeId}/full-profile',
        ),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          final emp = json['data']?['employee'] ?? {};
          _populateFromMap(emp);
        }
      }
    } catch (e) {
      debugPrint('Error fetching full profile: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _salaryBaseController.removeListener(_onSalaryChanged);
    _fullNameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _aadharController.dispose();
    _panController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _addressController.dispose();
    _empCodeController.dispose();
    _biometricCodeController.dispose();
    _officialEmailController.dispose();
    _designationController.dispose();
    _salaryBaseController.dispose();
    _casualLeaveController.dispose();
    _sickLeaveController.dispose();
    _paidLeaveController.dispose();
    _unpaidLimitController.dispose();
    _unpaidDeductionController.dispose();
    super.dispose();
  }

  Future<void> _saveProfileChanges() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please correct validation errors before saving.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'full_name': _fullNameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()),
        'gender': _selectedGender,
        'dob': _dob != null ? _dob!.toIso8601String().split('T')[0] : null,
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'emergency_contact': _emergencyContactController.text.trim().isEmpty
            ? null
            : _emergencyContactController.text.trim(),
        'aadhar_number': _aadharController.text.trim().isEmpty
            ? null
            : _aadharController.text.trim(),
        'pan_number': _panController.text.trim().isEmpty
            ? null
            : _panController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),

        // 2. Company Details
        'department_id': _selectedDepartmentId,
        'designation': _designationController.text.trim(),
        'employment_type': _selectedEmploymentType,
        'weekly_off': _selectedWeeklyOff,
        'status': _selectedStatus,
        'biometric_emp_code': _biometricCodeController.text.trim().isEmpty
            ? null
            : _biometricCodeController.text.trim(),
        'email': _officialEmailController.text.trim().isEmpty
            ? null
            : _officialEmailController.text.trim(),
        'join_date': _joinDate != null
            ? _joinDate!.toIso8601String().split('T')[0]
            : null,
        'salary_grade': _selectedSalaryGrade,
        'salary_base': double.tryParse(_salaryBaseController.text.trim()) ?? 35000.0,

        // 3. Leaves & Deductions
        'leave_balance_casual':
        int.tryParse(_casualLeaveController.text.trim()) ?? 12,
        'leave_balance_sick':
        int.tryParse(_sickLeaveController.text.trim()) ?? 8,
        'leave_balance_paid':
        int.tryParse(_paidLeaveController.text.trim()) ?? 15,
        'unpaid_leave_limit':
        int.tryParse(_unpaidLimitController.text.trim()) ?? 10,
        'unpaid_leave_per_day_deduction':
        double.tryParse(_unpaidDeductionController.text.trim()),
      };

      final res = await http.put(
        Uri.parse(
          'http://localhost:5000/api/hr/employees/${widget.employeeId}/lifecycle',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 || resData['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  resData['message'] ?? 'Employee profile updated successfully!',
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onEmployeeUpdated?.call();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resData['message'] ?? 'Failed to update employee.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final isMobile = MediaQuery.of(context).size.width < 700;
    final cardBg = isDark
        ? const Color(0xFF0F172A).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.95);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E8F0);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: _isLoading
              ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF059669)),
          )
              : Form(
            key: _formKey,
            child: Column(
              children: [
                _buildHeader(textTitle, textSub, borderColor, isDark, isMobile),
                _buildTabsRow(isDark, borderColor, textTitle, textSub, isMobile),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 24,
                      vertical: isMobile ? 12 : 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: _buildActiveTabContent(
                          isDark,
                          cardBg,
                          borderColor,
                          textTitle,
                          textSub,
                          isMobile,
                        ),
                      ),
                    ),
                  ),
                ),
                _buildBottomBar(isDark, borderColor, isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. TOP HEADER
  Widget _buildHeader(
      Color textTitle,
      Color textSub,
      Color borderColor,
      bool isDark,
      bool isMobile,
      ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: textTitle,
            tooltip: 'Back to Details',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: Color(0xFF059669),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMobile ? 'Edit Employee' : 'Edit Employee Lifecycle & Profile',
                  style: TextStyle(
                    color: textTitle,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isMobile
                      ? 'Step ${_activeTabIndex + 1} of 4: ${_getEditTabTitle(_activeTabIndex)}'
                      : 'Update Personal Demographics, Contract, Leaves & Compensation Quotas',
                  style: TextStyle(color: textSub, fontSize: isMobile ? 11 : 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: textSub,
                side: BorderSide(color: borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 20,
                vertical: isMobile ? 8 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 1,
            ),
            icon: _isSaving
                ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.check_circle_rounded, size: 16),
            label: Text(
              _isSaving
                  ? 'Saving...'
                  : (isMobile ? 'Save' : 'Save Profile Changes'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
            ),
            onPressed: _isSaving ? null : _saveProfileChanges,
          ),
        ],
      ),
    );
  }

  String _getEditTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Personal & KYC';
      case 1:
        return 'Company & Post';
      case 2:
        return 'Leaves & Quota';
      case 3:
      default:
        return 'Salary Structure';
    }
  }

  // 2. STEP TABS ROW
  Widget _buildTabsRow(
    bool isDark,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.grey.withValues(alpha: 0.04),
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildMobileTabChip(0, Icons.person_outline_rounded, '1. Details', isDark),
              const SizedBox(width: 8),
              _buildMobileTabChip(1, Icons.apartment_rounded, '2. Company', isDark),
              const SizedBox(width: 8),
              _buildMobileTabChip(2, Icons.beach_access_outlined, '3. Leaves', isDark),
              const SizedBox(width: 8),
              _buildMobileTabChip(3, Icons.receipt_long_outlined, '4. Salary', isDark),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.grey.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTabPill(
                index: 0,
                title: '1. Employee Details',
                subtitle: 'Personal Demographics, KYC, Address',
                icon: Icons.person_outline_rounded,
                isDark: isDark,
                borderColor: borderColor,
              ),
              const SizedBox(width: 12),
              _buildTabPill(
                index: 1,
                title: '2. Company Details',
                subtitle: 'Department, Role, Post & Salary',
                icon: Icons.apartment_rounded,
                isDark: isDark,
                borderColor: borderColor,
              ),
              const SizedBox(width: 12),
              _buildTabPill(
                index: 2,
                title: '3. Leaves & Deductions',
                subtitle: 'Paid Quota & Per-Day Cut (₹)',
                icon: Icons.beach_access_outlined,
                isDark: isDark,
                borderColor: borderColor,
              ),
              const SizedBox(width: 12),
              _buildTabPill(
                index: 3,
                title: '4. Salary Template',
                subtitle: 'Compensation Structure Preview',
                icon: Icons.receipt_long_outlined,
                isDark: isDark,
                borderColor: borderColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileTabChip(int index, IconData icon, String label, bool isDark) {
    final isActive = _activeTabIndex == index;
    const primaryColor = Color(0xFF059669);

    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? primaryColor
              : (isDark ? Colors.white10 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? primaryColor : (isDark ? Colors.white24 : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
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
        children: [
          first,
          const SizedBox(height: 14),
          second,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: firstFlex, child: first),
        const SizedBox(width: 14),
        Expanded(flex: secondFlex, child: second),
      ],
    );
  }

  Widget _buildTabPill({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Color borderColor,
  }) {
    final isActive = _activeTabIndex == index;
    final primaryColor = const Color(0xFF059669);

    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? primaryColor.withValues(alpha: isDark ? 0.2 : 0.1)
              : (isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? primaryColor : borderColor,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isActive
                    ? primaryColor
                    : (isDark ? Colors.white10 : Colors.grey.shade200),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 15,
                color: isActive
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: isActive
                        ? (isDark ? const Color(0xFF34D399) : primaryColor)
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 3. ACTIVE TAB CONTENT
  Widget _buildActiveTabContent(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    switch (_activeTabIndex) {
      case 0:
        return _buildTab1Personal(isDark, cardBg, borderColor, textTitle, textSub, isMobile);
      case 1:
        return _buildTab2Company(isDark, cardBg, borderColor, textTitle, textSub, isMobile);
      case 2:
        return _buildTab3Leaves(isDark, cardBg, borderColor, textTitle, textSub, isMobile);
      case 3:
      default:
        return _buildTab4SalaryPreview(isDark, cardBg, borderColor, textTitle, textSub, isMobile);
    }
  }

  // TAB 1: PERSONAL & RESIDENTIAL
  Widget _buildTab1Personal(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    return Column(
      children: [
        _buildSectionCard(
          title: 'Personal Demographics & KYC',
          icon: Icons.person_pin_outlined,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            if (isMobile) ...[
              _buildTextField(
                label: 'Full Legal Name',
                controller: _fullNameController,
                icon: Icons.person_outline,
                isDark: isDark,
                required: true,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Age (Years)',
                      controller: _ageController,
                      icon: Icons.numbers,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Gender',
                      value: _selectedGender,
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedGender = val ?? 'Male'),
                      icon: Icons.wc_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      label: 'Full Legal Name',
                      controller: _fullNameController,
                      icon: Icons.person_outline,
                      isDark: isDark,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Age (Years)',
                      controller: _ageController,
                      icon: Icons.numbers,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Gender',
                      value: _selectedGender,
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedGender = val ?? 'Male'),
                      icon: Icons.wc_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (isMobile) ...[
              _buildDatePicker(
                label: 'Date of Birth (DOB)',
                value: _dob,
                onPicked: (d) => setState(() => _dob = d),
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Contact Phone',
                      controller: _phoneController,
                      icon: Icons.phone_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Emergency Phone',
                      controller: _emergencyContactController,
                      icon: Icons.contact_phone_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildDatePicker(
                      label: 'Date of Birth (DOB)',
                      value: _dob,
                      onPicked: (d) => setState(() => _dob = d),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Contact Phone Number',
                      controller: _phoneController,
                      icon: Icons.phone_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Emergency Contact Phone',
                      controller: _emergencyContactController,
                      icon: Icons.contact_phone_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _buildResponsiveRow(
              first: _buildTextField(
                label: 'Aadhar Card Number (12 Digits)',
                controller: _aadharController,
                icon: Icons.credit_card_rounded,
                isDark: isDark,
                hint: '12-digit UIDAI number',
              ),
              second: _buildTextField(
                label: 'PAN Card Number (10 Characters)',
                controller: _panController,
                icon: Icons.badge_outlined,
                isDark: isDark,
                hint: 'e.g. ABCDE1234F',
              ),
              isMobile: isMobile,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Residential & Permanent Address',
          icon: Icons.home_work_outlined,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            _buildTextField(
              label: 'Street Address & House / Flat No.',
              controller: _addressController,
              icon: Icons.location_on_outlined,
              isDark: isDark,
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            _buildResponsiveRow(
              first: _buildTextField(
                label: 'City / District',
                controller: _cityController,
                icon: Icons.location_city_outlined,
                isDark: isDark,
              ),
              second: _buildTextField(
                label: 'State / Province',
                controller: _stateController,
                icon: Icons.map_outlined,
                isDark: isDark,
              ),
              isMobile: isMobile,
            ),
          ],
        ),
      ],
    );
  }

  // TAB 2: COMPANY DETAILS
  Widget _buildTab2Company(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    return Column(
      children: [
        _buildSectionCard(
          title: 'Workplace & Department Assignment',
          icon: Icons.apartment_rounded,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            if (isMobile) ...[
              _buildDropdown<int?>(
                label: 'Assigned Department',
                value: _departments.any(
                  (d) => d['department_id'] == _selectedDepartmentId,
                )
                    ? _selectedDepartmentId
                    : null,
                items: _departments.map<DropdownMenuItem<int?>>((d) {
                  return DropdownMenuItem<int?>(
                    value: d['department_id'],
                    child: Text(d['name'] ?? 'Department'),
                  );
                }).toList(),
                onChanged: (val) =>
                    setState(() => _selectedDepartmentId = val),
                icon: Icons.business_outlined,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Designation / Title',
                      controller: _designationController,
                      icon: Icons.badge_outlined,
                      isDark: isDark,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Access Role',
                      value: _selectedRole,
                      items: const [
                        DropdownMenuItem(
                          value: 'Employee',
                          child: Text('Employee'),
                        ),
                        DropdownMenuItem(
                          value: 'Module Manager',
                          child: Text('Manager'),
                        ),
                        DropdownMenuItem(
                          value: 'Super Admin',
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedRole = val ?? 'Employee'),
                      icon: Icons.shield_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildDropdown<int?>(
                      label: 'Assigned Department',
                      value: _departments.any(
                        (d) => d['department_id'] == _selectedDepartmentId,
                      )
                          ? _selectedDepartmentId
                          : null,
                      items: _departments.map<DropdownMenuItem<int?>>((d) {
                        return DropdownMenuItem<int?>(
                          value: d['department_id'],
                          child: Text(d['name'] ?? 'Department'),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedDepartmentId = val),
                      icon: Icons.business_outlined,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Designation / Title',
                      controller: _designationController,
                      icon: Icons.badge_outlined,
                      isDark: isDark,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'System Access Role',
                      value: _selectedRole,
                      items: const [
                        DropdownMenuItem(
                          value: 'Employee',
                          child: Text('Employee (Base)'),
                        ),
                        DropdownMenuItem(
                          value: 'Module Manager',
                          child: Text('Module Manager'),
                        ),
                        DropdownMenuItem(
                          value: 'Super Admin',
                          child: Text('Super Admin'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedRole = val ?? 'Employee'),
                      icon: Icons.shield_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (isMobile) ...[
              _buildDropdown<String>(
                label: 'Employment Type',
                value: _selectedEmploymentType,
                items: const [
                  DropdownMenuItem(
                    value: 'Permanent',
                    child: Text('Permanent Full-Time'),
                  ),
                  DropdownMenuItem(
                    value: 'Contract',
                    child: Text('Contractual'),
                  ),
                  DropdownMenuItem(
                    value: 'Probation',
                    child: Text('Probationary Period'),
                  ),
                  DropdownMenuItem(
                    value: 'Internship',
                    child: Text('Internship'),
                  ),
                ],
                onChanged: (val) => setState(
                  () => _selectedEmploymentType = val ?? 'Permanent',
                ),
                icon: Icons.work_outline_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Weekly Off',
                      value: _selectedWeeklyOff,
                      items: const [
                        DropdownMenuItem(value: 'Sunday', child: Text('Sunday')),
                        DropdownMenuItem(value: 'Monday', child: Text('Monday')),
                        DropdownMenuItem(value: 'Saturday', child: Text('Saturday')),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedWeeklyOff = val ?? 'Sunday'),
                      icon: Icons.calendar_today_outlined,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Status',
                      value: _selectedStatus,
                      items: const [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'suspended',
                          child: Text('Banned'),
                        ),
                        DropdownMenuItem(
                          value: 'terminated',
                          child: Text('Terminated'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedStatus = val ?? 'active'),
                      icon: Icons.power_settings_new_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Employment Type',
                      value: _selectedEmploymentType,
                      items: const [
                        DropdownMenuItem(
                          value: 'Permanent',
                          child: Text('Permanent Full-Time'),
                        ),
                        DropdownMenuItem(
                          value: 'Contract',
                          child: Text('Contractual'),
                        ),
                        DropdownMenuItem(
                          value: 'Probation',
                          child: Text('Probationary Period'),
                        ),
                        DropdownMenuItem(
                          value: 'Internship',
                          child: Text('Internship'),
                        ),
                      ],
                      onChanged: (val) => setState(
                        () => _selectedEmploymentType = val ?? 'Permanent',
                      ),
                      icon: Icons.work_outline_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Weekly Off Day',
                      value: _selectedWeeklyOff,
                      items: const [
                        DropdownMenuItem(value: 'Sunday', child: Text('Sunday')),
                        DropdownMenuItem(value: 'Monday', child: Text('Monday')),
                        DropdownMenuItem(value: 'Saturday', child: Text('Saturday')),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedWeeklyOff = val ?? 'Sunday'),
                      icon: Icons.calendar_today_outlined,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Account Status',
                      value: _selectedStatus,
                      items: const [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active (Normal Operational)'),
                        ),
                        DropdownMenuItem(
                          value: 'suspended',
                          child: Text('Access Banned (Suspended)'),
                        ),
                        DropdownMenuItem(
                          value: 'terminated',
                          child: Text('Terminated / Relieved'),
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _selectedStatus = val ?? 'active'),
                      icon: Icons.power_settings_new_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Emp Code',
                      controller: _empCodeController,
                      icon: Icons.qr_code_rounded,
                      isDark: isDark,
                      enabled: false,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Machine ID',
                      controller: _biometricCodeController,
                      icon: Icons.fingerprint,
                      isDark: isDark,
                      hint: '1001',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildDatePicker(
                      label: 'Joining Date',
                      value: _joinDate,
                      onPicked: (d) => setState(() => _joinDate = d),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Official Email',
                      controller: _officialEmailController,
                      icon: Icons.email_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Employee Code (Fixed ID)',
                      controller: _empCodeController,
                      icon: Icons.qr_code_rounded,
                      isDark: isDark,
                      enabled: false,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Biometric Machine ID',
                      controller: _biometricCodeController,
                      icon: Icons.fingerprint,
                      isDark: isDark,
                      hint: 'e.g. 1001',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildDatePicker(
                      label: 'Date of Joining',
                      value: _joinDate,
                      onPicked: (d) => setState(() => _joinDate = d),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Official Email ID',
                      controller: _officialEmailController,
                      icon: Icons.email_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Base Pay & Compensation Grade',
          icon: Icons.payments_outlined,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            _buildResponsiveRow(
              first: _buildDropdown<String>(
                label: 'Salary Grade',
                value: _selectedSalaryGrade,
                items: const [
                  DropdownMenuItem(
                    value: 'Grade A',
                    child: Text('Grade A (Executive / Manager)'),
                  ),
                  DropdownMenuItem(
                    value: 'Grade B',
                    child: Text('Grade B (Senior Staff / Operator)'),
                  ),
                  DropdownMenuItem(
                    value: 'Grade C',
                    child: Text('Grade C (Technician / Junior Staff)'),
                  ),
                ],
                onChanged: (val) => setState(
                  () => _selectedSalaryGrade = val ?? 'Grade B',
                ),
                icon: Icons.stars_outlined,
                isDark: isDark,
              ),
              second: _buildTextField(
                label: 'Base Monthly Salary (₹)',
                controller: _salaryBaseController,
                icon: Icons.currency_rupee_rounded,
                isDark: isDark,
                keyboardType: TextInputType.number,
                required: true,
              ),
              isMobile: isMobile,
            ),
          ],
        ),
      ],
    );
  }

  // TAB 3: LEAVES & DEDUCTIONS
  Widget _buildTab3Leaves(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    return Column(
      children: [
        _buildSectionCard(
          title: 'Annual Paid Leave Entitlements',
          icon: Icons.event_available_rounded,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'CL Quota',
                      controller: _casualLeaveController,
                      icon: Icons.beach_access_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      hint: '12 Days',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'SL Quota',
                      controller: _sickLeaveController,
                      icon: Icons.sick_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      hint: '8 Days',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTextField(
                label: 'Paid Privilege Leaves (PL)',
                controller: _paidLeaveController,
                icon: Icons.verified_user_outlined,
                isDark: isDark,
                keyboardType: TextInputType.number,
                hint: '15 Days',
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Casual Leaves Quota (CL)',
                      controller: _casualLeaveController,
                      icon: Icons.beach_access_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      hint: '12 Days',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Sick Leaves Quota (SL)',
                      controller: _sickLeaveController,
                      icon: Icons.sick_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      hint: '8 Days',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTextField(
                      label: 'Paid Privilege Leaves (PL)',
                      controller: _paidLeaveController,
                      icon: Icons.verified_user_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      hint: '15 Days',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Loss of Pay (LWP) & Daily Salary Deduction',
          icon: Icons.money_off_rounded,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            _buildResponsiveRow(
              first: _buildTextField(
                label: 'Max Unpaid Leave Limit (Days)',
                controller: _unpaidLimitController,
                icon: Icons.warning_amber_rounded,
                isDark: isDark,
                keyboardType: TextInputType.number,
                hint: '10 Days',
              ),
              second: _buildTextField(
                label: 'Per-Day Loss of Pay Cut Rate (₹ / Day)',
                controller: _unpaidDeductionController,
                icon: Icons.currency_rupee,
                isDark: isDark,
                keyboardType: TextInputType.number,
                hint: 'Auto = Base / 30',
              ),
              isMobile: isMobile,
            ),
            const SizedBox(height: 10),
            Text(
              '💡 Note: By default, per-day salary deduction is calculated as Base Pay ÷ 30 days. You can specify a custom deduction rate if needed.',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // TAB 4: SALARY TEMPLATE & PREVIEW
  Widget _buildTab4SalaryPreview(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textTitle,
    Color textSub,
    bool isMobile,
  ) {
    final base = double.tryParse(_salaryBaseController.text.trim()) ?? 0.0;
    final daily = double.tryParse(_unpaidDeductionController.text.trim()) ??
        (base > 0 ? base / 30.0 : 0.0);
    final ctc = base * 12;

    return Column(
      children: [
        _buildSectionCard(
          title: 'Updated Compensation Summary',
          icon: Icons.receipt_long_outlined,
          cardBg: cardBg,
          borderColor: borderColor,
          textTitle: textTitle,
          isMobile: isMobile,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  _buildPreviewRow(
                    'Monthly Base Pay',
                    '₹${base.toStringAsFixed(2)}',
                    textTitle,
                    textSub,
                  ),
                  const Divider(height: 16),
                  _buildPreviewRow(
                    'Per-Day Earning / Deduction Rate',
                    '₹${daily.toStringAsFixed(2)} / day',
                    textTitle,
                    textSub,
                  ),
                  const Divider(height: 16),
                  _buildPreviewRow(
                    'Hourly Overtime Rate (8-hr shift)',
                    '₹${(daily / 8).toStringAsFixed(2)} / hour',
                    textTitle,
                    textSub,
                  ),
                  const Divider(height: 16),
                  _buildPreviewRow(
                    'Estimated Annual Gross CTC',
                    '₹${ctc.toStringAsFixed(2)} / year',
                    const Color(0xFF059669),
                    textSub,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF059669).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF059669),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All profile demographic data, leaves balance, and contract parameters will sync immediately upon saving.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. BOTTOM BAR
  Widget _buildBottomBar(bool isDark, Color borderColor, bool isMobile) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0F172A).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.95),
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  if (_activeTabIndex > 0) {
                    setState(() => _activeTabIndex = _activeTabIndex - 1);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(_activeTabIndex > 0 ? 'Back' : 'Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _activeTabIndex < 3
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Next Step', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => setState(() => _activeTabIndex = _activeTabIndex + 1),
                    )
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(
                        _isSaving ? 'Updating...' : 'Save Changes',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSaving ? null : _saveProfileChanges,
                    ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_activeTabIndex > 0)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : Colors.black87,
                side: BorderSide(color: borderColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Previous Step'),
              onPressed: () =>
                  setState(() => _activeTabIndex = _activeTabIndex - 1),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              if (_activeTabIndex < 3)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Next Step'),
                  onPressed: () =>
                      setState(() => _activeTabIndex = _activeTabIndex + 1),
                ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(
                  _isSaving ? 'Updating...' : 'Save & Update Employee',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _saveProfileChanges,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // WIDGET HELPERS
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color cardBg,
    required Color borderColor,
    required Color textTitle,
    required List<Widget> children,
    bool isMobile = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 14 : 20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: const Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textTitle,
                        fontSize: isMobile ? 13.5 : 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 12 : 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    bool required = false,
    bool enabled = true,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(
            color: enabled
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white38 : Colors.grey),
            fontSize: 13,
          ),
          validator: required
              ? (val) =>
          (val == null || val.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : Colors.grey.shade400,
              fontSize: 12.5,
            ),
            prefixIcon: Icon(
              icon,
              size: 16,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF059669)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required IconData icon,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              dropdownColor:
              isDark ? const Color(0xFF0F172A) : Colors.white,
              icon: const Icon(Icons.arrow_drop_down_rounded),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPicked,
    required bool isDark,
  }) {
    final display = value != null
        ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
        : 'Select Date';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime(1995, 1, 1),
              firstDate: DateTime(1950),
              lastDate: DateTime.now(),
            );
            if (picked != null) onPicked(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Text(
                  display,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(
      String label,
      String value,
      Color textTitle,
      Color textSub, {
        bool isBold = false,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textSub,
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: textTitle,
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}