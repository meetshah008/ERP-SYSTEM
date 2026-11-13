import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import 'employee_details_screen.dart';
import 'employee_onboarding_screen.dart';
import 'departments_screen.dart';
import '../../core/network/session_manager.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  bool _canManageStaff = false;
  bool _canViewLifecycle = false;
  int? _currentUserId;
  List<dynamic> _employees = [];
  List<dynamic> _departments = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // 'ALL', 'active', 'suspended', 'terminated'
  int? _selectedDepartmentId; // null = All Departments, -1 = Unassigned
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchEmployees();
  }

  Future<void> _checkPermissions() async {
    final allowedStaff = await SessionManager.hasPermission('hr_manage_staff');
    final allowedLifecycle = await SessionManager.hasPermission('hr_view_lifecycle');
    final session = await SessionManager.getUserSession();
    if (mounted) {
      setState(() {
        _canManageStaff = allowedStaff;
        _canViewLifecycle = allowedLifecycle;
        _currentUserId = session['userId'];
      });
    }
  }

  // 1. Fetch All Employees & Departments from Backend
  Future<void> _fetchEmployees() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _employees = data['data'] ?? [];
      }
      try {
        final deptRes = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
        if (deptRes.statusCode == 200) {
          final deptData = jsonDecode(deptRes.body);
          _departments = deptData['data'] ?? [];
        }
      } catch (_) {}
      setState(() => _isLoading = false);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // 1.1 Unique Dynamic Departments List
  List<Map<String, dynamic>> get _availableDepartments {
    final Map<int, Map<String, dynamic>> map = {};
    for (var d in _departments) {
      final id = int.tryParse(d['department_id']?.toString() ?? '');
      if (id != null) {
        map[id] = {
          'id': id,
          'name': d['name'] ?? 'Dept $id',
        };
      }
    }
    for (var e in _employees) {
      final id = int.tryParse(e['department_id']?.toString() ?? '');
      if (id != null && !map.containsKey(id)) {
        map[id] = {
          'id': id,
          'name': e['department_name'] ?? 'Dept $id',
        };
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    return list;
  }

  int get _departmentFilteredCount {
    if (_selectedDepartmentId == null) return _employees.length;
    if (_selectedDepartmentId == -1) {
      return _employees.where((e) => e['department_id'] == null).length;
    }
    return _employees.where((e) => int.tryParse(e['department_id']?.toString() ?? '') == _selectedDepartmentId).length;
  }

  // 2. Filtered List (Department + Status + Live Search)
  List<dynamic> get _filteredEmployees {
    final query = _searchQuery.trim().toLowerCase();

    return _employees.where((e) {
      // 1. Department Filter
      if (_selectedDepartmentId != null) {
        if (_selectedDepartmentId == -1) {
          if (e['department_id'] != null) return false;
        } else {
          final deptId = int.tryParse(e['department_id']?.toString() ?? '');
          if (deptId != _selectedDepartmentId) return false;
        }
      }

      // 2. Status Filter
      final status = (e['status'] ?? 'active').toString().toLowerCase();
      if (_selectedFilter != 'ALL' && status != _selectedFilter.toLowerCase()) {
        return false;
      }

      // 3. Live Search Filter
      if (query.isNotEmpty) {
        final name = (e['full_name'] ?? '').toString().toLowerCase();
        final code = (e['emp_code'] ?? '').toString().toLowerCase();
        final bio = (e['biometric_emp_code'] ?? '').toString().toLowerCase();
        final desig = (e['designation'] ?? '').toString().toLowerCase();
        final dept = (e['department_name'] ?? '').toString().toLowerCase();
        final role = (e['role_name'] ?? e['role'] ?? '').toString().toLowerCase();
        final phone = (e['phone'] ?? '').toString().toLowerCase();
        final email = (e['email'] ?? '').toString().toLowerCase();

        return name.contains(query) ||
            code.contains(query) ||
            bio.contains(query) ||
            desig.contains(query) ||
            dept.contains(query) ||
            role.contains(query) ||
            phone.contains(query) ||
            email.contains(query);
      }

      return true;
    }).toList();
  }

  // 3. Open Add Employee Full Screen (Zero Popups)
  void _openAddEmployeeScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeOnboardingScreen(
          departments: _departments,
          onEmployeeAdded: _fetchEmployees,
        ),
      ),
    );
    if (result == true) {
      _fetchEmployees();
    }
  }


  // 4. MANAGE LIFECYCLE (TERMINATE / BAN ACCESS / ACTIVATE)
  
  // 4.1 CHANGE EMPLOYEE ROLE (Promote to Manager / Admin / Employee)
  void _showChangeRoleDialog(dynamic emp) {
    if (!_canManageStaff) return;
    final isDark = ThemeController.isDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);

    String currentRole = (emp['role_name'] ?? emp['role'] ?? 'Employee').toString();
    String selectedRole = currentRole;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF3B82F6), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Change System Role', style: TextStyle(color: titleColor, fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('${emp['full_name']} (${emp['emp_code'] ?? 'EMP'})', style: TextStyle(color: textSub, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select the role and operational authority for this user:', style: TextStyle(color: textSub, fontSize: 13)),
                  const SizedBox(height: 16),
                  _buildRoleRadioTile(
                    title: 'Module Manager',
                    subtitle: 'Full access to supervise department, staff, biometric attendance, and task workflows.',
                    value: 'Module Manager',
                    groupValue: selectedRole,
                    icon: Icons.shield_rounded,
                    color: const Color(0xFF2563EB),
                    isDark: isDark,
                    onTap: () => setDialogState(() => selectedRole = 'Module Manager'),
                  ),
                  const SizedBox(height: 10),
                  _buildRoleRadioTile(
                    title: 'Employee',
                    subtitle: 'Standard workforce access. Can view assigned jobs, logs, and apply leaves.',
                    value: 'Employee',
                    groupValue: selectedRole,
                    icon: Icons.badge_outlined,
                    color: const Color(0xFF059669),
                    isDark: isDark,
                    onTap: () => setDialogState(() => selectedRole = 'Employee'),
                  ),
                  const SizedBox(height: 10),
                  _buildRoleRadioTile(
                    title: 'Super Admin',
                    subtitle: 'Full workspace administrator with all executive and management permissions.',
                    value: 'Super Admin',
                    groupValue: selectedRole,
                    icon: Icons.admin_panel_settings_rounded,
                    color: const Color(0xFF8B5CF6),
                    isDark: isDark,
                    onTap: () => setDialogState(() => selectedRole = 'Super Admin'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: textSub)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSaving ? null : () async {
                  setDialogState(() => isSaving = true);
                  try {
                    final res = await http.put(
                      Uri.parse('http://localhost:5000/api/hr/employees/${emp['employee_id']}/role'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'role_name': selectedRole}),
                    );
                    if (!context.mounted) return;
                    if (res.statusCode == 200) {
                      Navigator.pop(ctx);
                      _fetchEmployees();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${emp['full_name']} role updated to $selectedRole successfully!'),
                          backgroundColor: const Color(0xFF059669),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => isSaving = false);
                  }
                },
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Role Change'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoleRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : (isDark ? Colors.white38 : Colors.black38),
              size: 20,
            ),
          ],
        ),
      ),
    );
}

  void _showLifecycleDialog(dynamic emp) {
    if (!_canManageStaff) return;
    final isDark = ThemeController.isDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 24),
            const SizedBox(width: 10),
            Text('Manage Access & Lifecycle', style: TextStyle(color: titleColor, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Employee: ${emp['full_name']} (${emp['emp_code']})', style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14)),
            Text('Current Status: ${(emp['status'] ?? 'active').toString().toUpperCase()}', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12.5)),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Reason for action (e.g. Resigned / Disciplinary / Resumed work)',
                hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 12),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Choose Action:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 10),

            // Button 1: Re-Activate
            if (emp['status'] != 'active')
              ListTile(
                dense: true,
                tileColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                title: const Text('Re-Activate Employee', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                subtitle: const Text('Restore system login and active workplace status', style: TextStyle(fontSize: 11)),
                onTap: () => _updateStatusApi(emp['employee_id'], 'active', reasonCtrl.text.trim(), ctx),
              ),

            // Button 2: Suspend / Ban
            if (emp['status'] == 'active') ...[
              ListTile(
                dense: true,
                tileColor: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.lock_person_outlined, color: Color(0xFFF59E0B)),
                title: const Text('Suspend / Ban System Access', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                subtitle: const Text('Temporarily lock out from mobile app and portal', style: TextStyle(fontSize: 11)),
                onTap: () => _updateStatusApi(emp['employee_id'], 'suspended', reasonCtrl.text.trim(), ctx),
              ),
              const SizedBox(height: 8),

              // Button 3: Terminate
              ListTile(
                dense: true,
                tileColor: Colors.redAccent.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.person_off_outlined, color: Colors.redAccent),
                title: const Text('Terminate Employment (Exit)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                subtitle: const Text('Permanently relieve from company and revoke credentials', style: TextStyle(fontSize: 11)),
                onTap: () => _updateStatusApi(emp['employee_id'], 'terminated', reasonCtrl.text.trim(), ctx),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _updateStatusApi(int empId, String status, String reason, BuildContext ctx) async {
    Navigator.pop(ctx);
    try {
      final res = await http.put(
        Uri.parse('http://localhost:5000/api/hr/employees/$empId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status, 'exit_reason': reason}),
      );

      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Status updated'),
            backgroundColor: status == 'active' ? const Color(0xFF059669) : (status == 'suspended' ? const Color(0xFFD97706) : Colors.redAccent),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchEmployees();
      }
    } catch (_) {}
  }

  // 6. DELETE EMPLOYEE
  void _confirmDelete(int empId, String name) {
    if (!_canManageStaff) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Employee Record?'),
        content: Text('Are you sure you want to delete $name? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await http.delete(Uri.parse('http://localhost:5000/api/hr/employees/$empId'));
              _fetchEmployees();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final isMobile = MediaQuery.of(context).size.width < 650;
    final cardBg = isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.55);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF475569);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.7);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // 1. TOP HEADER BANNER (Responsive Mobile Layout)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 650;

                    final deptsButton = OutlinedButton.icon(
                      icon: const Icon(Icons.domain_rounded, size: 14),
                      label: const Text('Departments', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textTitle,
                        side: BorderSide(color: cardBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DepartmentsScreen()),
                        ).then((_) => _fetchEmployees());
                      },
                    );

                    final onboardButton = _canManageStaff
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1, size: 15),
                            label: const Text('Onboard Employee', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            ),
                            onPressed: _openAddEmployeeScreen,
                          )
                        : null;

                    if (isMobile) {
                      // On phones the title and the two actions need separate rows.
                      // Keeping them in one Row causes a horizontal overflow on
                      // narrow devices once both buttons are visible.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back_rounded, color: textTitle),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Staff Directory',
                                      style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${_employees.length} Staff • Status & Access',
                                      style: TextStyle(color: textSub, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              deptsButton,
                              if (onboardButton != null) onboardButton,
                            ],
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
                              Text('HR & Employee Lifecycle Directory', style: TextStyle(color: textTitle, fontSize: 19, fontWeight: FontWeight.bold)),
                              Text('${_employees.length} Staff on Roster • Manage Status, Access & Terminations', style: TextStyle(color: textSub, fontSize: 12)),
                            ],
                          ),
                        ),
                        deptsButton,
                        if (onboardButton != null) ...[
                          const SizedBox(width: 8),
                          onboardButton,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),

              // 1.1 LIVE SEARCH BAR
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 22),
                  child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder, width: 1.1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: textTitle, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search staff by name, code (103), role, dept...',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 19),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, color: textSub, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // 2. UNIFIED FILTER BAR: Department Dropdown + Status Chips
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 22),
                child: Row(
                  children: [
                    // Sleek Department Dropdown
                    _buildDepartmentDropdown(isDark, cardBorder, textTitle),
                    const SizedBox(width: 10),
                    Container(width: 1.2, height: 26, color: cardBorder.withValues(alpha: 0.6)),
                    const SizedBox(width: 10),

                    // Status Filter Chips
                    _buildFilterChip('ALL', 'All Status ($_departmentFilteredCount)', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('active', 'Active', isDark, color: const Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    _buildFilterChip('suspended', 'Access Banned', isDark, color: const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    _buildFilterChip('terminated', 'Terminated', isDark, color: Colors.redAccent),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // 3. EMPLOYEE CARDS LIST (Fully Scrollable Slivers)
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
              )
            else if (_filteredEmployees.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 60, color: textSub.withValues(alpha: 0.4)),
                      const SizedBox(height: 14),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No staff found matching "$_searchQuery"'
                            : (_selectedDepartmentId != null
                                ? 'No ${_selectedFilter != 'ALL' ? _selectedFilter : ''} staff in ${_selectedDepartmentId == -1 ? "Unassigned" : (_availableDepartments.firstWhere((d) => d['id'] == _selectedDepartmentId, orElse: () => {'name': 'selected department'})['name'])}'
                                : 'No $_selectedFilter employees found'),
                        style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (_searchQuery.isNotEmpty || _selectedDepartmentId != null || _selectedFilter != 'ALL') ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          label: const Text('Reset All Filters'),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _selectedFilter = 'ALL';
                              _selectedDepartmentId = null;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(isMobile ? 12 : 22, 0, isMobile ? 12 : 22, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final emp = _filteredEmployees[index];
                    final status = (emp['status'] ?? 'active').toString().toLowerCase();

                    Color statusColor = const Color(0xFF10B981);
                    String statusLabel = 'ACTIVE';
                    IconData statusIcon = Icons.check_circle_outline;

                    if (status == 'suspended') {
                      statusColor = const Color(0xFFF59E0B);
                      statusLabel = 'ACCESS BANNED';
                      statusIcon = Icons.lock_person_outlined;
                    } else if (status == 'terminated') {
                      statusColor = Colors.redAccent;
                      statusLabel = 'TERMINATED';
                      statusIcon = Icons.person_off_outlined;
                    }

                                        return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cardBorder, width: 1.2),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04), blurRadius: 16, offset: const Offset(0, 6)),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                // 👈 Member card click - Ab Permission Protected hai!
                                onTap: () {
                                  final isOwnProfile = _currentUserId != null && _currentUserId == emp['user_id'];

                                  // Agar Super Admin hai, ya permission mili hai, ya apna khud ka profile hai:
                                  if (_canViewLifecycle || isOwnProfile) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EmployeeDetailsScreen(employeeId: emp['employee_id']),
                                      ),
                                    );
                                  } else {
                                    // Bina permission ke access block:
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Access Denied: You can not have access'),
                                        backgroundColor: Colors.redAccent,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                child: Builder(
                                  builder: (context) {
                                    final isMobileCard = MediaQuery.of(context).size.width < 650;
                                    final roleName = (emp['role_name'] ?? emp['role'] ?? 'Employee').toString();
                                    Color roleColor;
                                    Color roleBg;
                                    IconData roleIcon;
                                    if (roleName.toLowerCase().contains('admin')) {
                                      roleColor = const Color(0xFF8B5CF6);
                                      roleBg = const Color(0xFF8B5CF6).withValues(alpha: 0.15);
                                      roleIcon = Icons.admin_panel_settings_rounded;
                                    } else if (roleName.toLowerCase().contains('manager')) {
                                      roleColor = const Color(0xFF2563EB);
                                      roleBg = const Color(0xFF2563EB).withValues(alpha: 0.15);
                                      roleIcon = Icons.manage_accounts_rounded;
                                    } else {
                                      roleColor = const Color(0xFF059669);
                                      roleBg = const Color(0xFF059669).withValues(alpha: 0.12);
                                      roleIcon = Icons.badge_outlined;
                                    }

                                    if (isMobileCard) {
                                      // 📱 MOBILE CARD LAYOUT (Clean, Structured & Touch-Friendly)
                                      return Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 1. Top Row: Avatar + Name/Code + Status Pill
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                CircleAvatar(
                                                  radius: 19,
                                                  backgroundColor: statusColor.withValues(alpha: 0.15),
                                                  child: Text(
                                                    (emp['full_name'] != null && emp['full_name'].toString().isNotEmpty)
                                                        ? emp['full_name'][0].toUpperCase()
                                                        : 'E',
                                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              emp['full_name'] ?? 'Staff',
                                                              style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            child: Text(
                                                              emp['emp_code'] ?? 'EMP',
                                                              style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10.5, fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${emp['designation'] ?? 'Staff'} • ${emp['department_name'] ?? 'Manufacturing Operations'}',
                                                        style: TextStyle(color: textSub, fontSize: 11.5),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
                                                        statusLabel,
                                                        style: TextStyle(color: statusColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(height: 10),

                                            // 2. Info Badges (Role, Machine ID, Phone)
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 5,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: roleBg,
                                                    borderRadius: BorderRadius.circular(5),
                                                    border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(roleIcon, size: 11, color: roleColor),
                                                      const SizedBox(width: 4),
                                                      Text(roleName, style: TextStyle(color: roleColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(5),
                                                    border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.fingerprint_rounded, size: 11, color: textSub),
                                                      const SizedBox(width: 4),
                                                      Text('ID: ${emp['biometric_emp_code'] ?? 'N/A'}', style: TextStyle(color: textSub, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                                ),
                                                if (emp['phone'] != null && emp['phone'].toString().isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                    decoration: BoxDecoration(
                                                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.call_outlined, size: 11, color: textSub),
                                                        const SizedBox(width: 4),
                                                        Text('${emp['phone']}', style: TextStyle(color: textSub, fontSize: 10.5)),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),

                                            if (status == 'terminated' && emp['exit_reason'] != null) ...[
                                              const SizedBox(height: 6),
                                              Text('Exit: "${emp['exit_reason']}"', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontStyle: FontStyle.italic)),
                                            ],

                                            const SizedBox(height: 10),
                                            Divider(height: 1, color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                                            const SizedBox(height: 8),

                                            // 3. Bottom Strip: View Profile + Action Buttons
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const Row(
                                                  children: [
                                                    Text('View Profile', style: TextStyle(color: Color(0xFF059669), fontSize: 11.5, fontWeight: FontWeight.w600)),
                                                    SizedBox(width: 3),
                                                    Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF059669), size: 10),
                                                  ],
                                                ),
                                                if (_canManageStaff)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      InkWell(
                                                        onTap: () => _showChangeRoleDialog(emp),
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(Icons.manage_accounts_rounded, size: 13, color: Color(0xFF2563EB)),
                                                              SizedBox(width: 4),
                                                              Text('Role', style: TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      InkWell(
                                                        onTap: () => _showLifecycleDialog(emp),
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(Icons.shield_outlined, size: 13, color: Color(0xFF10B981)),
                                                              SizedBox(width: 4),
                                                              Text('Access', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      InkWell(
                                                        onTap: () => _confirmDelete(emp['employee_id'], emp['full_name'] ?? 'Employee'),
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.all(5),
                                                          decoration: BoxDecoration(
                                                            color: Colors.redAccent.withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    // 💻 DESKTOP CARD LAYOUT (Wide Row)
                                    return Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: statusColor.withValues(alpha: 0.15),
                                            child: Icon(statusIcon, color: statusColor, size: 22),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    Text(emp['full_name'] ?? 'Staff', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(emp['emp_code'] ?? 'EMP-00', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold)),
                                                    ),
                                                    // Role Badge
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: roleBg,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: roleColor.withValues(alpha: 0.35)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(roleIcon, size: 12, color: roleColor),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            roleName,
                                                            style: TextStyle(color: roleColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: statusColor.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  'Role: $roleName • Designation: ${emp['designation'] ?? 'Staff'} • ${emp['department_name'] ?? 'Manufacturing Operations'} • Machine ID: ${emp['biometric_emp_code'] ?? 'N/A'}',
                                                  style: TextStyle(color: textSub, fontSize: 12),
                                                ),
                                                if (emp['phone'] != null && emp['phone'].toString().isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text('📞 ${emp['phone']} • ✉️ ${emp['email'] ?? 'N/A'}', style: TextStyle(color: textSub, fontSize: 11.5)),
                                                ],
                                                if (status == 'terminated' && emp['exit_reason'] != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text('Exit Reason: "${emp['exit_reason']}"', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontStyle: FontStyle.italic)),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (_canManageStaff) ...[
                                            IconButton(
                                              icon: const Icon(Icons.manage_accounts_outlined, color: Color(0xFF2563EB), size: 19),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                              tooltip: 'Promote / Change Role (Admin, Manager, Employee)',
                                              onPressed: () => _showChangeRoleDialog(emp),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 18),
                                              onPressed: () => _showLifecycleDialog(emp),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                              onPressed: () => _confirmDelete(emp['employee_id'], emp['full_name'] ?? 'Employee'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _filteredEmployees.length,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildFilterChip(String filterKey, String label, bool isDark, {Color? color}) {
    final isSelected = _selectedFilter == filterKey;
    final activeColor = color ?? const Color(0xFF059669);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.2),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.6),
      labelStyle: TextStyle(
        color: isSelected ? (color ?? const Color(0xFF10B981)) : (isDark ? Colors.white70 : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.black12)),
      onSelected: (_) => setState(() => _selectedFilter = filterKey),
    );
  }

  Widget _buildDepartmentDropdown(bool isDark, Color cardBorder, Color textTitle) {
    final hasSelection = _selectedDepartmentId != null;
    const activeColor = Color(0xFF0284C7);

    // Safe lookup for valid dropdown value
    int? currentDeptValue = _selectedDepartmentId;
    final allValidValues = <int?>[
      null,
      if (_employees.any((e) => e['department_id'] == null)) -1,
      ..._availableDepartments.map((d) => d['id'] as int),
    ];
    if (!allValidValues.contains(currentDeptValue)) {
      currentDeptValue = null;
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark
            ? (hasSelection ? activeColor.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.05))
            : (hasSelection ? const Color(0xFFE0F2FE) : Colors.white.withValues(alpha: 0.85)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasSelection ? activeColor : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
          width: hasSelection ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: currentDeptValue,
          icon: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: hasSelection ? activeColor : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            color: hasSelection ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1)) : textTitle,
            fontSize: 12,
            fontWeight: hasSelection ? FontWeight.bold : FontWeight.w600,
          ),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.domain_rounded,
                    size: 15,
                    color: hasSelection ? activeColor : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 7),
                  Text('All Departments (${_employees.length})'),
                ],
              ),
            ),
            ..._availableDepartments.map((dept) {
              final deptId = dept['id'] as int;
              final count = _employees.where((e) => int.tryParse(e['department_id']?.toString() ?? '') == deptId).length;
              return DropdownMenuItem<int?>(
                value: deptId,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.apartment_rounded, size: 15, color: activeColor),
                    const SizedBox(width: 7),
                    Text('${dept['name']} ($count)'),
                  ],
                ),
              );
            }),
            if (_employees.any((e) => e['department_id'] == null))
              DropdownMenuItem<int?>(
                value: -1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.help_outline_rounded, size: 15, color: Color(0xFF64748B)),
                    const SizedBox(width: 7),
                    Text('Unassigned (${_employees.where((e) => e['department_id'] == null).length})'),
                  ],
                ),
              ),
          ],
          onChanged: (val) {
            setState(() => _selectedDepartmentId = val);
          },
        ),
      ),
    );
  }
}