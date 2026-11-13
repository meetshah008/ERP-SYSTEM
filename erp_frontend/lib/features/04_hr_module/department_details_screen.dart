import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/network/session_manager.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import 'employee_details_screen.dart';

class DepartmentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> department;
  final List<dynamic>? initialEmployees;
  final List<dynamic>? allEmployees;
  final VoidCallback? onDepartmentUpdated;

  const DepartmentDetailsScreen({
    super.key,
    required this.department,
    this.initialEmployees,
    this.allEmployees,
    this.onDepartmentUpdated,
  });

  @override
  State<DepartmentDetailsScreen> createState() => _DepartmentDetailsScreenState();
}

class _DepartmentDetailsScreenState extends State<DepartmentDetailsScreen> {
  bool _isLoading = true;
  bool _canManageStaff = false;
  late Map<String, dynamic> _department;
  List<dynamic> _deptEmployees = [];
  List<dynamic> _allEmployees = [];
  String _searchQuery = '';
  String _selectedStatus = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _department = Map<String, dynamic>.from(widget.department);
    if (widget.initialEmployees != null) {
      _deptEmployees = List<dynamic>.from(widget.initialEmployees!);
    }
    if (widget.allEmployees != null) {
      _allEmployees = List<dynamic>.from(widget.allEmployees!);
    }
    _checkPermissions();
    _fetchDepartmentDetails();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final session = await SessionManager.getUserSession();
    final isSuper = session['role'] == 'Super Admin';
    final hasPerm = isSuper || await SessionManager.hasPermission('hr_manage_departments');
    if (mounted) setState(() => _canManageStaff = hasPerm);
  }

  Future<void> _fetchDepartmentDetails() async {
    setState(() => _isLoading = true);
    final deptId = _department['department_id'];
    final deptName = _department['name'];

    try {
      // 1. Fetch all employees to get department roster
      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final eJson = jsonDecode(empRes.body);
        if (eJson['success'] == true && eJson['data'] is List) {
          _allEmployees = eJson['data'];
          _deptEmployees = _allEmployees.where((e) {
            final eDeptId = e['department_id'];
            final eDeptName = e['department_name'];
            return (deptId != null && eDeptId == deptId) ||
                (deptName != null && eDeptName != null && eDeptName.toString().toLowerCase() == deptName.toString().toLowerCase());
          }).toList();
        }
      }

      // 2. Refresh department info
      final deptRes = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
      if (deptRes.statusCode == 200) {
        final dJson = jsonDecode(deptRes.body);
        if (dJson['success'] == true && dJson['data'] is List) {
          final found = (dJson['data'] as List).firstWhere(
            (d) => d['department_id'] == deptId,
            orElse: () => _department,
          );
          _department = Map<String, dynamic>.from(found);
        }
      }
    } catch (e) {
      debugPrint('Error fetching department details: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<dynamic> get _filteredEmployees {
    final q = _searchQuery.trim().toLowerCase();

    return _deptEmployees.where((e) {
      // Status Filter
      final status = (e['status'] ?? 'active').toString().toLowerCase();
      if (_selectedStatus != 'ALL' && status != _selectedStatus.toLowerCase()) {
        return false;
      }

      // Search Filter
      if (q.isNotEmpty) {
        final name = (e['full_name'] ?? '').toString().toLowerCase();
        final code = (e['emp_code'] ?? '').toString().toLowerCase();
        final bio = (e['biometric_emp_code'] ?? '').toString().toLowerCase();
        final desig = (e['designation'] ?? '').toString().toLowerCase();
        final role = (e['role_name'] ?? e['role'] ?? '').toString().toLowerCase();
        return name.contains(q) || code.contains(q) || bio.contains(q) || desig.contains(q) || role.contains(q);
      }

      return true;
    }).toList();
  }

  // Assign / Reassign Staff Modal
  void _openAssignStaffDialog() async {
    if (!_canManageStaff) return;
    final deptId = int.tryParse(_department['department_id']?.toString() ?? '') ?? 0;
    final Set<int> selectedMemberIds = _deptEmployees
        .map((e) => int.tryParse(e['employee_id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toSet();

    bool isSaving = false;
    String filterQuery = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0);
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
          final listBg = isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFF8FAFC);

          final filteredAll = _allEmployees.where((emp) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            final name = (emp['full_name'] ?? '').toString().toLowerCase();
            final code = (emp['emp_code'] ?? '').toString().toLowerCase();
            final desig = (emp['designation'] ?? '').toString().toLowerCase();
            return name.contains(q) || code.contains(q) || desig.contains(q);
          }).toList();

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 650),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: dialogBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.1),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.group_add_rounded, color: Color(0xFF2563EB), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Allocate Staff Members', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('Select employees to assign to ${_department['name']}', style: TextStyle(color: textSub, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textSub, size: 20),
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Search Field
                  TextField(
                    enabled: !isSaving,
                    onChanged: (val) => setDialogState(() => filterQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search staff by name or code...',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Staff List
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: listBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredAll.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: cardBorder.withValues(alpha: 0.4)),
                        itemBuilder: (context, idx) {
                          final emp = filteredAll[idx];
                          final empId = int.tryParse(emp['employee_id']?.toString() ?? '') ?? 0;
                          final isSelected = selectedMemberIds.contains(empId);
                          final empDept = emp['department_name'] ?? '';

                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: isSaving
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (isSelected) {
                                        selectedMemberIds.remove(empId);
                                      } else {
                                        selectedMemberIds.add(empId);
                                      }
                                    });
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isSelected
                                        ? const Color(0xFF059669).withValues(alpha: 0.2)
                                        : const Color(0xFF64748B).withValues(alpha: 0.12),
                                    child: Text(
                                      (emp['full_name'] != null && emp['full_name'].toString().isNotEmpty)
                                          ? emp['full_name'].toString()[0].toUpperCase()
                                          : 'E',
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF059669) : textSub,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          emp['full_name'] ?? 'Staff',
                                          style: TextStyle(color: textTitle, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
                                        ),
                                        Text(
                                          '#${emp['emp_code'] ?? '01'} • ${emp['designation'] ?? 'Staff'}${empDept.isNotEmpty ? ' ($empDept)' : ''}',
                                          style: TextStyle(color: textSub, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF059669),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: isSaving
                                        ? null
                                        : (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedMemberIds.add(empId);
                                              } else {
                                                selectedMemberIds.remove(empId);
                                              }
                                            });
                                          },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                        onPressed: isSaving
                            ? null
                            : () async {
                                setDialogState(() => isSaving = true);
                                try {
                                  final res = await http.put(
                                    Uri.parse('http://localhost:5000/api/hr/departments/$deptId'),
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode({
                                      'name': _department['name'],
                                      'member_ids': selectedMemberIds.toList(),
                                    }),
                                  );

                                  if (res.statusCode == 200) {
                                    if (mounted) {
                                      Navigator.pop(dialogCtx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Department staff assignments updated!'),
                                          backgroundColor: Color(0xFF059669),
                                        ),
                                      );
                                      _fetchDepartmentDetails();
                                      widget.onDepartmentUpdated?.call();
                                    }
                                  }
                                } catch (_) {}
                              },
                        child: isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Save Allocations', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Remove single member from department
  void _removeMemberFromDept(dynamic emp) async {
    if (!_canManageStaff) return;
    final empId = emp['employee_id'];
    final empName = emp['full_name'] ?? 'Staff';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to remove "$empName" from ${_department['name']}?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updatedIds = _deptEmployees
          .map((e) => int.tryParse(e['employee_id']?.toString() ?? '') ?? 0)
          .where((id) => id > 0 && id != empId)
          .toList();

      try {
        final res = await http.put(
          Uri.parse('http://localhost:5000/api/hr/departments/${_department['department_id']}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': _department['name'],
            'member_ids': updatedIds,
          }),
        );
        if (res.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Removed $empName from department'), backgroundColor: const Color(0xFF059669)),
            );
            _fetchDepartmentDetails();
            widget.onDepartmentUpdated?.call();
          }
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final isWide = MediaQuery.of(context).size.width >= 700;

    final deptName = _department['name'] ?? 'Department';
    final deptId = _department['department_id'] ?? 'N/A';
    final nameParts = deptName
        .toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final deptInitials = nameParts.isEmpty
        ? 'D'
        : nameParts.length == 1
            ? nameParts.first.substring(0, 1).toUpperCase()
            : (nameParts.first.substring(0, 1) +
                    nameParts.last.substring(0, 1))
                .toUpperCase();
    final activeCount = _deptEmployees.where((e) => (e['status'] ?? 'active').toString().toLowerCase() == 'active').length;
    final bannedCount = _deptEmployees.where((e) => (e['status'] ?? '').toString().toLowerCase() == 'suspended').length;
    final managerCount = _deptEmployees.where((e) => (e['role_name'] ?? e['role'] ?? '').toString().toLowerCase().contains('manager')).length;

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TOP HEADER BAR
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Container(
                  padding: EdgeInsets.all(isWide ? 18 : 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF064E3B).withValues(alpha: 0.55),
                              const Color(0xFF0F172A).withValues(alpha: 0.35),
                            ]
                          : [
                              const Color(0xFF059669).withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.72),
                            ],
                    ),
                    border: Border.all(
                      color: const Color(0xFF059669)
                          .withValues(alpha: isDark ? 0.3 : 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.22 : 0.05),
                        blurRadius: 22,
                        offset: const Offset(0, 9),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Material(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(context),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.arrow_back_rounded,
                                color: textTitle, size: 20),
                          ),
                        ),
                      ),
                      SizedBox(width: isWide ? 14 : 10),
                      Container(
                        width: isWide ? 48 : 44,
                        height: isWide ? 48 : 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669)
                                  .withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          deptInitials,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isWide ? 16 : 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      SizedBox(width: isWide ? 14 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  deptName,
                                  style: TextStyle(
                                    color: textTitle,
                                    fontSize: isWide ? 20 : 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Unit #$deptId',
                                    style: const TextStyle(
                                      color: Color(0xFF7C3AED),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Corporate business unit • Member roster & allocations',
                              style: TextStyle(
                                color: textSub,
                                fontSize: isWide ? 12 : 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_canManageStaff) ...[
                        const SizedBox(width: 10),
                        if (isWide)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.group_add_rounded,
                                size: 18),
                            label: const Text(
                              'Assign Staff',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            onPressed: _openAssignStaffDialog,
                          )
                        else
                          Tooltip(
                            message: 'Assign Staff',
                            child: Material(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _openAssignStaffDialog,
                                child: const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(Icons.group_add_rounded,
                                      color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // 2. METRICS ROW
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, metricBox) {
                    final columns = metricBox.maxWidth >= 860 ? 4 : 2;
                    final cardWidth =
                        (metricBox.maxWidth - 10.0 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildMetricCard(
                            '${_deptEmployees.length}',
                            'Total Assigned',
                            Icons.people_alt_rounded,
                            const Color(0xFF0284C7),
                            isDark,
                            cardBorder,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildMetricCard(
                            '$activeCount',
                            'Active Staff',
                            Icons.check_circle_outline_rounded,
                            const Color(0xFF10B981),
                            isDark,
                            cardBorder,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildMetricCard(
                            '$managerCount',
                            'Unit Managers',
                            Icons.shield_outlined,
                            const Color(0xFF8B5CF6),
                            isDark,
                            cardBorder,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildMetricCard(
                            '$bannedCount',
                            'Access Banned',
                            Icons.block_rounded,
                            const Color(0xFFF59E0B),
                            isDark,
                            cardBorder,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),

              // 3. SEARCH & STATUS FILTER ROW
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSearchAndFilterBar(
                  isDark: isDark,
                  cardBorder: cardBorder,
                  textTitle: textTitle,
                  textSub: textSub,
                  deptName: deptName.toString(),
                  activeCount: activeCount,
                  bannedCount: bannedCount,
                ),
              ),
              const SizedBox(height: 12),

              // 4. EMPLOYEE ROSTER LIST
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                    : _filteredEmployees.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 54, color: textSub.withValues(alpha: 0.4)),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No staff found matching "$_searchQuery"'
                                      : 'No staff members assigned to this department yet',
                                  style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Assign members to this department to manage their lifecycle & access.',
                                  style: TextStyle(color: textSub, fontSize: 12),
                                ),
                                if (_canManageStaff) ...[
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    icon: const Icon(Icons.group_add_rounded, size: 16),
                                    label: const Text('Assign Staff Members'),
                                    onPressed: _openAssignStaffDialog,
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                            itemCount: _filteredEmployees.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final emp = _filteredEmployees[index];
                              return _buildEmployeeCard(
                                emp: emp,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textTitle: textTitle,
                                textSub: textSub,
                                isDark: isDark,
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String value,
    String label,
    IconData icon,
    Color color,
    bool isDark,
    Color cardBorder,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: ThemeController.isDarkMode.value
                        ? Colors.white
                        : const Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: ThemeController.isDarkMode.value
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar({
    required bool isDark,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required String deptName,
    required int activeCount,
    required int bannedCount,
  }) {
    final searchField = Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: TextStyle(color: textTitle, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search $deptName members by name, code, role...',
          hintStyle:
              TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFF0284C7), size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.clear_rounded, color: textSub, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        ),
      ),
    );

    final filterChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('ALL', 'All (${_deptEmployees.length})', isDark),
          const SizedBox(width: 6),
          _buildFilterChip('active', 'Active ($activeCount)', isDark,
              color: const Color(0xFF10B981)),
          const SizedBox(width: 6),
          _buildFilterChip('suspended', 'Banned ($bannedCount)', isDark,
              color: const Color(0xFFF59E0B)),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchField,
              const SizedBox(height: 8),
              filterChips,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: searchField),
            const SizedBox(width: 10),
            Expanded(flex: 4, child: filterChips),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String filterKey, String label, bool isDark, {Color? color}) {
    final isSelected = _selectedStatus == filterKey;
    final activeColor = color ?? const Color(0xFF059669);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.2),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.6),
      labelStyle: TextStyle(
        color: isSelected ? (color ?? const Color(0xFF10B981)) : (isDark ? Colors.white70 : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11.5,
      ),
      side: BorderSide(color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.black12)),
      onSelected: (_) => setState(() => _selectedStatus = filterKey),
    );
  }

  Widget _buildEmployeeCard({
    required dynamic emp,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required bool isDark,
  }) {
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

    final avatar = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF059669).withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF10B981),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              name,
              style: TextStyle(
                color: textTitle,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#${emp['emp_code'] ?? '01'}',
                style: const TextStyle(
                  color: Color(0xFF0284C7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            _infoChip(Icons.badge_outlined, emp['designation'] ?? 'Staff',
                textSub),
            _infoChip(Icons.shield_outlined,
                emp['role_name'] ?? emp['role'] ?? 'Employee', textSub),
            if (emp['biometric_emp_code'] != null)
              _infoChip(Icons.fingerprint,
                  'ID: ${emp['biometric_emp_code']}', textSub),
          ],
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFF1F5F9),
            foregroundColor: textTitle,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(color: cardBorder),
            ),
          ),
          icon: const Icon(Icons.person_outline_rounded, size: 14),
          label: const Text(
            'View Profile',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    EmployeeDetailsScreen(employeeId: emp['employee_id']),
              ),
            ).then((_) => _fetchDepartmentDetails());
          },
        ),
        if (_canManageStaff) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.person_remove_outlined,
                size: 18, color: Colors.redAccent),
            tooltip: 'Remove from ${_department['name']}',
            onPressed: () => _removeMemberFromDept(emp),
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(child: info),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 11.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
