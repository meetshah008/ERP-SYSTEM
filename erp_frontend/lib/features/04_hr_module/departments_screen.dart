import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/network/session_manager.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import 'department_details_screen.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  bool _isLoading = true;
  bool _canManageDepartments = false;
  List<dynamic> _departments = [];
  List<dynamic> _employees = [];
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchData();
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
    if (mounted) setState(() => _canManageDepartments = hasPerm);
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final deptRes = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
      if (deptRes.statusCode == 200) {
        final dJson = jsonDecode(deptRes.body);
        if (dJson['success'] == true && dJson['data'] is List) {
          _departments = dJson['data'];
        }
      }

      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final eJson = jsonDecode(empRes.body);
        if (eJson['success'] == true && eJson['data'] is List) {
          _employees = eJson['data'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching departments data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<dynamic> get _filteredDepartments {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _departments;
    return _departments.where((d) {
      final name = (d['name'] ?? '').toString().toLowerCase();
      // Also match employees in department
      final deptId = d['department_id'];
      final staffMatch = _employees.any((e) =>
          (e['department_id'] == deptId || e['department_name'] == d['name']) &&
          ((e['full_name'] ?? '').toString().toLowerCase().contains(q) ||
              (e['emp_code'] ?? '').toString().toLowerCase().contains(q)));
      return name.contains(q) || staffMatch;
    }).toList();
  }

  // Add / Edit Department Dialog
  void _openAddEditDeptDialog([Map<String, dynamic>? deptToEdit]) async {
    if (!_canManageDepartments) return;
    final isEditing = deptToEdit != null;
    final nameCtrl = TextEditingController(text: isEditing ? (deptToEdit['name'] ?? '') : '');
    final targetDeptId = isEditing ? int.tryParse(deptToEdit['department_id']?.toString() ?? '') : null;
    final targetDeptName = isEditing ? (deptToEdit['name'] ?? '').toString().trim().toLowerCase() : '';

    final Set<int> selectedMemberIds = {};
    if (isEditing) {
      for (var emp in _employees) {
        final empId = int.tryParse(emp['employee_id']?.toString() ?? '');
        final empDeptId = int.tryParse(emp['department_id']?.toString() ?? '');
        final empDeptName = (emp['department_name'] ?? '').toString().trim().toLowerCase();
        if (empId != null) {
          if (targetDeptId != null && empDeptId == targetDeptId) {
            selectedMemberIds.add(empId);
          } else if (targetDeptName.isNotEmpty && empDeptName == targetDeptName) {
            selectedMemberIds.add(empId);
          }
        }
      }
    }

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

          final filteredEmployees = _employees.where((emp) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            final name = (emp['full_name'] ?? '').toString().toLowerCase();
            final code = (emp['emp_code'] ?? '').toString().toLowerCase();
            final desig = (emp['designation'] ?? '').toString().toLowerCase();
            return name.contains(q) || code.contains(q) || desig.contains(q);
          }).toList();

          final allFilteredSelected = filteredEmployees.isNotEmpty &&
              filteredEmployees.every((e) => selectedMemberIds.contains(int.tryParse(e['employee_id']?.toString() ?? '')));

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 540,
              constraints: const BoxConstraints(maxHeight: 680),
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
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEditing ? Icons.edit_note_rounded : Icons.domain_add_rounded,
                          color: const Color(0xFF059669),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing ? 'Edit Department & Staff' : 'Create New Department',
                              style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEditing
                                  ? 'Update department name and team allocations'
                                  : 'Name the department and assign initial team members',
                              style: TextStyle(color: textSub, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textSub, size: 20),
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Department Name Input
                  Text('Department Name', style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      hintText: 'e.g. Manufacturing Operations, IT, Finance',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.7), fontSize: 13),
                      prefixIcon: const Icon(Icons.apartment_rounded, color: Color(0xFF7C3AED), size: 19),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Members Header & Quick Select
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, color: Color(0xFF2563EB), size: 18),
                      const SizedBox(width: 8),
                      Text('Assigned Staff Members', style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${selectedMemberIds.length} Selected',
                          style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      if (filteredEmployees.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: isSaving
                              ? null
                              : () {
                                  setDialogState(() {
                                    if (allFilteredSelected) {
                                      for (var e in filteredEmployees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null) selectedMemberIds.remove(eid);
                                      }
                                    } else {
                                      for (var e in filteredEmployees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null) selectedMemberIds.add(eid);
                                      }
                                    }
                                  });
                                },
                          child: Text(
                            allFilteredSelected ? 'Deselect All' : 'Select All',
                            style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Member Search Filter
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

                  // Member List (Scrollable)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: listBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: _employees.isEmpty
                          ? Center(
                              child: Text('No active employees found in system.',
                                  textAlign: TextAlign.center, style: TextStyle(color: textSub, fontSize: 12)),
                            )
                          : filteredEmployees.isEmpty
                              ? Center(
                                  child: Text('No employees match "$filterQuery"', style: TextStyle(color: textSub, fontSize: 12)),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: filteredEmployees.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: cardBorder.withValues(alpha: 0.4)),
                                  itemBuilder: (context, idx) {
                                    final emp = filteredEmployees[idx];
                                    final empId = int.tryParse(emp['employee_id']?.toString() ?? '') ?? 0;
                                    final isSelected = selectedMemberIds.contains(empId);
                                    final empDeptName = (emp['department_name'] ?? '').toString().trim();
                                    final isCurrentlyInThisDept = isEditing &&
                                        ((targetDeptId != null && int.tryParse(emp['department_id']?.toString() ?? '') == targetDeptId) ||
                                            (targetDeptName.isNotEmpty && empDeptName.toLowerCase() == targetDeptName));

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
                                                  ? const Color(0xFF059669).withValues(alpha: 0.18)
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
                                                    style: TextStyle(
                                                      color: textTitle,
                                                      fontSize: 13,
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        '#${emp['emp_code'] ?? '01'} • ${emp['designation'] ?? 'Operator'}',
                                                        style: TextStyle(color: textSub, fontSize: 11),
                                                      ),
                                                      if (empDeptName.isNotEmpty) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: isCurrentlyInThisDept
                                                                ? const Color(0xFF059669).withValues(alpha: 0.12)
                                                                : Colors.amber.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            isCurrentlyInThisDept ? 'This Dept' : empDeptName,
                                                            style: TextStyle(
                                                              color: isCurrentlyInThisDept ? const Color(0xFF059669) : Colors.amber.shade800,
                                                              fontSize: 9.5,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
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
                  const SizedBox(height: 18),

                  // Footer Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textSub,
                          side: BorderSide(color: cardBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter a department name!')),
                                  );
                                  return;
                                }

                                setDialogState(() => isSaving = true);
                                try {
                                  http.Response res;
                                  if (isEditing) {
                                    res = await http.put(
                                      Uri.parse('http://localhost:5000/api/hr/departments/${deptToEdit['department_id']}'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode({
                                        'name': name,
                                        'member_ids': selectedMemberIds.toList(),
                                      }),
                                    );
                                  } else {
                                    res = await http.post(
                                      Uri.parse('http://localhost:5000/api/hr/departments'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode({
                                        'name': name,
                                        'member_ids': selectedMemberIds.toList(),
                                      }),
                                    );
                                  }

                                  if (res.statusCode == 200 || res.statusCode == 201) {
                                    if (mounted) {
                                      Navigator.pop(dialogCtx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(isEditing
                                              ? 'Department "$name" & members updated!'
                                              : 'Department "$name" created successfully!'),
                                          backgroundColor: const Color(0xFF059669),
                                        ),
                                      );
                                      _fetchData();
                                    }
                                  } else {
                                    final errJson = jsonDecode(res.body);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(errJson['message'] ?? 'Failed to save department'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Network error: $e'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                } finally {
                                  if (mounted) setDialogState(() => isSaving = false);
                                }
                              },
                        child: isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(isEditing ? 'Save Changes' : 'Create Department', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  // Delete Department
  void _confirmDeleteDept(Map<String, dynamic> dept) {
    if (!_canManageDepartments) return;
    final deptId = dept['department_id'];
    final deptName = dept['name'] ?? 'this department';
    final deptEmployees = _employees.where((e) => e['department_name'] == deptName || e['department_id'] == deptId).toList();

    if (deptEmployees.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 10),
              Text('Cannot Delete Unit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'Cannot delete "$deptName" because ${deptEmployees.length} staff member(s) are currently assigned to it.\n\nPlease reassign or remove members before deleting.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Deletion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete department "$deptName"? This action cannot be undone.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = await http.delete(Uri.parse('http://localhost:5000/api/hr/departments/$deptId'));
                if (res.statusCode == 200) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Department "$deptName" deleted successfully!'), backgroundColor: Colors.redAccent),
                    );
                    _fetchData();
                  }
                }
              } catch (_) {}
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  List<dynamic> _membersOf(Map<String, dynamic> dept) {
    final deptId = dept['department_id'];
    return _employees
        .where((e) =>
            e['department_name'] == dept['name'] || e['department_id'] == deptId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final cardBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.9);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final accent = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final totalAllocatedStaff = _departments.fold<int>(
      0,
      (sum, dept) => sum + _membersOf(dept).length,
    );
    final unassignedStaff = _employees.length > totalAllocatedStaff
        ? _employees.length - totalAllocatedStaff
        : 0;
    final filtered = _filteredDepartments;
    final maxMembers = _departments.isEmpty
        ? 1
        : _departments
            .map((dept) => _membersOf(dept).length)
            .reduce((a, b) => a > b ? a : b);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final isWide = viewport.maxWidth >= 760;
              final isExtraWide = viewport.maxWidth >= 1280;
              final horizontal = isWide ? 24.0 : 16.0;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        isWide ? 20 : 12,
                        horizontal,
                        0,
                      ),
                      child: _buildHeroHeader(
                        isDark: isDark,
                        isWide: isWide,
                        textTitle: textTitle,
                        textSub: textSub,
                      ),
                    ),
                  ),

                  // ================= SUMMARY METRICS =================
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                      child: LayoutBuilder(
                        builder: (context, metricBox) {
                          final columns = metricBox.maxWidth >= 900
                              ? 3
                              : (metricBox.maxWidth >= 540 ? 2 : 1);
                          final cardWidth =
                              (metricBox.maxWidth - 12.0 * (columns - 1)) /
                                  columns;
                          // With three metrics in a two-column layout, let the
                          // last card span the full row so the strip stays balanced.
                          final lastWidth =
                              columns == 2 ? metricBox.maxWidth : cardWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: cardWidth,
                                child: _buildMetricCard(
                                  icon: Icons.account_tree_rounded,
                                  value: '${_departments.length}',
                                  label: 'Business Units',
                                  caption: 'Active departments',
                                  color: const Color(0xFF7C3AED),
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  textTitle: textTitle,
                                  textSub: textSub,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _buildMetricCard(
                                  icon: Icons.groups_2_rounded,
                                  value: '$totalAllocatedStaff',
                                  label: 'Allocated Staff',
                                  caption: 'Across all units',
                                  color: const Color(0xFF059669),
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  textTitle: textTitle,
                                  textSub: textSub,
                                ),
                              ),
                              SizedBox(
                                width: lastWidth,
                                child: _buildMetricCard(
                                  icon: Icons.person_off_outlined,
                                  value: '$unassignedStaff',
                                  label: 'Unallocated',
                                  caption: 'Awaiting assignment',
                                  color: const Color(0xFFF59E0B),
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  textTitle: textTitle,
                                  textSub: textSub,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // ================= SEARCH & ACTIONS =================
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 46,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cardBorder),
                              ),
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                style:
                                    TextStyle(color: textTitle, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search unit by name or assigned staff...',
                                  hintStyle: TextStyle(
                                    color: textSub.withValues(alpha: 0.6),
                                    fontSize: 12.5,
                                  ),
                                  prefixIcon: Icon(Icons.search_rounded,
                                      color: accent, size: 20),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Clear search',
                                          icon: Icon(Icons.close_rounded,
                                              color: textSub, size: 17),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 10),
                            Container(
                              height: 46,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cardBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.grid_view_rounded,
                                      size: 15, color: accent),
                                  const SizedBox(width: 7),
                                  Text(
                                    '${filtered.length} shown',
                                    style: TextStyle(
                                      color: textSub,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          _buildHeaderIcon(
                            icon: Icons.refresh_rounded,
                            color: textSub,
                            isDark: isDark,
                            size: 46,
                            tooltip: 'Refresh',
                            onTap: _fetchData,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ================= SECTION HEADER =================
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 20, horizontal, 10),
                      child: Row(
                        children: [
                          Text(
                            'Business Units',
                            style: TextStyle(
                              color: textTitle,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_departments.length}',
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (isWide)
                            Text(
                              'Tap a unit to open its workspace',
                              style: TextStyle(
                                color: textSub.withValues(alpha: 0.8),
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ================= DEPARTMENT GRID =================
                  if (_isLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF059669)),
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(
                        isDark: isDark,
                        textTitle: textTitle,
                        textSub: textSub,
                      ),
                    )
                  else
                    SliverPadding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 28),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isExtraWide
                              ? 3
                              : (viewport.maxWidth >= 820 ? 2 : 1),
                          mainAxisExtent: 236,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final dept = filtered[index];
                            final deptName =
                                (dept['name'] ?? 'Department').toString();
                            return _buildDepartmentCard(
                              dept: dept,
                              deptName: deptName,
                              deptEmployees: _membersOf(dept),
                              maxMembers: maxMembers,
                              cardBg: cardBg,
                              cardBorder: cardBorder,
                              textTitle: textTitle,
                              textSub: textSub,
                              isDark: isDark,
                            );
                          },
                          childCount: filtered.length,
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

  // ================= HERO HEADER =================
  Widget _buildHeroHeader({
    required bool isDark,
    required bool isWide,
    required Color textTitle,
    required Color textSub,
  }) {
    return Container(
      padding: EdgeInsets.all(isWide ? 20 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
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
          color:
              const Color(0xFF059669).withValues(alpha: isDark ? 0.3 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildHeaderIcon(
            icon: Icons.arrow_back_rounded,
            color: textTitle,
            isDark: isDark,
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(width: isWide ? 16 : 12),
          Container(
            width: isWide ? 50 : 44,
            height: isWide ? 50 : 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF059669), Color(0xFF10B981)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.account_tree_rounded,
                color: Colors.white, size: 24),
          ),
          SizedBox(width: isWide ? 16 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Department Hierarchy & Units',
                  style: TextStyle(
                    color: textTitle,
                    fontSize: isWide ? 21 : 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Corporate business units, operations & staff allocations',
                  style: TextStyle(
                    color: textSub,
                    fontSize: isWide ? 12.5 : 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_canManageDepartments) ...[
            const SizedBox(width: 12),
            if (isWide)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text(
                  'New Department',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                onPressed: () => _openAddEditDeptDialog(null),
              )
            else
              Tooltip(
                message: 'New Department',
                child: Material(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () => _openAddEditDeptDialog(null),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.add_rounded,
                          color: Colors.white, size: 23),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    double size = 40,
    String? tooltip,
  }) {
    final button = Material(
      color:
          isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  // ================= METRIC CARD =================
  Widget _buildMetricCard({
    required IconData icon,
    required String value,
    required String label,
    required String caption,
    required Color color,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: textTitle,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: textSub,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  caption,
                  style: TextStyle(
                    color: textSub.withValues(alpha: 0.7),
                    fontSize: 10,
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

  // ================= EMPTY STATE =================
  Widget _buildEmptyState({
    required bool isDark,
    required Color textTitle,
    required Color textSub,
  }) {
    final searching = _searchQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 470),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF059669).withValues(alpha: 0.18),
                      const Color(0xFF10B981).withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Icon(
                  searching
                      ? Icons.search_off_rounded
                      : Icons.account_tree_rounded,
                  color: const Color(0xFF059669),
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                searching ? 'No units match your search' : 'No departments yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textTitle,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                searching
                    ? 'Try a different unit name or staff member.'
                    : 'Create your first department to start organising teams and staff allocations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSub, fontSize: 12.5, height: 1.45),
              ),
              if (!searching && _canManageDepartments) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Create First Department',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  onPressed: () => _openAddEditDeptDialog(null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentCard({
    required Map<String, dynamic> dept,
    required String deptName,
    required List<dynamic> deptEmployees,
    required int maxMembers,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required bool isDark,
  }) {
    return _DepartmentUnitCard(
      deptName: deptName,
      unitNumber: dept['department_id']?.toString() ?? '',
      deptEmployees: deptEmployees,
      maxMembers: maxMembers,
      cardBg: cardBg,
      cardBorder: cardBorder,
      textTitle: textTitle,
      textSub: textSub,
      isDark: isDark,
      canManage: _canManageDepartments,
      onOpen: () {
        // 👉 NAVIGATE TO DEPARTMENT DETAILS SCREEN!
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DepartmentDetailsScreen(
              department: dept,
              initialEmployees: deptEmployees,
              allEmployees: _employees,
              onDepartmentUpdated: _fetchData,
            ),
          ),
        ).then((_) => _fetchData());
      },
      onEdit: () => _openAddEditDeptDialog(dept),
      onDelete: () => _confirmDeleteDept(dept),
    );
  }
}

// ================= DEPARTMENT CARD (HOVER + AVATARS) =================
class _DepartmentUnitCard extends StatefulWidget {
  final String deptName;
  final String unitNumber;
  final List<dynamic> deptEmployees;
  final int maxMembers;
  final Color cardBg;
  final Color cardBorder;
  final Color textTitle;
  final Color textSub;
  final bool isDark;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DepartmentUnitCard({
    required this.deptName,
    required this.unitNumber,
    required this.deptEmployees,
    required this.maxMembers,
    required this.cardBg,
    required this.cardBorder,
    required this.textTitle,
    required this.textSub,
    required this.isDark,
    required this.canManage,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DepartmentUnitCard> createState() => _DepartmentUnitCardState();
}

class _DepartmentUnitCardState extends State<_DepartmentUnitCard> {
  bool _hovered = false;

  static const Color _accent = Color(0xFF059669);

  String _initialsOf(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '?';
    final parts =
        text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = widget.deptEmployees.length;
    final ratio = widget.maxMembers <= 0
        ? 0.0
        : (memberCount / widget.maxMembers).clamp(0.0, 1.0).toDouble();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: widget.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? _accent.withValues(alpha: 0.55)
                : widget.cardBorder,
            width: _hovered ? 1.4 : 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: widget.isDark
                    ? (_hovered ? 0.35 : 0.22)
                    : (_hovered ? 0.09 : 0.05),
              ),
              blurRadius: _hovered ? 22 : 14,
              offset: Offset(0, _hovered ? 10 : 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onOpen,
            hoverColor: _accent.withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Card header ----
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initialsOf(widget.deptName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
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
                              widget.deptName,
                              style: TextStyle(
                                color: widget.textTitle,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'UNIT ${widget.unitNumber}',
                              style: TextStyle(
                                color:
                                    widget.textSub.withValues(alpha: 0.75),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7)
                              .withValues(alpha: widget.isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_alt_rounded,
                                size: 12.5, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(
                              '$memberCount',
                              style: const TextStyle(
                                color: Color(0xFF0284C7),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.canManage) ...[
                        const SizedBox(width: 2),
                        PopupMenuButton<String>(
                          tooltip: 'Manage unit',
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_horiz_rounded,
                              color: widget.textSub, size: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (val) {
                            if (val == 'edit') {
                              widget.onEdit();
                            } else if (val == 'delete') {
                              widget.onDelete();
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              height: 42,
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined,
                                      size: 17, color: _accent),
                                  const SizedBox(width: 10),
                                  const Text('Edit department',
                                      style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              height: 42,
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline_rounded,
                                      size: 17, color: Colors.redAccent),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Delete department',
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- Member avatars ----
                  if (memberCount == 0)
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: widget.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_add_alt_1_rounded,
                              size: 14, color: widget.textSub),
                          const SizedBox(width: 6),
                          Text(
                            'No staff assigned yet',
                            style: TextStyle(
                              color: widget.textSub,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 30,
                      child: Row(
                        children: [
                          _buildAvatarStack(),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              memberCount <= 3
                                  ? 'Team members'
                                  : 'and ${memberCount - 3} more',
                              style: TextStyle(
                                color: widget.textSub,
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  // ---- Allocation progress ----
                  Row(
                    children: [
                      Text(
                        'Team size',
                        style: TextStyle(
                          color: widget.textSub,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Largest unit: ${widget.maxMembers}',
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: widget.isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation(_accent),
                    ),
                  ),
                  const Spacer(),

                  // ---- Footer ----
                  Divider(
                    height: 20,
                    color: widget.cardBorder.withValues(alpha: 0.6),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: _accent),
                      const SizedBox(width: 6),
                      Text(
                        memberCount == 0
                            ? 'Unassigned unit'
                            : '$memberCount active staff',
                        style: TextStyle(
                          color: widget.textSub,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Open unit',
                        style: TextStyle(
                          color: _accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 14, color: _accent),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarStack() {
    final members = widget.deptEmployees.take(3).toList();
    final extra = widget.deptEmployees.length - members.length;
    const colors = [
      Color(0xFF059669),
      Color(0xFF0284C7),
      Color(0xFF7C3AED),
      Color(0xFFF59E0B),
    ];
    final width =
        20.0 * members.length + (extra > 0 ? 30.0 : 10.0);
    return SizedBox(
      width: width,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < members.length; i++)
            Positioned(
              left: i * 20.0,
              top: 0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[i % colors.length],
                  border: Border.all(color: widget.cardBg, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initialsOf(members[i]['full_name']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: members.length * 20.0,
              top: 0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  border: Border.all(color: widget.cardBg, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    color: widget.textSub,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
