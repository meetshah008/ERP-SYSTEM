import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../../core/network/session_manager.dart';
import 'employee_edit_screen.dart';

class EmployeeDetailsScreen extends StatefulWidget {
  final dynamic employeeId;

  const EmployeeDetailsScreen({super.key, required this.employeeId});

  @override
  State<EmployeeDetailsScreen> createState() => _EmployeeDetailsScreenState();
}

class _EmployeeDetailsScreenState extends State<EmployeeDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSavingPermissions = false;
  bool _canManageStaff = false;
  bool _canOverrideAttendance = false;
  Map<String, dynamic> _data = {};
  List<dynamic> _departments = [];

  // System Access & Permissions StateF
  late Map<String, bool> _permissions;
  String _selectedRole = 'Employee';
  bool _userActive = true;

  // Attendance & Biometric Filter State
  int _attMonth = 0; // 0 = All Months
  int _attYear = DateTime.now().year;
  DateTimeRange? _attCustomRange;
  List<dynamic> _employeeAttendanceList = [];
  bool _isLoadingAttendance = false;

  static const List<String> _attMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _permissions = {};
    _initScreen();
  }

  Future<void> _initScreen() async {
    setState(() => _isLoading = true);
    await _checkUserPermissions();
    final targetLength = _canManageStaff ? 5 : 4;
    _tabController = TabController(length: targetLength, vsync: this);
    await _fetchFullProfile(setLoadingState: false);
    if (mounted) {
      setState(() => _isLoading = false);
      _fetchEmployeeAttendance();
    }
  }

  Future<void> _checkUserPermissions() async {
    final session = await SessionManager.getUserSession();
    final isSuper = session['role'] == 'Super Admin';
    final allowed =
        isSuper || await SessionManager.hasPermission('hr_manage_staff');
    final allowedOverride =
        isSuper || await SessionManager.hasPermission('attendance_override');
    _canManageStaff = allowed;
    _canOverrideAttendance = allowedOverride;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 1. Fetch Full Profile
  Future<void> _fetchFullProfile({bool setLoadingState = true}) async {
    if (setLoadingState) setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse(
          'http://localhost:5000/api/hr/employees/${widget.employeeId}/full-profile',
        ),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          _data = json['data'] ?? {};
          final emp = _data['employee'] ?? {};
          final perms = _data['permissions'] ?? {};

          _permissions = Map<String, bool>.from(
            perms.map((k, v) => MapEntry(k.toString(), v == true)),
          );
          _selectedRole = emp['role_name'] ?? 'Employee';
          _userActive = emp['user_active'] == 1 || emp['user_active'] == true;

          final att = (_data['attendance'] as List?) ?? [];
          if (att.isNotEmpty && att[0]['work_date'] != null) {
            try {
              final d = DateTime.tryParse(att[0]['work_date'].toString());
              if (d != null) {
                _attYear = d.year;
                _attMonth = 0;
              }
            } catch (_) {}
          }
        }
      }

      // Fetch departments for edit modal
      try {
        final deptRes = await http.get(
          Uri.parse('http://localhost:5000/api/hr/departments'),
        );
        if (deptRes.statusCode == 200) {
          final deptJson = jsonDecode(deptRes.body);
          _departments = deptJson['data'] ?? [];
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
    if (setLoadingState && mounted) {
      setState(() => _isLoading = false);
      _fetchEmployeeAttendance();
    }
  }

  // 1.1 Fetch Attendance
  Future<void> _fetchEmployeeAttendance() async {
    setState(() => _isLoadingAttendance = true);
    try {
      String url =
          'http://localhost:5000/api/hr/attendance?employee_id=${widget.employeeId}&';
      if (_attCustomRange != null) {
        final start = _attCustomRange!.start.toIso8601String().split('T')[0];
        final end = _attCustomRange!.end.toIso8601String().split('T')[0];
        url += 'start_date=$start&end_date=$end';
      } else {
        if (_attMonth > 0) {
          url += 'month=$_attMonth&year=$_attYear';
        } else {
          url += 'year=$_attYear';
        }
      }

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          setState(() {
            _employeeAttendanceList = json['data'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
    }
    if (mounted) setState(() => _isLoadingAttendance = false);
  }

  String _formatWorkDuration(dynamic minutes, [String? inTime, String? outTime]) {
    final m = int.tryParse(minutes?.toString() ?? '0') ?? 0;
    if (m > 0) {
      final hours = m ~/ 60;
      final mins = m % 60;
      return '${hours}h ${mins}m';
    }

    // Agar database se minutes 0 aaye, toh In Time aur Out Time se khud calculate karega
    if (inTime != null && outTime != null && inTime != '--:--' && outTime != '--:--') {
      try {
        final inParts = inTime.split(':');
        final outParts = outTime.split(':');
        if (inParts.length >= 2 && outParts.length >= 2) {
          int inH = int.parse(inParts[0]);
          int inM = int.parse(inParts[1]);
          int outH = int.parse(outParts[0]);
          int outM = int.parse(outParts[1]);

          // Agar out time in time se chota hai (jaise 06:00 vs 09:00), toh 6 PM (18:00) hai
          if (outH < inH && outH < 12) {
            outH += 12; // 6 + 12 = 18:00
          }

          int diff = (outH * 60 + outM) - (inH * 60 + inM);
          if (diff > 0) {
            final hours = diff ~/ 60;
            final mins = diff % 60;
            return '${hours}h ${mins}m';
          }
        }
      } catch (_) {}
    }
    return '--';
  }

  // 1.2 Manual Attendance Override
  void _openEditAttendanceDialog(dynamic row) {
    final attendanceId = row['attendance_id'];
    String selectedStatus = row['status'] ?? 'Present';
    final inCtrl = TextEditingController(
      text:
          row['check_in_time'] ??
          (row['check_in'] != null
              ? row['check_in'].toString().split('T').last.substring(0, 8)
              : ''),
    );
    final outCtrl = TextEditingController(
      text:
          row['check_out_time'] ??
          (row['check_out'] != null
              ? row['check_out'].toString().split('T').last.substring(0, 8)
              : ''),
    );
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
          final cardBorder = isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.edit_calendar_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manual Attendance Override',
                              style: TextStyle(
                                color: textTitle,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Date: ${row['work_date']?.toString().split('T')[0]}',
                              style: TextStyle(color: textSub, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    'Attendance Status',
                    style: TextStyle(
                      color: textTitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedStatus,
                        isExpanded: true,
                        dropdownColor: dialogBg,
                        style: TextStyle(color: textTitle, fontSize: 13),
                        items: ['Present', 'Late', 'Half-Day', 'Absent']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null)
                            setDialogState(() => selectedStatus = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-In Time',
                              style: TextStyle(
                                color: textTitle,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: inCtrl,
                              style: TextStyle(color: textTitle, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '09:00:00',
                                hintStyle: TextStyle(
                                  color: textSub,
                                  fontSize: 11,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: cardBorder),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-Out Time',
                              style: TextStyle(
                                color: textTitle,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: outCtrl,
                              style: TextStyle(color: textTitle, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '18:00:00',
                                hintStyle: TextStyle(
                                  color: textSub,
                                  fontSize: 11,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: cardBorder),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            try {
                              final res = await http.put(
                                Uri.parse(
                                  'http://localhost:5000/api/hr/attendance/$attendanceId',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'status': selectedStatus,
                                  'check_in': inCtrl.text.trim(),
                                  'check_out': outCtrl.text.trim(),
                                }),
                              );
                              final json = jsonDecode(res.body);
                              if (res.statusCode == 200 &&
                                  json['success'] == true) {
                                Navigator.pop(ctx);
                                _fetchEmployeeAttendance();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      json['message'] ?? 'Record updated!',
                                    ),
                                    backgroundColor: const Color(0xFF059669),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                setDialogState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      json['message'] ?? 'Update failed',
                                    ),
                                    backgroundColor: Colors.redAccent,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    child: Text(
                      isSaving ? 'Saving Changes...' : 'Save Override Changes',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 2. Save Permissions & Roles
  Future<void> _savePermissions() async {
    setState(() => _isSavingPermissions = true);
    try {
      final res = await http.put(
        Uri.parse(
          'http://localhost:5000/api/hr/employees/${widget.employeeId}/permissions',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'permissions': _permissions,
          'user_active': _userActive,
          'role_name': _selectedRole,
        }),
      );

      final json = jsonDecode(res.body);

      if (res.statusCode == 200 && json['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      json['message'] ?? 'Permissions saved successfully!',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(json['message'] ?? 'Error saving permissions'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _isSavingPermissions = false);
  }

  // 3. Create Login Modal
  void _openCreateLoginDialog() {
    final emp = _data['employee'] ?? {};
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController(text: emp['email'] ?? '');
    final passCtrl = TextEditingController(text: '123456');
    String selectedRole = 'Employee';
    bool isSaving = false;
    bool obscurePass = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark
              ? const Color(0xFF94A3B8)
              : const Color(0xFF64748B);
          final borderColor = isDark
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: Container(
              width: 440,
              decoration: BoxDecoration(
                color: dialogBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : const Color(0xFFF8FAFC),
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.vpn_key_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create ERP Login Account',
                                  style: TextStyle(
                                    color: titleColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'For ${emp['full_name'] ?? 'Staff Member'}',
                                  style: TextStyle(
                                    color: textSub,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: textSub,
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              'Login Email / Username',
                              emailCtrl,
                              Icons.email_outlined,
                              isDark,
                              required: true,
                              hint: 'e.g. staff@company.com',
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Initial Password',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                TextFormField(
                                  controller: passCtrl,
                                  obscureText: obscurePass,
                                  validator: (v) => v!.trim().isEmpty
                                      ? 'Password is required'
                                      : (v.trim().length < 6
                                            ? 'Min 6 characters'
                                            : null),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter password',
                                    prefixIcon: Icon(
                                      Icons.lock_outline,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        obscurePass
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 17,
                                      ),
                                      onPressed: () => setDialogState(
                                        () => obscurePass = !obscurePass,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFF1F5F9),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownField<String>(
                              label: 'Assigned Role',
                              value: selectedRole,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Employee',
                                  child: Text('Employee (Standard Staff)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Module Manager',
                                  child: Text('Module Manager (Supervisor)'),
                                ),
                                DropdownMenuItem(
                                  value: 'Super Admin',
                                  child: Text('Super Admin (Executive)'),
                                ),
                              ],
                              onChanged: (val) => setDialogState(
                                () => selectedRole = val ?? 'Employee',
                              ),
                              icon: Icons.security_rounded,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.02)
                            : const Color(0xFFF8FAFC),
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: textSub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            icon: isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 16),
                            label: Text(
                              isSaving
                                  ? 'Creating...'
                                  : 'Create & Link Account',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate())
                                      return;
                                    setDialogState(() => isSaving = true);
                                    try {
                                      final res = await http.post(
                                        Uri.parse(
                                          'http://localhost:5000/api/hr/employees/${widget.employeeId}/create-login',
                                        ),
                                        headers: {
                                          'Content-Type': 'application/json',
                                        },
                                        body: jsonEncode({
                                          'email': emailCtrl.text.trim(),
                                          'password': passCtrl.text.trim(),
                                          'role_name': selectedRole,
                                        }),
                                      );
                                      final json = jsonDecode(res.body);
                                      if (res.statusCode == 201 &&
                                          json['success'] == true) {
                                        Navigator.pop(ctx);
                                        _fetchFullProfile();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              json['message'] ??
                                                  'Login created!',
                                            ),
                                            backgroundColor: const Color(
                                              0xFF059669,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      } else {
                                        setDialogState(() => isSaving = false);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              json['message'] ??
                                                  'Creation failed',
                                            ),
                                            backgroundColor: Colors.redAccent,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setDialogState(() => isSaving = false);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 4. Edit Profile Details Screen (Zero Popups Dedicated Full Screen)
  Future<void> _openEditDetailsDialog() async {
    if (!_canManageStaff) return;
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeEditScreen(
          employeeId: widget.employeeId,
          initialData: _data,
          onEmployeeUpdated: _fetchFullProfile,
        ),
      ),
    );
    if (updated == true) {
      _fetchFullProfile();
    }
  }

  // ================= 🏗️ BUILD MAIN VIEW =================
  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final isMobile = MediaQuery.of(context).size.width < 768;

    final cardBg = isDark
        ? const Color(0xFF1E293B)
        : Colors.white;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    final emp = _data['employee'] ?? {};
    final name = emp['full_name'] ?? 'Staff Member';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
    final status = (emp['status'] ?? 'active').toString().toLowerCase();

    Color statusColor = const Color(0xFF10B981);
    String statusText = 'ACTIVE';
    if (status == 'suspended') {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'ACCESS BANNED';
    } else if (status == 'terminated') {
      statusColor = Colors.redAccent;
      statusText = 'TERMINATED';
    }

    // ==========================================
    // 📱 MOBILE VIEW: Clean Native Slate Layout (No Heavy Wallpaper)
    // ==========================================
    if (isMobile) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                )
              : NestedScrollView(
                  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                    return [
                      // 1. TOP HEADER & HERO & QUICK ACTIONS
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1.1 TOP BAR (iOS/Android Native Style)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () => Navigator.pop(context),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 15,
                                        color: textTitle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Employee Profile',
                                          style: TextStyle(
                                            color: textTitle,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Row(
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: emp['biometric_emp_code'] != null
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFFF59E0B),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              emp['biometric_emp_code'] != null
                                                  ? 'Biometric Sync: Online'
                                                  : 'Biometric: Unlinked',
                                              style: TextStyle(
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _openEditDetailsDialog,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: textTitle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 1.2 QUICK ACTION COMMAND BAR
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Row(
                                children: [
                                  if (_canManageStaff)
                                    Expanded(
                                      child: SizedBox(
                                        height: 38,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                            foregroundColor: textTitle,
                                            side: BorderSide(
                                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                          ),
                                          icon: Icon(
                                            Icons.edit_note_rounded,
                                            size: 16,
                                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                          ),
                                          label: const Text(
                                            'Edit Details',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          onPressed: _openEditDetailsDialog,
                                        ),
                                      ),
                                    ),
                                  if (_canManageStaff) const SizedBox(width: 10),
                                  if (_canManageStaff)
                                    Expanded(
                                      child: SizedBox(
                                        height: 38,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                          ),
                                          icon: _isSavingPermissions
                                              ? const SizedBox(
                                                  width: 13,
                                                  height: 13,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Icon(Icons.shield_outlined, size: 15),
                                          label: const Text(
                                            'Save Permissions',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          onPressed: _isSavingPermissions ? null : _savePermissions,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // 1.3 STAFF IDENTITY HERO CARD (Clean White Native Card)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Avatar with presence badge
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 52,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                initial,
                                                style: const TextStyle(
                                                  color: Color(0xFF065F46),
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: -2,
                                            bottom: -2,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  name,
                                                  style: TextStyle(
                                                    color: textTitle,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '#${emp['emp_code'] ?? '01'}',
                                                    style: TextStyle(
                                                      color: textTitle,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 5,
                                                        height: 5,
                                                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        statusText,
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEEF2FF),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: const Color(0xFFC7D2FE)),
                                                  ),
                                                  child: Text(
                                                    emp['role_name'] ?? emp['designation'] ?? 'Operator',
                                                    style: const TextStyle(
                                                      color: Color(0xFF4338CA),
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.business_outlined,
                                                  size: 13,
                                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    emp['department_name'] ?? 'Manufacturing Operations',
                                                    style: TextStyle(
                                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                      fontSize: 11.5,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.fingerprint,
                                              size: 14,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Bio ID: ',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                '${emp['biometric_emp_code'] ?? "N/A"}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: textTitle,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today_outlined,
                                              size: 13,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Joined: ',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                '${emp['join_date']?.toString().split("T")[0] ?? "N/A"}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: textTitle,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 14,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Unit: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${emp['branch_name'] ?? "Main Plant"} • ${emp['department_name'] ?? "Assembly Sector A"}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: textTitle,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),

                      // 2. STICKY SEGMENTED TAB BAR
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverTabBarDelegate(
                          Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            child: TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              dividerColor: Colors.transparent,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                              tabs: [
                                const Tab(
                                  height: 36,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.grid_view_rounded, size: 14),
                                        SizedBox(width: 6),
                                        Text('Overview & KPIs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                                const Tab(
                                  height: 36,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.badge_outlined, size: 14),
                                        SizedBox(width: 6),
                                        Text('Personal & Job', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_canManageStaff)
                                  const Tab(
                                    height: 36,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.shield_outlined, size: 14),
                                          SizedBox(width: 6),
                                          Text('Permissions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                const Tab(
                                  height: 36,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.history_rounded, size: 14),
                                        SizedBox(width: 6),
                                        Text('Attendance Logs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                                const Tab(
                                  height: 36,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.account_balance_wallet_outlined, size: 14),
                                        SizedBox(width: 6),
                                        Text('Payroll', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          height: 48,
                          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        ),
                      ),
                    ];
                  },
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTab1Overview(cardBg, cardBorder, textTitle, textSub, isDark),
                        _buildTab2Employment(cardBg, cardBorder, textTitle, textSub, isDark),
                        if (_canManageStaff)
                          _buildTab3Permissions(cardBg, cardBorder, textTitle, textSub, isDark),
                        _buildTab4AttendanceLeaves(cardBg, cardBorder, textTitle, textSub, isDark),
                        _buildTab5Payroll(cardBg, cardBorder, textTitle, textSub, isDark),
                      ],
                    ),
                  ),
                ),
        ),
      );
    }

    // ==========================================
    // 💻 DESKTOP LAYOUT (Preserved Full-Width Botanical Layout)
    // ==========================================
    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. TOP HEADER BAR
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded),
                                color: textTitle,
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Employee Profile & Lifecycle',
                                      style: TextStyle(
                                        color: textTitle,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Live biometric logs, compensation, contract & permissions',
                                      style: TextStyle(
                                        color: textSub,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_canManageStaff)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: textTitle,
                                    side: BorderSide(color: cardBorder),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text(
                                    'Edit Details',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: _openEditDetailsDialog,
                                ),
                              if (_canManageStaff) ...[
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: _isSavingPermissions
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.security_update_good_rounded,
                                          size: 16,
                                        ),
                                  label: const Text(
                                    'Save Permissions',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _isSavingPermissions
                                      ? null
                                      : _savePermissions,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // 2. HERO PROFILE CARD
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: cardBorder, width: 1.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.3 : 0.05,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 34,
                                      backgroundColor: const Color(
                                        0xFF059669,
                                      ).withValues(alpha: 0.15),
                                      child: Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  color: textTitle,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF0284C7,
                                                  ).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  emp['emp_code'] ?? 'EMP',
                                                  style: const TextStyle(
                                                    color: Color(0xFF0284C7),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(
                                                    alpha: 0.15,
                                                  ),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: statusColor.withValues(
                                                      alpha: 0.3,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        color: statusColor,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      statusText,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF8B5CF6,
                                                  ).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  emp['role_name'] ?? 'Employee',
                                                  style: const TextStyle(
                                                    color: Color(0xFF8B5CF6),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              _buildHeroMeta(
                                                Icons.badge_outlined,
                                                emp['designation'] ?? 'Staff',
                                                textSub,
                                              ),
                                              const SizedBox(width: 18),
                                              _buildHeroMeta(
                                                Icons.apartment_rounded,
                                                emp['department_name'] ?? 'Operations',
                                                textSub,
                                              ),
                                              const SizedBox(width: 18),
                                              _buildHeroMeta(
                                                Icons.fingerprint,
                                                'Machine ID: ${emp['biometric_emp_code'] ?? 'Not Linked'}',
                                                textSub,
                                              ),
                                              const SizedBox(width: 18),
                                              _buildHeroMeta(
                                                Icons.calendar_today_outlined,
                                                'Joined: ${emp['join_date']?.toString().split('T')[0] ?? 'N/A'}',
                                                textSub,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 3. SEGMENTED TAB BAR (DESKTOP FULL WIDTH)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorder),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: textSub,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            tabs: [
                              const Tab(
                                icon: Icon(Icons.analytics_outlined, size: 16),
                                text: 'Overview & Metrics',
                              ),
                              const Tab(
                                icon: Icon(Icons.badge_outlined, size: 16),
                                text: 'Personal & Job Profile',
                              ),
                              if (_canManageStaff)
                                const Tab(
                                  icon: Icon(Icons.security_rounded, size: 16),
                                  text: 'Access & Permissions',
                                ),
                              const Tab(
                                icon: Icon(Icons.history_rounded, size: 16),
                                text: 'Attendance & Leaves',
                              ),
                              const Tab(
                                icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                                text: 'Salary & Payroll',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 4. TAB CONTENTS (DESKTOP)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildTab1Overview(
                                  cardBg,
                                  cardBorder,
                                  textTitle,
                                  textSub,
                                  isDark,
                                ),
                                _buildTab2Employment(
                                  cardBg,
                                  cardBorder,
                                  textTitle,
                                  textSub,
                                  isDark,
                                ),
                               
                                if (_canManageStaff)
                                  _buildTab3Permissions(cardBg, cardBorder, textTitle, textSub, isDark),
                                _buildTab4AttendanceLeaves(cardBg, cardBorder, textTitle, textSub, isDark),
                                _buildTab5Payroll(cardBg, cardBorder, textTitle, textSub, isDark),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ================= 📊 TAB 1: OVERVIEW & RESPONSIVE METRICS =================
  Widget _buildTab1Overview(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final perf = _data['performance'] ?? {};
    final emp = _data['employee'] ?? {};


    final totalShifts =
        int.tryParse(perf['total_shifts']?.toString() ?? '0') ?? 0;
    final attRate = perf['attendance_rate'];
    final puncRate = perf['punctuality_rate'];
    final approvedLeaves =
        int.tryParse(perf['approved_leave_days']?.toString() ?? '0') ?? 0;
    final overtime =
        double.tryParse(perf['total_overtime']?.toString() ?? '0') ?? 0.0;

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        // 4 Metric Cards (Mobile: 2x2 grid, Desktop: 4 across)
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 650;

            final card1 = _buildMetricCard(
              title: 'Shift Attendance',
              value: attRate != null ? '$attRate%' : 'No Logs Yet',
              subtitle: totalShifts > 0
                  ? '$totalShifts Shifts Logged'
                  : '0 machine shifts',
              icon: Icons.access_time_rounded,
              color: const Color(0xFF059669),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card2 = _buildMetricCard(
              title: 'Punctuality Rate',
              value: puncRate != null ? '$puncRate%' : '--',
              subtitle: puncRate != null
                  ? 'On-time Check-ins'
                  : 'No punch records',
              icon: Icons.alarm_on_rounded,
              color: const Color(0xFF0284C7),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card3 = _buildMetricCard(
              title: 'Approved Leaves',
              value: '$approvedLeaves Days',
              subtitle: 'On record this year',
              icon: Icons.event_note_rounded,
              color: const Color(0xFFD97706),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card4 = _buildMetricCard(
              title: 'Overtime Logged',
              value: '${overtime}h',
              subtitle: 'Extra shifts sum',
              icon: Icons.more_time_rounded,
              color: const Color(0xFF8B5CF6),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            if (isMobile) {
              return Column(
                children: [
                  Row(children: [card1, const SizedBox(width: 10), card2]),
                  const SizedBox(height: 10),
                  Row(children: [card3, const SizedBox(width: 10), card4]),
                ],
              );
            }

            return Row(
              children: [
                card1,
                const SizedBox(width: 12),
                card2,
                const SizedBox(width: 12),
                card3,
                const SizedBox(width: 12),
                card4,
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Two Section Cards (Mobile: Stacked Column, Desktop: 2 Columns)
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 700;

            final cardWorkforce = _buildFrostedSectionCard(
              title: 'Workforce & Machine Identity',
              icon: Icons.vpn_key_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              children: [
                _buildDetailRow(
                  'Employee Code',
                  emp['emp_code'] ?? '01',
                  textTitle,
                  textSub,
                  customValue: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${emp['emp_code'] ?? "01"}',
                      style: TextStyle(color: textTitle, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                _buildDetailRow(
                  'Biometric Machine ID',
                  emp['biometric_emp_code'] ?? 'Not Linked',
                  textTitle,
                  textSub,
                  customValue: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${emp['biometric_emp_code'] ?? "1001"}',
                        style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          emp['biometric_emp_code'] != null ? 'Synced' : 'Offline',
                          style: const TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDetailRow(
                  'Branch / Unit',
                  emp['branch_name'] ?? 'Main Plant / Headquarter',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Department',
                  emp['department_name'] ?? 'Manufacturing Operations',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Shift Assignment',
                  'Shift A (06:00 - 14:30)',
                  textTitle,
                  textSub,
                  customValue: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Shift A (06:00 - 14:30)',
                      style: TextStyle(color: Color(0xFF047857), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                _buildDetailRow(
                  'Date of Joining',
                  emp['join_date']?.toString().split('T')[0] ?? '2026-10-12',
                  textTitle,
                  textSub,
                ),
              ],
            );

            final clLeft = int.tryParse(emp['leave_balance_casual']?.toString() ?? '12') ?? 12;
            final slLeft = int.tryParse(emp['leave_balance_sick']?.toString() ?? '8') ?? 8;
            final elLeft = int.tryParse(emp['leave_balance_paid']?.toString() ?? '15') ?? 15;

            final cardSchedule = _buildFrostedSectionCard(
              title: 'Schedule & Leave Quotas',
              icon: Icons.calendar_month_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  emp['employment_type'] ?? 'Permanent',
                  style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              children: [
                _buildLeaveQuotaProgressBar(
                  title: 'Casual Leave (CL)',
                  current: clLeft,
                  total: 14,
                  color: const Color(0xFF10B981),
                  textTitle: textTitle,
                  textSub: textSub,
                ),
                _buildLeaveQuotaProgressBar(
                  title: 'Medical / Sick Leave (SL)',
                  current: slLeft,
                  total: 10,
                  color: const Color(0xFF14B8A6),
                  textTitle: textTitle,
                  textSub: textSub,
                ),
                _buildLeaveQuotaProgressBar(
                  title: 'Earned Leave (EL)',
                  current: elLeft,
                  total: 15,
                  color: const Color(0xFF6366F1),
                  textTitle: textTitle,
                  textSub: textSub,
                ),
              ],
            );

            if (isMobile) {
              return Column(
                children: [
                  cardWorkforce,
                  const SizedBox(height: 16),
                  cardSchedule,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cardWorkforce),
                const SizedBox(width: 16),
                Expanded(child: cardSchedule),
              ],
            );
          },
        ),
      ],
    );
  }

  // ================= 💼 TAB 2: PERSONAL & EMPLOYMENT PROFILE =================
  Widget _buildTab2Employment(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final emp = _data['employee'] ?? {};
    final baseSalary =
        double.tryParse(emp['salary_base']?.toString() ?? '0') ?? 0.0;
    final customDeduction = double.tryParse(
      emp['unpaid_leave_per_day_deduction']?.toString() ?? '',
    );
    final double perDayDeduction =
        (customDeduction != null && customDeduction > 0)
            ? customDeduction
            : (baseSalary > 0 ? (baseSalary / 30.0) : 0.0);

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 750;

            final cardEmployment = _buildFrostedSectionCard(
              title: 'Employment & Organization',
              icon: Icons.business_center_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              trailing: _canManageStaff
                  ? IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Color(0xFF059669),
                      ),
                      tooltip: 'Edit Details',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: _openEditDetailsDialog,
                    )
                  : null,
              children: [
                _buildDetailRow(
                  'Employment Type',
                  emp['employment_type'] ?? 'Permanent',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Designation',
                  emp['designation'] ?? 'Staff',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Department',
                  emp['department_name'] ?? 'Operations',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Branch / Unit',
                  emp['branch_name'] ?? 'Main Plant / Headquarter',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Weekly Off Day',
                  emp['weekly_off'] ?? 'Sunday',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Date of Joining',
                  emp['join_date']?.toString().split('T')[0] ?? 'Not Specified',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Official Email',
                  emp['email'] ?? emp['user_email'] ?? 'Not Configured',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Phone Number',
                  emp['phone'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
              ],
            );

            final cardPersonal = _buildFrostedSectionCard(
              title: 'Personal Identity & KYC Details',
              icon: Icons.person_pin_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              children: [
                _buildDetailRow(
                  'Full Legal Name',
                  emp['full_name'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Age',
                  emp['age'] != null ? '${emp['age']} yrs' : 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Gender',
                  emp['gender'] ?? 'Not Specified',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Date of Birth',
                  emp['dob']?.toString().split('T')[0] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Emergency Contact',
                  emp['emergency_contact'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Aadhar Card Number',
                  emp['aadhar_number'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'PAN Card Number',
                  emp['pan_number'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
              ],
            );

            final cardAddress = _buildFrostedSectionCard(
              title: 'Residential & Permanent Address',
              icon: Icons.home_work_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              children: [
                _buildDetailRow(
                  'Street Address',
                  emp['address'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'City / District',
                  emp['city'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'State / Province',
                  emp['state'] ?? 'Not Provided',
                  textTitle,
                  textSub,
                ),
              ],
            );

            final cardLeaves = _buildFrostedSectionCard(
              title: 'Leave Quotas & Policy Entitlements',
              icon: Icons.beach_access_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              children: [
                _buildDetailRow(
                  'Casual Leave Quota',
                  '${emp['leave_balance_casual'] ?? 12} Days / Year',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Sick Leave Quota',
                  '${emp['leave_balance_sick'] ?? 8} Days / Year',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Paid Leave Quota',
                  '${emp['leave_balance_paid'] ?? 15} Days / Year',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Unpaid Leave Limit (LWP)',
                  '${emp['unpaid_leave_limit'] ?? 10} Days Max',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Loss of Pay Deduction Rate',
                  '₹${perDayDeduction.toStringAsFixed(2)} / Day',
                  textTitle,
                  textSub,
                ),
              ],
            );

            if (isMobile) {
              return Column(
                children: [
                  cardEmployment,
                  const SizedBox(height: 16),
                  cardPersonal,
                  const SizedBox(height: 16),
                  cardAddress,
                  const SizedBox(height: 16),
                  cardLeaves,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      cardEmployment,
                      const SizedBox(height: 16),
                      cardAddress,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      cardPersonal,
                      const SizedBox(height: 16),
                      cardLeaves,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ================= 🔐 TAB 3: ACCESS & GRANULAR PERMISSIONS =================
  Widget _buildTab3Permissions(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final emp = _data['employee'] ?? {};

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        _buildFrostedSectionCard(
          title: 'System Login & Account Status',
          icon: Icons.account_circle_outlined,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textTitle: textTitle,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Login Username / Email',
                    style: TextStyle(color: textSub, fontSize: 12.5),
                  ),
                  emp['user_email'] != null
                      ? Text(
                          emp['user_email'],
                          style: TextStyle(
                            color: textTitle,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : (_canManageStaff
                            ? ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Create Login',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: _openCreateLoginDialog,
                              )
                            : Text(
                                'No Account Linked',
                                style: TextStyle(
                                  color: textSub,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              )),
                ],
              ),
            ),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Access Status',
                        style: TextStyle(
                          color: textTitle,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _userActive
                            ? 'Employee can login and perform duties'
                            : 'Account is frozen / banned',
                        style: TextStyle(color: textSub, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _userActive,
                  activeColor: const Color(0xFF059669),
                  onChanged: _canManageStaff
                      ? (v) => setState(() => _userActive = v)
                      : null,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildFrostedSectionCard(
          title: 'Granular Feature Permissions',
          icon: Icons.admin_panel_settings_outlined,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textTitle: textTitle,
          children: [
            Text(
              'Turn switches ON or OFF for each feature, then click Save Permissions.',
              style: TextStyle(color: textSub, fontSize: 12),
            ),
            const SizedBox(height: 14),

            _buildPermissionCategory('👥 HR & Workforce Management', textTitle),
            _buildPermissionSwitch(
              'hr_view_directory',
              'View Employee Directory',
              'Browse workforce roster',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'hr_manage_staff',
              'Onboard & Terminate Staff',
              'Add or modify employee lifecycle',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'hr_manage_departments',
              'Manage Departments',
              'Create or edit company units',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'hr_view_lifecycle',
              'View Staff Profile & Lifecycle',
              'Access detailed contracts, personal docs & work metrics',
              textTitle,
              textSub,
            ),

            const Divider(height: 24),
            _buildPermissionCategory(
              '🕒 Biometric & Attendance System',
              textTitle,
            ),
            _buildPermissionSwitch(
              'attendance_view_logs',
              'View Punch Logs & Daily Records',
              'See machine scans & timestamps',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'attendance_import_excel',
              'Upload Biometric Excel Sheets',
              'Upload machine log dump files',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'attendance_override',
              'Manual Attendance Override',
              'Edit or fix missed punches',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'attendance_biometric_manage',
              'Advanced Biometric Tools',
              'Device mapping, terminal inspection & raw dump tools',
              textTitle,
              textSub,
            ),

            const Divider(height: 24),
            _buildPermissionCategory('📅 Leave Management System', textTitle),
            _buildPermissionSwitch(
              'leaves_apply',
              'Apply For Leaves',
              'Submit personal leave requests',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'leaves_approve',
              'Approve / Reject Staff Leaves',
              'Department head leave approval',
              textTitle,
              textSub,
            ),

            const Divider(height: 24),
            _buildPermissionCategory('📋 Projects & Work Orders', textTitle),
            _buildPermissionSwitch(
              'tasks_view',
              'View Projects & Kanban Tasks',
              'Access project board and task details',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'tasks_create_assign',
              'Create Tasks & Assign Members',
              'Distribute workloads to team',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'tasks_log_timesheet',
              'Log Work Timesheets',
              'Submit hourly task progress logs',
              textTitle,
              textSub,
            ),

            const Divider(height: 24),
            _buildPermissionCategory(
              '🏭 Inventory & Floor Operations',
              textTitle,
            ),
            _buildPermissionSwitch(
              'inventory_view_stock',
              'View Stock Levels',
              'Inspect inventory quantities',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'inventory_manage_material',
              'Issue & Indent Materials',
              'Material dispatch for production',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'manufacturing_view_bom',
              'View Bill of Materials (BOM)',
              'Access manufacturing recipes',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'manufacturing_work_orders',
              'Manage Floor Work Orders',
              'Control plant batch processing',
              textTitle,
              textSub,
            ),

            const Divider(height: 24),
            _buildPermissionCategory('💼 Finance & Audit Logs', textTitle),
            _buildPermissionSwitch(
              'finance_view_reports',
              'View Plant Financial Reports',
              'Access company invoicing & payroll',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'salary_manage_increment',
              'Manage Salary Increments & Appraisals',
              'Process percentage/fixed hikes & promotion reviews',
              textTitle,
              textSub,
            ),
            _buildPermissionSwitch(
              'system_audit_logs',
              'System Security & Audit Logs',
              'Inspect admin actions and system events',
              textTitle,
              textSub,
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: _isSavingPermissions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.security_update_good_rounded, size: 18),
                label: Text(
                  _isSavingPermissions
                      ? 'Saving...'
                      : 'Save Permissions & Access',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                onPressed: _isSavingPermissions ? null : _savePermissions,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAttStatPill(
    String label,
    int count,
    Color color,
    Color cardBg,
    Color cardBorder,
    Color textSub,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textSub,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= 🕒 TAB 4: ATTENDANCE & LEAVES HISTORY =================
  Widget _buildTab4AttendanceLeaves(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final emp = _data['employee'] ?? {};
    final leavesList = (_data['leaves'] as List?) ?? [];

    final totalLogs = _employeeAttendanceList.length;
    final totalPresent = _employeeAttendanceList
        .where((r) => r['status'] == 'Present')
        .length;
    final totalLate = _employeeAttendanceList
        .where((r) => r['status'] == 'Late')
        .length;
    final totalHalfDay = _employeeAttendanceList
        .where((r) => r['status'] == 'Half-Day')
        .length;
    final totalAbsent = _employeeAttendanceList
        .where((r) => r['status'] == 'Absent')
        .length;

    int totalWorkMins = 0;
    for (final a in _employeeAttendanceList) {
      final inTime = a['check_in_time'] ??
          (a['check_in'] != null
              ? a['check_in'].toString().split('T').last.substring(0, 8)
              : null);
      final outTime = a['check_out_time'] ??
          (a['check_out'] != null
              ? a['check_out'].toString().split('T').last.substring(0, 8)
              : null);
      final m = a['work_minutes'] ?? a['work_duration_minutes'];
      final formatted = _formatWorkDuration(m, inTime, outTime);
      final rawM = int.tryParse(m?.toString() ?? '0') ?? 0;
      if (rawM > 0) {
        totalWorkMins += rawM;
      } else if (formatted.contains('h')) {
        try {
          final parts = formatted.split(' ');
          int h = 0;
          int min = 0;
          for (final p in parts) {
            if (p.endsWith('h')) h = int.parse(p.replaceAll('h', ''));
            if (p.endsWith('m')) min = int.parse(p.replaceAll('m', ''));
          }
          totalWorkMins += (h * 60 + min);
        } catch (_) {}
      }
    }
    final totalWorkHoursFormatted = totalWorkMins > 0
        ? '${totalWorkMins ~/ 60}h ${totalWorkMins % 60}m'
        : '--';

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        // Quota Balances (Responsive: 2-column grid on mobile, 3+2 on desktop)
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 650;
            if (isMobile) {
              return Column(
                children: [
                  Row(
                    children: [
                      _buildLeaveQuotaCard(
                        'Casual Leave',
                        '${emp['leave_balance_casual'] ?? 12} Days',
                        const Color(0xFF0284C7),
                        cardBg,
                        cardBorder,
                        textTitle,
                        textSub,
                      ),
                      const SizedBox(width: 8),
                      _buildLeaveQuotaCard(
                        'Sick Leave',
                        '${emp['leave_balance_sick'] ?? 8} Days',
                        const Color(0xFFD97706),
                        cardBg,
                        cardBorder,
                        textTitle,
                        textSub,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildLeaveQuotaCard(
                        'Paid / Annual',
                        '${emp['leave_balance_paid'] ?? 15} Days',
                        const Color(0xFF059669),
                        cardBg,
                        cardBorder,
                        textTitle,
                        textSub,
                      ),
                      const SizedBox(width: 8),
                      _buildLeaveQuotaCard(
                        'Unpaid (LWP)',
                        '${emp['unpaid_leaves_taken'] ?? 0} / ${emp['unpaid_leave_limit'] ?? 10} Days',
                        const Color(0xFFEA580C),
                        cardBg,
                        cardBorder,
                        textTitle,
                        textSub,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildLeaveQuotaCard(
                        'Total Salary Deduction',
                        '₹${double.tryParse((emp['total_leave_deduction'] ?? 0).toString())?.toStringAsFixed(2) ?? '0.00'}',
                        const Color(0xFFDC2626),
                        cardBg,
                        cardBorder,
                        textTitle,
                        textSub,
                      ),
                    ],
                  ),
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    _buildLeaveQuotaCard(
                      'Casual Leave',
                      '${emp['leave_balance_casual'] ?? 12} Days',
                      const Color(0xFF0284C7),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                    const SizedBox(width: 8),
                    _buildLeaveQuotaCard(
                      'Sick Leave',
                      '${emp['leave_balance_sick'] ?? 8} Days',
                      const Color(0xFFD97706),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                    const SizedBox(width: 8),
                    _buildLeaveQuotaCard(
                      'Paid / Annual',
                      '${emp['leave_balance_paid'] ?? 15} Days',
                      const Color(0xFF059669),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildLeaveQuotaCard(
                      'Unpaid Leaves Taken (LWP)',
                      '${emp['unpaid_leaves_taken'] ?? 0} / ${emp['unpaid_leave_limit'] ?? 10} Days',
                      const Color(0xFFEA580C),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                    const SizedBox(width: 8),
                    _buildLeaveQuotaCard(
                      'Total Salary Deduction',
                      '₹${double.tryParse((emp['total_leave_deduction'] ?? 0).toString())?.toStringAsFixed(2) ?? '0.00'}',
                      const Color(0xFFDC2626),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Attendance Card with Controls
        _buildFrostedSectionCard(
          title: 'Biometric Attendance Logs',
          icon: Icons.fingerprint_rounded,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textTitle: textTitle,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _attMonth,
                      dropdownColor: isDark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      style: TextStyle(color: textTitle, fontSize: 12),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('All Months'),
                        ),
                        ...List.generate(12, (i) => i + 1).map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(_attMonthNames[m - 1]),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _attMonth = val;
                            _attCustomRange = null;
                          });
                          _fetchEmployeeAttendance();
                        }
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _attYear,
                      dropdownColor: isDark
                          ? const Color(0xFF0F172A)
                          : Colors.white,
                      style: TextStyle(color: textTitle, fontSize: 12),
                      items: [2024, 2025, 2026, 2027]
                          .map(
                            (y) =>
                                DropdownMenuItem(value: y, child: Text('$y')),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _attYear = val;
                            _attCustomRange = null;
                          });
                          _fetchEmployeeAttendance();
                        }
                      },
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _attCustomRange != null
                        ? const Color(0xFF059669)
                        : textTitle,
                    side: BorderSide(
                      color: _attCustomRange != null
                          ? const Color(0xFF059669)
                          : cardBorder,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  icon: Icon(
                    Icons.date_range_rounded,
                    size: 15,
                    color: _attCustomRange != null
                        ? const Color(0xFF059669)
                        : textTitle,
                  ),
                  label: Text(
                    _attCustomRange == null
                        ? 'Custom Date'
                        : '${_attCustomRange!.start.day}/${_attCustomRange!.start.month} - ${_attCustomRange!.end.day}/${_attCustomRange!.end.month}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      initialDateRange: _attCustomRange,
                    );
                    if (picked != null) {
                      setState(() => _attCustomRange = picked);
                      _fetchEmployeeAttendance();
                    }
                  },
                ),
                if (_attCustomRange != null)
                  IconButton(
                    tooltip: 'Reset Custom Range',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() => _attCustomRange = null);
                      _fetchEmployeeAttendance();
                    },
                  ),
                IconButton(
                  tooltip: 'Refresh Attendance',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _fetchEmployeeAttendance,
                ),
              ],
            ),
            const SizedBox(height: 12),

            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 650) {
                  return const SizedBox(height: 4);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildAttStatPill(
                          'Total Logs',
                          totalLogs,
                          const Color(0xFF0284C7),
                          cardBg,
                          cardBorder,
                          textSub,
                        ),
                        _buildAttStatPill(
                          'Present',
                          totalPresent,
                          const Color(0xFF059669),
                          cardBg,
                          cardBorder,
                          textSub,
                        ),
                        _buildAttStatPill(
                          'Late',
                          totalLate,
                          const Color(0xFFF59E0B),
                          cardBg,
                          cardBorder,
                          textSub,
                        ),
                        _buildAttStatPill(
                          'Half-Day',
                          totalHalfDay,
                          const Color(0xFF8B5CF6),
                          cardBg,
                          cardBorder,
                          textSub,
                        ),
                        _buildAttStatPill(
                          'Absent',
                          totalAbsent,
                          Colors.redAccent,
                          cardBg,
                          cardBorder,
                          textSub,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: cardBorder.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),

            if (_isLoadingAttendance)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Loading attendance records...',
                        style: TextStyle(color: textSub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (_employeeAttendanceList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 40,
                        color: textSub.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No attendance records found for this period.',
                        style: TextStyle(
                          color: textTitle,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Selected: Year $_attYear • ${_attMonth == 0 ? "All Months" : _attMonthNames[_attMonth - 1]}.',
                        style: TextStyle(color: textSub, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 650;

                  // 📱 1. MOBILE ATTENDANCE VIEW (Monthly aggregated summary: Kitni baar aaya, half leaves, etc. - No table clutter)
                  if (isMobile) {
                    return _buildMobileMonthlyAttendanceView(
                      context: context,
                      totalLogs: totalLogs,
                      totalPresent: totalPresent,
                      totalHalfDay: totalHalfDay,
                      totalLate: totalLate,
                      totalAbsent: totalAbsent,
                      totalWorkHoursFormatted: totalWorkHoursFormatted,
                      isDark: isDark,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      textTitle: textTitle,
                      textSub: textSub,
                    );
                  }
                  // 💻 2. DESKTOP / TABLET VIEW (100% Full Width Table - Zero Side Gap)
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: cardBorder.withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth > 750 ? constraints.maxWidth : 750,
                          ),
                          child: Table(
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                color: cardBorder.withValues(alpha: 0.4),
                                width: 1,
                              ),
                              verticalInside: BorderSide(
                                color: cardBorder.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            columnWidths: const {
                              0: FlexColumnWidth(0.5),   // #
                              1: FlexColumnWidth(1.4),   // Work Date
                              2: FlexColumnWidth(0.8),   // Day
                              3: FlexColumnWidth(1.2),   // Check In
                              4: FlexColumnWidth(1.2),   // Check Out
                              5: FlexColumnWidth(1.1),   // Duration
                              6: FlexColumnWidth(1.0),   // Overtime
                              7: FlexColumnWidth(1.2),   // Status
                              8: FlexColumnWidth(0.8),   // Action
                            },
                            children: [
                              // 1. TABLE HEADER ROW
                              TableRow(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF1F5F9),
                                ),
                                children: [
                                  _buildTableHeaderCell('#', isDark, align: TextAlign.center),
                                  _buildTableHeaderCell('Work Date', isDark),
                                  _buildTableHeaderCell('Day', isDark),
                                  _buildTableHeaderCell('Check In', isDark),
                                  _buildTableHeaderCell('Check Out', isDark),
                                  _buildTableHeaderCell('Duration', isDark),
                                  _buildTableHeaderCell('Overtime', isDark),
                                  _buildTableHeaderCell('Status', isDark, align: TextAlign.center),
                                  _buildTableHeaderCell('Action', isDark, align: TextAlign.center),
                                ],
                              ),

                              // 2. DATA ROWS
                              ..._employeeAttendanceList.asMap().entries.map((entry) {
                                final idx = entry.key + 1;
                                final a = entry.value;

                                final rawDate = a['work_date']?.toString().split('T')[0] ?? '';
                                String dayName = '--';
                                if (rawDate.isNotEmpty) {
                                  try {
                                    final parsedDate = DateTime.parse(rawDate);
                                    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                    dayName = weekdays[parsedDate.weekday - 1];
                                  } catch (_) {}
                                }

                                final inTime = a['check_in_time'] ??
                                    (a['check_in'] != null
                                        ? a['check_in'].toString().split('T').last.substring(0, 8)
                                        : '--:--');

                                final outTime = a['check_out_time'] ??
                                    (a['check_out'] != null
                                        ? a['check_out'].toString().split('T').last.substring(0, 8)
                                        : '--:--');

                                final duration = _formatWorkDuration(
                                  a['work_minutes'] ?? a['work_duration_minutes'],
                                  inTime,
                                  outTime,
                                );

                                final status = a['status'] ?? 'Present';
                                final overtime = (a['overtime_hours'] != null &&
                                    double.tryParse(a['overtime_hours'].toString()) != null &&
                                    double.parse(a['overtime_hours'].toString()) > 0)
                                    ? '+${a['overtime_hours']}h'
                                    : '--';

                                Color statusColor = const Color(0xFF059669);
                                if (status == 'Late') statusColor = const Color(0xFFF59E0B);
                                if (status == 'Half-Day') statusColor = const Color(0xFF8B5CF6);
                                if (status == 'Absent') statusColor = Colors.redAccent;

                                final isEven = entry.key % 2 == 0;
                                final rowBg = isEven
                                    ? (isDark ? Colors.white.withValues(alpha: 0.015) : Colors.white)
                                    : (isDark ? Colors.white.withValues(alpha: 0.035) : const Color(0xFFF8FAFC));

                                return TableRow(
                                  decoration: BoxDecoration(color: rowBg),
                                  children: [
                                    // #
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      child: Text(
                                        '$idx',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    // Date
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        rawDate,
                                        style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    // Day
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      child: Text(
                                        dayName,
                                        style: TextStyle(color: textSub, fontSize: 11.5),
                                      ),
                                    ),
                                    // In Time
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        inTime,
                                        style: TextStyle(color: textTitle, fontSize: 12, fontFamily: 'monospace'),
                                      ),
                                    ),
                                    // Out Time
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        outTime,
                                        style: TextStyle(color: textTitle, fontSize: 12, fontFamily: 'monospace'),
                                      ),
                                    ),
                                    // Duration
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      child: Text(
                                        duration,
                                        style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    // Overtime
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      child: Text(
                                        overtime,
                                        style: TextStyle(
                                          color: overtime != '--' ? const Color(0xFF059669) : textSub,
                                          fontSize: 11.5,
                                          fontWeight: overtime != '--' ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    // Status Badge
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Action Override
                                    Center(
                                      child: _canOverrideAttendance
                                          ? IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 15),
                                        color: const Color(0xFF059669),
                                        tooltip: 'Override Attendance',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: () => _openEditAttendanceDialog(a),
                                      )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Recent Leaves Card
        _buildFrostedSectionCard(
          title: 'Leave Applications History',
          icon: Icons.event_note_rounded,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textTitle: textTitle,
          children: [
            leavesList.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No leave applications recorded.',
                        style: TextStyle(color: textSub, fontSize: 12),
                      ),
                    ),
                  )
                : Column(
                    children: leavesList.map((l) {
                      final type = l['leave_type'] ?? 'Leave';
                      final days = l['total_days'] ?? 1;
                      final status = (l['status'] ?? 'PENDING')
                          .toString()
                          .toUpperCase();
                      final reason = l['reason'] ?? 'Personal Reason';

                      Color stColor = const Color(0xFFD97706);
                      if (status == 'APPROVED')
                        stColor = const Color(0xFF059669);
                      if (status == 'REJECTED') stColor = Colors.redAccent;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: cardBorder.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: stColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.event_note,
                                color: stColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$type ($days Day) • $reason',
                                    style: TextStyle(
                                      color: textTitle,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Submitted Request',
                                    style: TextStyle(
                                      color: textSub,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: stColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: stColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ],
    );
  }



  // ================= 💰 TAB 5: SALARY & DYNAMIC ATTENDANCE PAYROLL =================
  Widget _buildTab5Payroll(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final emp = _data['employee'] ?? {};
    final perf = _data['performance'] ?? {};

    final double baseSalary =
        double.tryParse(emp['salary_base']?.toString() ?? '0') ?? 0.0;
    final customDeduction =
        double.tryParse(emp['unpaid_leave_per_day_deduction']?.toString() ?? '');
    final double perDayDeduction = (customDeduction != null && customDeduction > 0)
        ? customDeduction
        : (baseSalary > 0 ? (baseSalary / 30.0) : 0.0);

    final double hourlyRate =
        perDayDeduction > 0 ? (perDayDeduction / 8.0) : 0.0;

    final int totalShifts =
        int.tryParse(perf['total_shifts']?.toString() ?? '0') ?? 0;
    final int presentShifts =
        int.tryParse(perf['present_shifts']?.toString() ?? '0') ?? 0;
    final int onTimeShifts =
        int.tryParse(perf['on_time_shifts']?.toString() ?? '0') ?? 0;
    final double totalOvertime = (perf['total_overtime'] is num
        ? (perf['total_overtime'] as num).toDouble()
        : double.tryParse(perf['total_overtime']?.toString() ?? '0') ?? 0.0);
    final int approvedLeaves =
        int.tryParse(perf['approved_leave_days']?.toString() ?? '0') ?? 0;

    final int absentDays =
        (totalShifts > presentShifts) ? (totalShifts - presentShifts) : 0;
    final double totalDeduction = absentDays * perDayDeduction;
    final double overtimeEarning = totalOvertime * hourlyRate;
    final double grossEarning = baseSalary + overtimeEarning;
    final double netPayable =
        (grossEarning - totalDeduction).clamp(0.0, double.infinity);

    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        // 4 KPI Summary Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 650;

            final card1 = _buildMetricCard(
              title: 'Monthly Base Pay',
              value: baseSalary > 0
                  ? '₹${baseSalary.toStringAsFixed(0)}'
                  : 'Not Configured',
              subtitle: 'Grade: ${emp['salary_grade'] ?? 'Grade B'}',
              icon: Icons.payments_outlined,
              color: const Color(0xFF059669),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card2 = _buildMetricCard(
              title: 'Shifts & Presence',
              value: '$presentShifts / ${totalShifts > 0 ? totalShifts : 30}',
              subtitle: '${perf['attendance_rate'] ?? 100}% Shift Presence',
              icon: Icons.event_available_rounded,
              color: const Color(0xFF0284C7),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card3 = _buildMetricCard(
              title: 'Absence Cut (LWP)',
              value: '-₹${totalDeduction.toStringAsFixed(2)}',
              subtitle: '$absentDays Days Unpaid',
              icon: Icons.money_off_csred_rounded,
              color: const Color(0xFFDC2626),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            final card4 = _buildMetricCard(
              title: 'Net In-Hand Payable',
              value: '₹${netPayable.toStringAsFixed(2)}',
              subtitle: 'Disbursable Payout',
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFF10B981),
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              textSub: textSub,
            );

            if (isMobile) {
              return Column(
                children: [
                  Row(children: [card1, const SizedBox(width: 10), card2]),
                  const SizedBox(height: 10),
                  Row(children: [card3, const SizedBox(width: 10), card4]),
                ],
              );
            }

            return Row(
              children: [
                card1,
                const SizedBox(width: 12),
                card2,
                const SizedBox(width: 12),
                card3,
                const SizedBox(width: 12),
                card4,
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // 2 Side-by-Side Breakdown Cards (Desktop) or Stacked (Mobile)
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 750;

            final cardStructure = _buildFrostedSectionCard(
              title: 'Salary Structure & Earning Policy',
              icon: Icons.receipt_long_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              trailing: _canManageStaff
                  ? IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Color(0xFF059669),
                      ),
                      tooltip: 'Edit Base Salary',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: _openEditDetailsDialog,
                    )
                  : null,
              children: [
                _buildDetailRow(
                  'Salary Grade',
                  emp['salary_grade'] ?? 'Grade B',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Base Monthly Salary',
                  baseSalary > 0
                      ? '₹${baseSalary.toStringAsFixed(2)} / month'
                      : 'Not Set',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Standard Payroll Cycle',
                  '30 Days (Monthly Calendar)',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Per-Day Earning Rate',
                  '₹${perDayDeduction.toStringAsFixed(2)} / day',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Overtime Rate (1.0x)',
                  '₹${hourlyRate.toStringAsFixed(2)} / hour',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Overtime Incentive Logged',
                  '+₹${overtimeEarning.toStringAsFixed(2)} (${totalOvertime}h logged)',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Estimated Annual CTC',
                  '₹${(baseSalary * 12).toStringAsFixed(2)} / year',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Payment Disbursement Mode',
                  'Direct Bank Transfer (NEFT/RTGS)',
                  textTitle,
                  textSub,
                ),
              ],
            );

            final cardDeductions = _buildFrostedSectionCard(
              title: 'Attendance & Leave Linked Deductions',
              icon: Icons.rule_folder_outlined,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textTitle: textTitle,
              children: [
                _buildDetailRow(
                  'Total Shift Records',
                  '$totalShifts machine check-ins',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Present On Duty',
                  '$presentShifts shifts logged',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'On-Time Punctuality',
                  '$onTimeShifts / $totalShifts shifts (${perf['punctuality_rate'] ?? 100}%)',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Approved Paid Leaves',
                  '$approvedLeaves Days (₹0.00 Cut - Company Paid)',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Unpaid Absences (LWP)',
                  '$absentDays Days',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Daily Deduction Rate Applied',
                  '₹${perDayDeduction.toStringAsFixed(2)} / day',
                  textTitle,
                  textSub,
                ),
                _buildDetailRow(
                  'Total Loss of Pay Deduction',
                  '-₹${totalDeduction.toStringAsFixed(2)}',
                  const Color(0xFFDC2626),
                  textSub,
                ),
              ],
            );

            if (isMobile) {
              return Column(
                children: [
                  cardStructure,
                  const SizedBox(height: 16),
                  cardDeductions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cardStructure),
                const SizedBox(width: 16),
                Expanded(child: cardDeductions),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Payslip Payout Summary Box
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF059669).withValues(alpha: 0.4)
                      : const Color(0xFF059669).withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.fact_check_outlined,
                              color: Color(0xFF059669),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monthly Payroll Calculation Statement',
                                style: TextStyle(
                                  color: textTitle,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dynamically computed based on real machine punches & leave records',
                                style: TextStyle(
                                  color: textSub,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF059669).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF059669)),
                            SizedBox(width: 5),
                            Text(
                              'Auto-Computed Payout',
                              style: TextStyle(
                                color: Color(0xFF059669),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          'Gross Base Pay (Monthly)',
                          '₹${baseSalary.toStringAsFixed(2)}',
                          textTitle,
                          textSub,
                        ),
                        _buildDetailRow(
                          '(+) Overtime Earnings',
                          '+₹${overtimeEarning.toStringAsFixed(2)}',
                          const Color(0xFF059669),
                          textSub,
                        ),
                        _buildDetailRow(
                          '(-) Loss of Pay / Absence Deductions',
                          '-₹${totalDeduction.toStringAsFixed(2)}',
                          const Color(0xFFDC2626),
                          textSub,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(color: cardBorder, height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Net In-Hand Payable Salary',
                              style: TextStyle(
                                color: textTitle,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${netPayable.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF059669),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================= 🎨 UI HELPER BUILDERS =================
  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: textTitle,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: textSub, fontSize: 10.5, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedSectionCard({
    required String title,
    required IconData icon,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: const Color(0xFF059669), size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          color: textTitle,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    Color textTitle,
    Color textSub, {
    Widget? customValue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: textSub.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          if (customValue != null)
            customValue
          else
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: textTitle,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaveQuotaProgressBar({
    required String title,
    required int current,
    required int total,
    required Color color,
    required Color textTitle,
    required Color textSub,
  }) {
    final double pct = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w500)),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$current / $total ',
                      style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: 'Days Left',
                      style: TextStyle(color: textSub, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMeta(IconData icon, String label, Color textSub) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: textSub),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: textSub, fontSize: 11.5)),
      ],
    );
  }

  Widget _buildPermissionCategory(String title, Color textTitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 6.0),
      child: Text(
        title,
        style: TextStyle(
          color: textTitle,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPermissionSwitch(
    String key,
    String title,
    String subtitle,
    Color textTitle,
    Color textSub,
  ) {
    final isAllowed = _permissions[key] ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textTitle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: textSub, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Switch(
            value: isAllowed,
            activeColor: const Color(0xFF059669),
            onChanged: _canManageStaff
                ? (val) {
                    setState(() {
                      _permissions[key] = val;
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMonthlyStatTile(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.08) : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: textTitle,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Days',
                style: TextStyle(
                  color: textSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: textSub.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMonthlyAttendanceView({
    required BuildContext context,
    required int totalLogs,
    required int totalPresent,
    required int totalHalfDay,
    required int totalLate,
    required int totalAbsent,
    required String totalWorkHoursFormatted,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
  }) {
    final periodName = _attCustomRange != null
        ? '${_attCustomRange!.start.day}/${_attCustomRange!.start.month} - ${_attCustomRange!.end.day}/${_attCustomRange!.end.month} $_attYear'
        : (_attMonth == 0 ? 'Full Year $_attYear' : '${_attMonthNames[_attMonth - 1]} $_attYear');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_available_rounded, size: 16, color: Color(0xFF059669)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$periodName Summary',
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Monthly Attendance Breakdown',
                      style: TextStyle(color: textSub, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$totalPresent Days In',
                  style: const TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildMobileMonthlyStatTile(
                  'Present Days',
                  '$totalPresent',
                  'Pura Din Aaye',
                  Icons.check_circle_rounded,
                  const Color(0xFF059669),
                  textTitle,
                  textSub,
                  isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMobileMonthlyStatTile(
                  'Half-Day Leaves',
                  '$totalHalfDay',
                  'Aadhe Din Leave',
                  Icons.hourglass_bottom_rounded,
                  const Color(0xFF8B5CF6),
                  textTitle,
                  textSub,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMobileMonthlyStatTile(
                  'Late Arrivals',
                  '$totalLate',
                  'Der Se Aaye',
                  Icons.access_time_filled_rounded,
                  const Color(0xFFF59E0B),
                  textTitle,
                  textSub,
                  isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMobileMonthlyStatTile(
                  'Absent Days',
                  '$totalAbsent',
                  'Gair-hazir Din',
                  Icons.cancel_rounded,
                  Colors.redAccent,
                  textTitle,
                  textSub,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  'Total Working Hours: ',
                  style: TextStyle(color: textSub, fontSize: 12),
                ),
                Text(
                  totalWorkHoursFormatted,
                  style: TextStyle(
                    color: textTitle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '$totalLogs Logs',
                  style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF059669),
                side: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: Text(
                'View Daily Punch History ($totalLogs Records)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _openMobileAttendanceBottomSheet(
                context,
                isDark,
                cardBg,
                cardBorder,
                textTitle,
                textSub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openMobileAttendanceBottomSheet(
    BuildContext context,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 18, color: Color(0xFF059669)),
                        const SizedBox(width: 8),
                        Text(
                          'Daily Punch Logs (${_employeeAttendanceList.length})',
                          style: TextStyle(
                            color: textTitle,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cardBorder.withValues(alpha: 0.5)),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(14),
                      itemCount: _employeeAttendanceList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (c, index) {
                        final a = _employeeAttendanceList[index];
                        final rawDate = a['work_date']?.toString().split('T')[0] ?? '';
                        String dayName = '--';
                        if (rawDate.isNotEmpty) {
                          try {
                            final parsedDate = DateTime.parse(rawDate);
                            const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                            dayName = weekdays[parsedDate.weekday - 1];
                          } catch (_) {}
                        }

                        final inTime = a['check_in_time'] ??
                            (a['check_in'] != null
                                ? a['check_in'].toString().split('T').last.substring(0, 8)
                                : '--:--');

                        final outTime = a['check_out_time'] ??
                            (a['check_out'] != null
                                ? a['check_out'].toString().split('T').last.substring(0, 8)
                                : '--:--');

                        final duration = _formatWorkDuration(
                          a['work_minutes'] ?? a['work_duration_minutes'],
                          inTime,
                          outTime,
                        );

                        final status = a['status'] ?? 'Present';
                        final overtime = (a['overtime_hours'] != null &&
                            double.tryParse(a['overtime_hours'].toString()) != null &&
                            double.parse(a['overtime_hours'].toString()) > 0)
                            ? '+${a['overtime_hours']}h'
                            : null;

                        Color statusColor = const Color(0xFF059669);
                        if (status == 'Late') statusColor = const Color(0xFFF59E0B);
                        if (status == 'Half-Day') statusColor = const Color(0xFF8B5CF6);
                        if (status == 'Absent') statusColor = Colors.redAccent;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.035) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder.withValues(alpha: 0.7)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF059669)),
                                  const SizedBox(width: 6),
                                  Text(
                                    rawDate,
                                    style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('($dayName)', style: TextStyle(color: textSub, fontSize: 11.5)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (_canOverrideAttendance) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      color: const Color(0xFF059669),
                                      tooltip: 'Override Attendance',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _openEditAttendanceDialog(a);
                                      },
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: cardBorder.withValues(alpha: 0.45)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildMobileAttMetric('In Time', inTime, Icons.login_rounded, const Color(0xFF059669), textTitle, textSub),
                                    Container(width: 1, height: 24, color: cardBorder.withValues(alpha: 0.35)),
                                    _buildMobileAttMetric('Out Time', outTime, Icons.logout_rounded, const Color(0xFFD97706), textTitle, textSub),
                                    Container(width: 1, height: 24, color: cardBorder.withValues(alpha: 0.35)),
                                    _buildMobileAttMetric('Duration', duration, Icons.timer_outlined, const Color(0xFF2563EB), textTitle, textSub),
                                    if (overtime != null) ...[
                                      Container(width: 1, height: 24, color: cardBorder.withValues(alpha: 0.35)),
                                      _buildMobileAttMetric('Overtime', overtime, Icons.add_circle_outline_rounded, const Color(0xFF10B981), textTitle, textSub),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileAttMetric(
    String label,
    String value,
    IconData icon,
    Color iconColor,
    Color textTitle,
    Color textSub,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: iconColor),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(color: textSub, fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: textTitle,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveQuotaCard(
    String type,
    String quota,
    Color color,
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              type,
              style: TextStyle(color: textSub, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              quota,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    bool isDark, {
    bool required = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label${required ? " *" : ""}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          validator: required
              ? (v) => v!.trim().isEmpty ? '$label is required' : null
              : null,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontSize: 12.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white30 : Colors.black38,
              fontSize: 11.5,
            ),
            prefixIcon: Icon(
              icon,
              color: isDark ? Colors.white54 : Colors.black45,
              size: 16,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
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
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              icon: Icon(
                Icons.arrow_drop_down,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 12.5,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

Widget _buildTableHeaderCell(String text, bool isDark, {TextAlign align = TextAlign.start}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    child: Text(
      text,
      textAlign: align,
      style: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
  );
}

// 📌 Helper Delegate for Smooth Sticky Header in NestedScrollView
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  _SliverTabBarDelegate(
    this.child, {
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
