import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../../core/network/session_manager.dart';
import '../../core/widgets/searchable_employee_dropdown.dart';

class LeaveManagementScreen extends StatefulWidget {
  const LeaveManagementScreen({super.key});

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  List<dynamic> _leaves = [];
  List<dynamic> _employees = [];
  bool _isLoading = true;
  bool _canApplyLeave = false;
  bool _canApproveLeave = false;
  int? _currentUserId;
  String _currentUserRole = '';

  @override
  void initState() {
    super.initState();
    _loadPermissions(); // 👈 Call permission loader
    _fetchLeaves();
    _fetchEmployees();
  }

  Future<void> _loadPermissions() async {
    final session = await SessionManager.getUserSession();
    final canApply = await SessionManager.hasPermission('leaves_apply');
    final canApprove = await SessionManager.hasPermission('leaves_approve');
    if (mounted) {
      setState(() {
        _currentUserId = session['userId'];
        _currentUserRole = session['role'] ?? '';
        _canApplyLeave = canApply;
        _canApproveLeave = canApprove;
      });
    }
  }

  // 1. Backend se Leaves mangwana (Role-Based Filtered)
  Future<void> _fetchLeaves() async {
    try {
      final session = await SessionManager.getUserSession();
      final currentUserId = session['userId'];
      final role = session['role'] ?? '';
      final canApprove = await SessionManager.hasPermission('leaves_approve');
      final isApproverOrAdmin = role == 'Super Admin' || canApprove;

      String url = 'http://localhost:5000/api/hr/leaves';
      // Regular employee ko sirf apni leaves aayengi:
      if (!isApproverOrAdmin && currentUserId != null) {
        url += '?user_id=$currentUserId';
      }

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _leaves = data['data'] ?? [];
          });
        }
      } else {
        debugPrint('Fetch leaves failed with code: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching leaves: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper: Display leaves list (Approver gets all, Employee gets only own leaves)
  List<dynamic> get _displayLeaves {
    final isApproverOrAdmin = _currentUserRole == 'Super Admin' || _canApproveLeave;
    if (isApproverOrAdmin) {
      return _leaves;
    }
    return _leaves.where((l) {
      if (_currentUserId == null) return true;
      return l['user_id'] == _currentUserId;
    }).toList();
  }

  // 2. Employees mangwana (Apply leave ke dropdown ke liye)
  Future<void> _fetchEmployees() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _employees = data['data'] ?? [];
          });
        }
      }
    } catch (_) {}
  }

  // 3. Leave Approve ya Reject karna
  Future<void> _updateStatus(int leaveId, String status) async {
    try {
      final session = await SessionManager.getUserSession();
      final currentUserId = session['userId'] ?? 1;

      final res = await http.put(
        Uri.parse('http://localhost:5000/api/hr/leaves/$leaveId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status, 'approved_by': currentUserId}),
      );

      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Status updated'),
            backgroundColor: status == 'APPROVED' ? const Color(0xFF059669) : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchLeaves(); // Refresh list
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  // 3.1 Leave Delete karna (Confirmation Popup ke sath)
  void _confirmDeleteLeave(int leaveId) {
    final isDark = ThemeController.isDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white70 : const Color(0xFF64748B);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text('Delete Leave Application', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete this leave application? This action cannot be undone.',
          style: TextStyle(color: textSub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteLeave(leaveId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLeave(int leaveId) async {
    try {
      final res = await http.delete(Uri.parse('http://localhost:5000/api/hr/leaves/$leaveId'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave application deleted successfully.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _fetchLeaves(); // List refresh
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server Error (${res.statusCode}): Please restart backend server.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // 4. Nayi Leave Apply karne ka Popup Form (With Start Date, End Date & Total Days)
  void _showApplyLeaveDialog() {
    final isApproverOrAdmin = _currentUserRole == 'Super Admin' || _canApproveLeave;
    dynamic myEmp;
    try {
      myEmp = _employees.firstWhere((e) => e['user_id'] == _currentUserId, orElse: () => null);
    } catch (_) {}

    int? selectedEmpId = (!isApproverOrAdmin && myEmp != null)
        ? myEmp['employee_id']
        : (_employees.isNotEmpty ? _employees[0]['employee_id'] : null);
    String selectedType = 'Casual Leave';
    final reasonCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? Colors.white70 : const Color(0xFF64748B);
          final inputBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC);
          final inputBorder = isDark ? Colors.white24 : const Color(0xFFCBD5E1);
          final totalDays = endDate.difference(startDate).inDays + 1;

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF059669).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.event_available_rounded, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 10),
                Text('Apply Employee Leave', style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee Selection (Admin/Manager chooses staff, Regular Employee applies for self)
                    if (isApproverOrAdmin) ...[
                      Text('Select Employee', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SearchableEmployeeDropdown(
                        employees: _employees,
                        selectedEmployeeId: selectedEmpId,
                        onChanged: (emp) {
                          setModalState(() {
                            selectedEmpId = emp['employee_id'];
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                myEmp != null ? '${myEmp['full_name']} (${myEmp['emp_code'] ?? 'EMP'})' : 'Applying for Self',
                                style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Leave Type Dropdown
                    Text('Leave Type', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: inputBorder),
                      ),
                      child: DropdownButton<String>(
                        value: selectedType,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        iconEnabledColor: textTitle,
                        underline: const SizedBox(),
                        style: TextStyle(color: textTitle, fontSize: 13),
                        items: ['Casual Leave', 'Sick Leave', 'Paid Leave', 'Unpaid Leave'].map((t) {
                          return DropdownMenuItem<String>(
                            value: t,
                            child: Text(t, style: TextStyle(color: textTitle)),
                          );
                        }).toList(),
                        onChanged: (val) => setModalState(() => selectedType = val ?? selectedType),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 📅 START DATE & END DATE PICKERS
                    Row(
                      children: [
                        // Start Date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Start Date', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: startDate,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    setModalState(() {
                                      startDate = picked;
                                      if (endDate.isBefore(startDate)) endDate = picked;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: inputBg,
                                    border: Border.all(color: inputBorder),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF10B981)),
                                      const SizedBox(width: 8),
                                      Text(
                                        startDate.toIso8601String().split('T')[0],
                                        style: TextStyle(color: textTitle, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // End Date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('End Date', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                                    firstDate: startDate,
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    setModalState(() => endDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: inputBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: inputBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.event_repeat_rounded, size: 14, color: Color(0xFF10B981)),
                                      const SizedBox(width: 8),
                                      Text(
                                        endDate.toIso8601String().split('T')[0],
                                        style: TextStyle(color: textTitle, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Total Days Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Duration: $totalDays ${totalDays == 1 ? "Day" : "Days"}',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Live Connected Paid vs Unpaid Calculation Preview
                    Builder(
                      builder: (context) {
                        final dynamic selectedEmp = _employees.firstWhere(
                          (e) => e['employee_id'] == selectedEmpId,
                          orElse: () => null,
                        );

                        final casual = selectedEmp != null ? (selectedEmp['leave_balance_casual'] ?? 12) : 12;
                        final sick = selectedEmp != null ? (selectedEmp['leave_balance_sick'] ?? 8) : 8;
                        final paid = selectedEmp != null ? (selectedEmp['leave_balance_paid'] ?? 15) : 15;
                        final totalPaidLeft = (casual is int ? casual : int.tryParse(casual.toString()) ?? 12) +
                                              (sick is int ? sick : int.tryParse(sick.toString()) ?? 8) +
                                              (paid is int ? paid : int.tryParse(paid.toString()) ?? 15);

                        double rate = 1166.67;
                        if (selectedEmp != null && selectedEmp['unpaid_leave_per_day_deduction'] != null) {
                          rate = double.tryParse(selectedEmp['unpaid_leave_per_day_deduction'].toString()) ?? 1166.67;
                        }

                        final isUnpaidType = selectedType.toLowerCase().contains('unpaid');
                        final paidDaysCovered = isUnpaidType ? 0 : (totalDays <= totalPaidLeft ? totalDays : totalPaidLeft);
                        final unpaidDaysCount = totalDays - paidDaysCovered;
                        final totalDeduction = unpaidDaysCount * rate;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: unpaidDaysCount == 0
                                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: unpaidDaysCount == 0
                                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    unpaidDaysCount == 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                                    size: 16,
                                    color: unpaidDaysCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Connected Quota Status',
                                    style: TextStyle(
                                      color: textTitle,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Remaining Paid Quotas: Casual: $casual | Sick: $sick | Annual: $paid (Total: $totalPaidLeft Days)',
                                style: TextStyle(color: textSub, fontSize: 11),
                              ),
                              const SizedBox(height: 6),
                              if (unpaidDaysCount == 0)
                                Text(
                                  '✅ 100% Paid Leave: All $totalDays day(s) will be deducted from Paid Leave balance. ₹0.00 salary deduction.',
                                  style: const TextStyle(color: Color(0xFF059669), fontSize: 11.5, fontWeight: FontWeight.bold),
                                )
                              else if (paidDaysCovered > 0)
                                Text(
                                  '⚠️ Split Deduction: $paidDaysCovered day(s) covered by Paid Leaves. Remaining $unpaidDaysCount day(s) will become Unpaid Leave (LWP) with ₹${totalDeduction.toStringAsFixed(2)} salary deduction.',
                                  style: const TextStyle(color: Color(0xFFD97706), fontSize: 11.5, fontWeight: FontWeight.bold),
                                )
                              else
                                Text(
                                  '🔴 Unpaid Leave (LWP): Paid balance exhausted. All $totalDays day(s) are Unpaid with ₹${totalDeduction.toStringAsFixed(2)} salary deduction.',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // Reason Text
                    Text('Reason', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      style: TextStyle(color: textTitle, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Urgent family matter / Fever',
                        hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
                        filled: true,
                        fillColor: inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: textSub, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(isSubmitting ? 'Submitting...' : 'Submit Application'),
                onPressed: (selectedEmpId == null || isSubmitting)
                    ? null
                    : () async {
                  setModalState(() => isSubmitting = true);
                  final payload = {
                    'company_id': 1,
                    'employee_id': selectedEmpId,
                    'leave_type': selectedType,
                    'start_date': startDate.toIso8601String().split('T')[0],
                    'end_date': endDate.toIso8601String().split('T')[0],
                    'total_days': totalDays,
                    'reason': reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : 'Personal Leave',
                  };

                  try {
                    final res = await http.post(
                      Uri.parse('http://localhost:5000/api/hr/leaves'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(payload),
                    );

                    if (res.statusCode == 201) {
                      Navigator.pop(ctx);
                      _fetchLeaves();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Leave application submitted & notified to Admin!'),
                            backgroundColor: Color(0xFF059669),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } else {
                      setModalState(() => isSubmitting = false);
                      String errorMsg = 'Failed to apply leave (${res.statusCode})';
                      try {
                        final errData = jsonDecode(res.body);
                        if (errData is Map && errData['message'] != null) {
                          errorMsg = errData['message'].toString();
                          if (errData['error'] != null) {
                            errorMsg += ': ${errData['error']}';
                          }
                        }
                      } catch (_) {}
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMsg),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    setModalState(() => isSubmitting = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF475569);
    final cardBg = isDark ? const Color(0xFF030D08).withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.7);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.75);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            children: [
              // 1. TOP HEADER BANNER (Responsive Mobile Layout)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 650;

                    final applyButton = _canApplyLeave
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Apply Leave', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            ),
                            onPressed: _showApplyLeaveDialog,
                          )
                        : null;

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back_rounded, color: textTitle),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Leave Management',
                                  style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 48, bottom: 8),
                            child: Text(
                              'Approve, reject, and review factory staff leave requests',
                              style: TextStyle(color: textSub, fontSize: 11),
                            ),
                          ),
                          if (applyButton != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: applyButton,
                            ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: textTitle),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Leave Management & Approvals', style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Approve, reject, and review factory staff leave requests', style: TextStyle(color: textSub, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        if (applyButton != null) applyButton,
                      ],
                    );
                  },
                ),
              ),

              // 2. CONTENT BODY
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                    : _displayLeaves.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_available_outlined, size: 64, color: textSub.withValues(alpha: 0.3)),
                                const SizedBox(height: 14),
                                Text('No leave applications found', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('Click "+ Apply Leave" to create a new leave request.', style: TextStyle(color: textSub, fontSize: 12)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _displayLeaves.length,
                            itemBuilder: (context, index) {
                              final leave = _displayLeaves[index];
                              return _buildLeaveCard(leave, cardBg, cardBorder, textTitle, textSub, isDark);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveCard(dynamic leave, Color cardBg, Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    final status = (leave['status'] ?? 'PENDING').toString().toUpperCase();
    final isPending = status == 'PENDING';
    final isOwnLeave = _currentUserId != null && leave['user_id'] == _currentUserId;
    final canDeleteThis = _canApproveLeave || _currentUserRole == 'Super Admin' || isOwnLeave;

    Color statusColor;
    if (status == 'APPROVED') {
      statusColor = const Color(0xFF10B981);
    } else if (status == 'REJECTED') {
      statusColor = Colors.redAccent;
    } else {
      statusColor = const Color(0xFFF59E0B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar + Name & Code + Status Badge + Delete icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                      child: const Icon(Icons.person_outline_rounded, color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(leave['full_name'] ?? 'Staff', style: TextStyle(color: textTitle, fontSize: 14.5, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(leave['emp_code'] ?? 'EMP', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_canApproveLeave && !isPending) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Change Decision',
                        icon: Icon(Icons.more_vert_rounded, color: textSub, size: 18),
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        onSelected: (newStatus) => _updateStatus(leave['leave_id'], newStatus),
                        itemBuilder: (ctx) => [
                          if (status != 'APPROVED')
                            const PopupMenuItem(
                              value: 'APPROVED',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                  SizedBox(width: 8),
                                  Text('Approve', style: TextStyle(fontSize: 12.5)),
                                ],
                              ),
                            ),
                          if (status != 'REJECTED')
                            const PopupMenuItem(
                              value: 'REJECTED',
                              child: Row(
                                children: [
                                  Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 16),
                                  SizedBox(width: 8),
                                  Text('Reject', style: TextStyle(fontSize: 12.5)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (canDeleteThis) ...[
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: 'Delete Application',
                        onPressed: () => _confirmDeleteLeave(leave['leave_id']),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Middle Info: Leave Type & Dates
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${leave['leave_type']}',
                        style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${leave['total_days']} Days (${leave['start_date']?.toString().split('T')[0]} → ${leave['end_date']?.toString().split('T')[0]})',
                      style: TextStyle(color: textSub, fontSize: 11.5),
                    ),
                    // Connected Paid vs Unpaid status badge
                    Builder(
                      builder: (context) {
                        final unpaidDays = leave['unpaid_days'] ?? 0;
                        final paidDays = leave['paid_days'] ?? leave['total_days'];
                        final deduction = double.tryParse((leave['deduction_amount'] ?? 0).toString()) ?? 0.0;

                        if (unpaidDays == 0) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                            ),
                            child: const Text('🟢 Paid Leave (₹0 Cut)', style: TextStyle(color: Color(0xFF059669), fontSize: 10.5, fontWeight: FontWeight.bold)),
                          );
                        } else if (paidDays > 0) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                            ),
                            child: Text('🟡 $paidDays Paid + $unpaidDays Unpaid (₹${deduction.toStringAsFixed(0)} Cut)', style: const TextStyle(color: Color(0xFFD97706), fontSize: 10.5, fontWeight: FontWeight.bold)),
                          );
                        } else {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                            ),
                            child: Text('🔴 Unpaid LWP (₹${deduction.toStringAsFixed(0)} Cut)', style: const TextStyle(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          );
                        }
                      },
                    ),
                  ],
                ),
                if (leave['reason'] != null && leave['reason'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reason: "${leave['reason']}"',
                    style: TextStyle(color: textSub, fontSize: 11.5, fontStyle: FontStyle.italic),
                  ),
                ],

                // Action Buttons for PENDING leaves (Mobile Responsive Row)
                if (_canApproveLeave && isPending) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_rounded, size: 15),
                          label: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _updateStatus(leave['leave_id'], 'APPROVED'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 15),
                          label: const Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _updateStatus(leave['leave_id'], 'REJECTED'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
