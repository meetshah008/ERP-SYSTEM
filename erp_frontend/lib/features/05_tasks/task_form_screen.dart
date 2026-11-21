import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/session_manager.dart';
import '../../core/widgets/botanical_background.dart';

class TaskFormScreen extends StatefulWidget {
  final Map<String, dynamic>? task;
  final int? preselectedProjectId;
  final Map<String, dynamic>? preselectedProject;
  final Map<String, dynamic>? projectDetails;
  final List<dynamic> projects;
  final List<dynamic> employees;
  final VoidCallback? onTaskSaved;

  const TaskFormScreen({
    super.key,
    this.task,
    this.preselectedProjectId,
    this.preselectedProject,
    this.projectDetails,
    this.projects = const [],
    this.employees = const [],
    this.onTaskSaved,
  });

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  static String get _apiHost => ApiClient.apiHost;

  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _hoursCtrl;
  late TextEditingController _tagsCtrl;
  final List<TextEditingController> _subtaskCtrls = [];

  int? _selectedProjectId;
  final List<int> _selectedAssigneeIds = [];
  int? _selectedDeptId;
  String _selectedPriority = 'MEDIUM';
  String _selectedStatus = 'TODO';

  DateTime _startDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 3));

  bool _isSaving = false;
  List<dynamic> _departments = [];
  bool _isLoadingDepts = true;

  List<dynamic> _availableWorkers = [];
  bool _isLoadingProjectMembers = false;
  bool _canAssignOthers = true;
  bool _isPrivateTask = false;
  int? _currentEmployeeId;
  bool _isSuperAdmin = false;

  bool get isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;

    _titleCtrl = TextEditingController(text: t?['title'] ?? '');
    _descCtrl = TextEditingController(text: t?['description'] ?? '');
    _hoursCtrl = TextEditingController(text: (t?['estimated_hours'] ?? 8.0).toString());
    _tagsCtrl = TextEditingController(text: t?['tags'] ?? '');

    _selectedProjectId = t != null
        ? (int.tryParse(t['project_id']?.toString() ?? '') ?? widget.preselectedProjectId)
        : widget.preselectedProjectId;

    // Multi-worker assignment initialization
    if (t != null) {
      if (t['assignees'] is List && (t['assignees'] as List).isNotEmpty) {
        for (final a in t['assignees']) {
          final id = int.tryParse(a['employee_id']?.toString() ?? '');
          if (id != null && !_selectedAssigneeIds.contains(id)) {
            _selectedAssigneeIds.add(id);
          }
        }
      }
      if (_selectedAssigneeIds.isEmpty && t['assigned_to'] != null) {
        final id = int.tryParse(t['assigned_to'].toString());
        if (id != null) _selectedAssigneeIds.add(id);
      }
    }

    _availableWorkers = List.from(widget.employees);

    if (t != null && t['priority'] != null) {
      final p = t['priority'].toString().toUpperCase();
      if (p.contains('LOW')) {
        _selectedPriority = 'LOW';
      } else if (p.contains('HIGH')) {
        _selectedPriority = 'HIGH';
      } else if (p.contains('URG')) {
        _selectedPriority = 'URGENT';
      } else {
        _selectedPriority = 'MEDIUM';
      }
    } else {
      _selectedPriority = 'MEDIUM';
    }

    _selectedStatus = t?['status'] ?? 'TODO';

    if (t != null && t['due_date'] != null) {
      try {
        _dueDate = DateTime.parse(t['due_date'].toString().split('T')[0]);
      } catch (_) {}
    }

    if (t != null && t['subtasks'] != null && t['subtasks'] is List) {
      for (final st in t['subtasks']) {
        _subtaskCtrls.add(TextEditingController(text: st['title'] ?? ''));
      }
    }
    if (_subtaskCtrls.isEmpty) {
      _subtaskCtrls.add(TextEditingController());
    }

    _initFormContext();
  }

  Future<void> _initFormContext() async {
    try {
      final session = await SessionManager.getUserSession();
      final isSuper = session['role'] == 'Super Admin' || session['role_name'] == 'Super Admin';
      _isSuperAdmin = isSuper;
      final hasAssign = isSuper || await SessionManager.hasPermission('tasks_create_assign');
      _canAssignOthers = hasAssign;

      final empIdStr = session['employee_id']?.toString() ?? session['employeeId']?.toString();
      if (empIdStr != null) {
        _currentEmployeeId = int.tryParse(empIdStr);
      }
      if (_currentEmployeeId == null && session['userId'] != null) {
        for (final e in widget.employees) {
          if (e['user_id'] == session['userId']) {
            _currentEmployeeId = int.tryParse(e['employee_id'].toString());
            break;
          }
        }
      }

      if (!_canAssignOthers) {
        _isPrivateTask = true;
        if (!isEdit && _currentEmployeeId != null) {
          _selectedAssigneeIds.clear();
          _selectedAssigneeIds.add(_currentEmployeeId!);
        }
      }
    } catch (_) {}

    await _fetchDepartments();
    await _loadProjectContext(_selectedProjectId, isInitial: true);
  }

  Future<void> _loadProjectContext(int? projectId, {bool isInitial = false}) async {
    if (projectId == null) {
      List<dynamic> workers = List.from(widget.employees);
      if (_selectedDeptId != null) {
        final deptWorkers = widget.employees.where((e) {
          final dId = int.tryParse(e['department_id']?.toString() ?? '');
          return dId == _selectedDeptId;
        }).toList();
        if (deptWorkers.isNotEmpty) {
          workers = deptWorkers;
        }
      }
      if (mounted) {
        setState(() {
          _availableWorkers = workers;
          if (_departments.isNotEmpty && _selectedDeptId == null) {
            _selectedDeptId = _departments[0]['department_id'];
          }
          _ensureValidAssignees();
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingProjectMembers = true);

    try {
      Map<String, dynamic>? prj;
      for (final p in widget.projects) {
        if ((int.tryParse(p['project_id']?.toString() ?? '') ?? 0) == projectId) {
          prj = p;
          break;
        }
      }
      prj ??= widget.preselectedProject;

      Map<String, dynamic>? details;
      if (widget.projectDetails != null && (int.tryParse(widget.projectDetails!['project_id']?.toString() ?? '') ?? 0) == projectId) {
        details = widget.projectDetails;
      } else {
        final res = await ApiClient.get(Uri.parse('$_apiHost/api/projects/$projectId'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true && data['data'] != null) {
            details = data['data'];
          }
        }
      }

      final prjDeptId = int.tryParse(details?['department_id']?.toString() ?? prj?['department_id']?.toString() ?? '');
      int? matchedDeptId;
      if (prjDeptId != null) {
        for (final d in _departments) {
          if ((int.tryParse(d['department_id']?.toString() ?? '') ?? 0) == prjDeptId) {
            matchedDeptId = prjDeptId;
            break;
          }
        }
      }

      final List<dynamic> projectWorkers = [];
      final Set<int> addedIds = {};

      final leaderId = int.tryParse(details?['project_leader_id']?.toString() ?? prj?['project_leader_id']?.toString() ?? '');
      if (leaderId != null && leaderId > 0) {
        dynamic leaderEmp;
        for (final e in widget.employees) {
          if ((int.tryParse(e['employee_id']?.toString() ?? '') ?? 0) == leaderId) {
            leaderEmp = e;
            break;
          }
        }
        leaderEmp ??= {
          'employee_id': leaderId,
          'full_name': details?['leader_name'] ?? prj?['leader_name'] ?? 'Project Leader',
          'emp_code': 'LEAD',
        };
        final item = Map<String, dynamic>.from(leaderEmp);
        item['role_in_project'] = 'Lead';
        projectWorkers.add(item);
        addedIds.add(leaderId);
      }

      final membersList = (details?['members'] as List<dynamic>?) ?? [];
      for (final m in membersList) {
        final mId = int.tryParse(m['employee_id']?.toString() ?? '') ?? 0;
        if (mId > 0 && !addedIds.contains(mId)) {
          dynamic memberEmp;
          for (final e in widget.employees) {
            if ((int.tryParse(e['employee_id']?.toString() ?? '') ?? 0) == mId) {
              memberEmp = e;
              break;
            }
          }
          memberEmp ??= m;
          final item = Map<String, dynamic>.from(memberEmp);
          if (m['role_in_project'] != null) {
            item['role_in_project'] = m['role_in_project'];
          }
          projectWorkers.add(item);
          addedIds.add(mId);
        }
      }

      if (projectWorkers.isEmpty && prjDeptId != null) {
        final deptEmployees = widget.employees.where((e) {
          final dId = int.tryParse(e['department_id']?.toString() ?? '');
          return dId == prjDeptId;
        }).toList();
        projectWorkers.addAll(deptEmployees);
      }

      if (projectWorkers.isEmpty) {
        projectWorkers.addAll(widget.employees);
      }

      if (mounted) {
        setState(() {
          if (matchedDeptId != null) {
            _selectedDeptId = matchedDeptId;
          }
          _availableWorkers = projectWorkers;
          _isLoadingProjectMembers = false;
          _ensureValidAssignees();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableWorkers = widget.employees;
          _isLoadingProjectMembers = false;
          _ensureValidAssignees();
        });
      }
    }
  }

  void _ensureValidAssignees() {
    if (!_canAssignOthers && _currentEmployeeId != null) {
      _selectedAssigneeIds.clear();
      _selectedAssigneeIds.add(_currentEmployeeId!);
      return;
    }

    if (isEdit) {
      if (_selectedAssigneeIds.isEmpty && _availableWorkers.isNotEmpty) {
        final firstId = int.tryParse(_availableWorkers.first['employee_id']?.toString() ?? '');
        if (firstId != null) _selectedAssigneeIds.add(firstId);
      }
      return;
    }

    final valid = _selectedAssigneeIds.where((id) {
      return _availableWorkers.any((w) => (int.tryParse(w['employee_id']?.toString() ?? '') ?? 0) == id);
    }).toList();

    if (valid.isNotEmpty) {
      _selectedAssigneeIds.clear();
      _selectedAssigneeIds.addAll(valid);
    } else if (_availableWorkers.isNotEmpty) {
      _selectedAssigneeIds.clear();
      final firstId = int.tryParse(_availableWorkers.first['employee_id']?.toString() ?? '');
      if (firstId != null) _selectedAssigneeIds.add(firstId);
    } else {
      _selectedAssigneeIds.clear();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _tagsCtrl.dispose();
    for (final c in _subtaskCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await ApiClient.get(Uri.parse('$_apiHost/api/hr/departments'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _departments = data['data'];
            if (_departments.isNotEmpty && _selectedDeptId == null) {
              _selectedDeptId = _departments[0]['department_id'];
            }
            _isLoadingDepts = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() {
      _departments = [
        {'department_id': 1, 'department_name': 'Engineering'},
        {'department_id': 2, 'department_name': 'Design'},
        {'department_id': 3, 'department_name': 'Product'},
        {'department_id': 4, 'department_name': 'Operations'},
      ];
      _selectedDeptId = 1;
      _isLoadingDepts = false;
    });
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) {
        final isDark = ThemeController.isDarkMode.value;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF059669), onPrimary: Colors.white),
          )
              : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF059669), onPrimary: Colors.white),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_dueDate.isBefore(_startDate)) {
            _dueDate = _startDate.add(const Duration(days: 3));
          }
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAssigneeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 Assignee!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final hours = double.tryParse(_hoursCtrl.text.trim()) ?? 8.0;
      final subtasks = _subtaskCtrls
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final dueDateStr = '${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}';

      if (isEdit) {
        final res = await ApiClient.put(
          Uri.parse('$_apiHost/api/tasks/${widget.task!['task_id']}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'assigned_to': _selectedAssigneeIds.first,
            'assignees': _selectedAssigneeIds,
            'project_id': _selectedProjectId,
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'priority': _selectedPriority,
            'status': _selectedStatus,
            'due_date': dueDateStr,
            'estimated_hours': hours,
          }),
        );

        if (res.statusCode == 200) {
          widget.onTaskSaved?.call();
          if (mounted) {
            Navigator.pop(context, true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Task updated successfully!'),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          final err = jsonDecode(res.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(err['message'] ?? 'Failed to update task'), backgroundColor: Colors.redAccent),
            );
          }
        }
      } else {
        final res = await ApiClient.post(
          Uri.parse('$_apiHost/api/tasks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'assigned_to': _selectedAssigneeIds.first,
            'assignees': _selectedAssigneeIds,
            'project_id': _selectedProjectId,
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'priority': _selectedPriority,
            'status': _selectedStatus,
            'due_date': dueDateStr,
            'estimated_hours': hours,
            'is_private': _isPrivateTask ? 1 : 0,
            'subtasks': subtasks,
          }),
        );

        if (res.statusCode == 201 || res.statusCode == 200) {
          widget.onTaskSaved?.call();
          if (mounted) {
            Navigator.pop(context, true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Task created successfully!'),
                backgroundColor: Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          final err = jsonDecode(res.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(err['message'] ?? 'Failed to create task'), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration(String hint, IconData icon, bool isDark) {
    return InputDecoration(
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF059669)),
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
        fontSize: 13,
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF059669), width: 1.6),
      ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPriorityChip(String value, String label, Color color) {
    final isSelected = _selectedPriority == value;
    final isDark = ThemeController.isDarkMode.value;

    return InkWell(
      onTap: () => setState(() => _selectedPriority = value),
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.3 : 0.15)
              : (isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isAssignedToThisTask {
    if (!isEdit) return true; // new task being created
    if (_isSuperAdmin) return true; // Admin can always manage
    if (_currentEmployeeId == null || widget.task == null) return false;
    final assignedTo = widget.task!['assigned_to'];
    if (assignedTo != null && assignedTo.toString() == _currentEmployeeId.toString()) return true;
    final assignees = widget.task!['assignees'];
    if (assignees is List) {
      for (final a in assignees) {
        if (a is Map && a['employee_id']?.toString() == _currentEmployeeId.toString()) return true;
        if (a.toString() == _currentEmployeeId.toString()) return true;
      }
    }
    return false;
  }

  Widget _buildStatusChip(String value, String label, Color color) {
    final isSelected = _selectedStatus.toUpperCase() == value.toUpperCase();
    final isDark = ThemeController.isDarkMode.value;
    final canChange = _isAssignedToThisTask;

    return Tooltip(
      message: canChange ? 'Select status' : 'Only assigned employee can modify task status',
      child: InkWell(
        onTap: canChange ? () => setState(() => _selectedStatus = value) : null,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: isDark ? 0.3 : 0.15)
                : (isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSelected ? color : (canChange ? Colors.grey : Colors.grey.withValues(alpha: 0.4)),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : (canChange ? (isDark ? Colors.white70 : const Color(0xFF475569)) : Colors.grey),
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (!canChange) ...[
                const SizedBox(width: 5),
                Icon(Icons.lock_outline_rounded, size: 12, color: Colors.grey.withValues(alpha: 0.7)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveRow({required bool isMobile, required Widget first, required Widget second}) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          first,
          const SizedBox(height: 14),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 16),
        Expanded(child: second),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textTitle,
    required Color textSub,
    required List<Widget> children,
  }) {
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                  ),
                  child: Icon(icon, color: const Color(0xFF059669), size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: textTitle, fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: textSub, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textTitle, Color textSub, Color borderColor, bool isDark, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : const Color(0xFF334155), size: 20),
            tooltip: 'Back',
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
                  isEdit ? 'Edit Task Deliverable' : 'Create New Task',
                  style: TextStyle(
                    color: textTitle,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isEdit
                      ? 'Task #${widget.task?['task_id']} • Update deliverables, priority & deadline'
                      : 'Define requirements, assign team owner, priority & checklist',
                  style: TextStyle(color: textSub, fontSize: isMobile ? 11 : 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Cancel', style: TextStyle(color: textSub, fontSize: 13)),
            ),
            const SizedBox(width: 10),
          ],
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveTask,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20,
                vertical: isMobile ? 8 : 10,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
            ),
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 16),
            label: Text(
              _isSaving ? 'Saving...' : (isEdit ? (isMobile ? 'Save' : 'Save Changes') : (isMobile ? 'Create' : 'Create Task')),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);

    final Widget mainContent = SafeArea(
      child: Column(
        children: [
          // 1. TOP HEADER (Botanical ERP Theme)
          _buildHeader(textTitle, textSub, cardBorder, isDark, isMobile),

          // 2. FORM CONTENT
          Expanded(
            child: Form(
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
                        // CARD 1: Task Scope & Identification
                        _buildCard(
                          title: 'Task Scope & Deliverable Details',
                          subtitle: 'Task title, technical description, project link and department',
                          icon: Icons.assignment_outlined,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            // Task Title
                            _buildLabel('Task Title *', isDark),
                            TextFormField(
                              controller: _titleCtrl,
                              style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.w600),
                              decoration: _inputDecoration('e.g. Implement OAuth Flow, Firmware Flash', Icons.title_rounded, isDark),
                              validator: (v) => v!.trim().isEmpty ? 'Task title is required' : null,
                            ),
                            const SizedBox(height: 14),

                            // Description / Specs
                            _buildLabel('Technical Description / Acceptance Criteria', isDark),
                            TextFormField(
                              controller: _descCtrl,
                              minLines: 3,
                              maxLines: 5,
                              style: TextStyle(color: textTitle, fontSize: 13),
                              decoration: _inputDecoration('Enter detailed requirements, steps or reference notes...', Icons.notes_rounded, isDark),
                            ),
                            const SizedBox(height: 14),

                            // Row: Department & Project
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Department *', isDark),
                                  DropdownButtonFormField<int>(
                                    value: (_departments.any((dept) => dept['department_id'] == _selectedDeptId))
                                        ? _selectedDeptId
                                        : null,
                                    isExpanded: true,
                                    dropdownColor: cardBg,
                                    style: TextStyle(color: textTitle, fontSize: 13.5),
                                    decoration: _inputDecoration('Department', Icons.apartment_rounded, isDark),
                                    items: _departments.map<DropdownMenuItem<int>>((dept) {
                                      return DropdownMenuItem<int>(
                                        value: dept['department_id'] as int,
                                        child: Text(
                                            dept['name'] ?? dept['department_name'] ?? 'Department',
                                          style: TextStyle(color: textTitle, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() => _selectedDeptId = val);
                                      if (_selectedProjectId == null) {
                                        _loadProjectContext(null);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              second: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel(
                                    widget.preselectedProjectId != null ? 'Project *' : 'Project (Optional)',
                                    isDark,
                                  ),
                                  DropdownButtonFormField<int?>(
                                    value: (_selectedProjectId != null && widget.projects.any((p) => p['project_id'] == _selectedProjectId))
                                        ? _selectedProjectId
                                        : (widget.preselectedProjectId != null && widget.projects.any((p) => p['project_id'] == widget.preselectedProjectId)
                                            ? widget.preselectedProjectId
                                            : null),
                                    isExpanded: true,
                                    dropdownColor: cardBg,
                                    style: TextStyle(color: textTitle, fontSize: 13.5),
                                    decoration: _inputDecoration('Project', Icons.folder_open_outlined, isDark),
                                    items: [
                                      if (widget.preselectedProjectId == null)
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text(
                                            'None (General Task / No Project)',
                                            style: TextStyle(fontSize: 13, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ...widget.projects.map<DropdownMenuItem<int?>>((p) {
                                        return DropdownMenuItem<int?>(
                                          value: p['project_id'],
                                          child: Text(
                                            '${p['project_code']} - ${p['project_name']}',
                                            style: TextStyle(color: textTitle, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (val) {
                                      setState(() => _selectedProjectId = val);
                                      _loadProjectContext(val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // CARD 2: Assignee, Priority & Schedule
                        _buildCard(
                          title: 'Assignee, Priority & Schedule',
                          subtitle: 'Task owner, priority rating, timeline dates and estimated hours',
                          icon: Icons.tune_rounded,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            // Row: Multi-Worker Assignee & Estimated Hours
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _buildLabel('Assigned Workers (${_selectedAssigneeIds.length}) *', isDark),
                                      if (!_canAssignOthers) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.lock_rounded, size: 10, color: Colors.blue),
                                              SizedBox(width: 4),
                                              Text(
                                                'Self Personal Task',
                                                style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else if (_selectedProjectId != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Project Team',
                                            style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (_isLoadingProjectMembers)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                        )
                                      else if (_canAssignOthers && _availableWorkers.isNotEmpty)
                                        PopupMenuButton<int>(
                                          tooltip: 'Add Worker',
                                          icon: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.person_add_alt_1_rounded, size: 14, color: Color(0xFF10B981)),
                                                SizedBox(width: 4),
                                                Text('+ Add Worker', style: TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                          onSelected: (empId) {
                                            if (!_selectedAssigneeIds.contains(empId)) {
                                              setState(() => _selectedAssigneeIds.add(empId));
                                            }
                                          },
                                          itemBuilder: (context) {
                                            return _availableWorkers.map<PopupMenuItem<int>>((e) {
                                              final empId = int.tryParse(e['employee_id'].toString()) ?? 0;
                                              final isSelected = _selectedAssigneeIds.contains(empId);
                                              return PopupMenuItem<int>(
                                                value: empId,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                                      size: 18,
                                                      color: isSelected ? const Color(0xFF10B981) : Colors.grey,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '${e['full_name']} (${e['emp_code'] ?? 'EMP'})',
                                                        style: TextStyle(
                                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (e['role_in_project'] != null)
                                                      Container(
                                                        margin: const EdgeInsets.only(left: 6),
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          e['role_in_project'].toString(),
                                                          style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }).toList();
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (_selectedAssigneeIds.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline_rounded, size: 16, color: textSub),
                                          const SizedBox(width: 8),
                                          Text('Tap "+ Add Worker" to assign staff', style: TextStyle(color: textSub, fontSize: 12)),
                                        ],
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _selectedAssigneeIds.map((empId) {
                                        final emp = _availableWorkers.firstWhere(
                                          (e) => (int.tryParse(e['employee_id'].toString()) ?? 0) == empId,
                                          orElse: () => widget.employees.firstWhere(
                                            (e) => (int.tryParse(e['employee_id'].toString()) ?? 0) == empId,
                                            orElse: () => {'full_name': 'Worker #$empId', 'emp_code': 'EMP'},
                                          ),
                                        );
                                        final name = (emp['full_name'] ?? 'Worker').toString();
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 10,
                                                backgroundColor: const Color(0xFF10B981),
                                                child: Text(
                                                  name.isNotEmpty ? name[0].toUpperCase() : 'W',
                                                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '$name (${emp['emp_code'] ?? 'EMP'})',
                                                style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                              if (_canAssignOthers && _selectedAssigneeIds.length > 1) ...[
                                                const SizedBox(width: 6),
                                                InkWell(
                                                  onTap: () {
                                                    setState(() => _selectedAssigneeIds.remove(empId));
                                                  },
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Icon(Icons.close_rounded, size: 14, color: textSub),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                              second: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Estimated Hours (Hrs)', isDark),
                                  TextFormField(
                                    controller: _hoursCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: TextStyle(color: textTitle, fontSize: 13.5),
                                    decoration: _inputDecoration('8.0', Icons.access_time_rounded, isDark),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Status Chips (Integrated from Quick Edit Modal)
                            _buildLabel('Current Status', isDark),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildStatusChip('TODO', 'To Do', const Color(0xFF3B82F6)),
                                _buildStatusChip('IN_PROGRESS', 'In Progress', const Color(0xFFF59E0B)),
                                _buildStatusChip('DONE', 'Done / Completed', const Color(0xFF10B981)),
                              ],
                            ),
                            if (isEdit && !_isAssignedToThisTask) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 12, color: isDark ? Colors.amber[300] : Colors.amber[800]),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Only assigned employee can modify task status',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.amber[300] : Colors.amber[800],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),

                            // Priority Chips
                            _buildLabel('Priority Level', isDark),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildPriorityChip('LOW', 'Low', const Color(0xFF10B981)),
                                _buildPriorityChip('MEDIUM', 'Medium', const Color(0xFFF59E0B)),
                                _buildPriorityChip('HIGH', 'High', const Color(0xFFF97316)),
                                _buildPriorityChip('URGENT', 'Urgent', const Color(0xFFEF4444)),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Row: Start Date & Due Date
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Start Date *', isDark),
                                  InkWell(
                                    onTap: () => _pickDate(isStart: true),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF3B82F6), size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _formatDate(_startDate),
                                              style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          Icon(Icons.calendar_month_outlined, size: 16, color: textSub),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              second: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Target Due Date *', isDark),
                                  InkWell(
                                    onTap: () => _pickDate(isStart: false),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today_outlined, color: Color(0xFFEF4444), size: 17),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _formatDate(_dueDate),
                                              style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          Icon(Icons.calendar_month_outlined, size: 16, color: textSub),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // CARD 3: Checklist & Action Items
                        _buildCard(
                          title: 'Checklist / Subtasks (Optional)',
                          subtitle: 'Break down deliverable into verifiable action items',
                          icon: Icons.checklist_rounded,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                        textSub: textSub,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Action Items (${_subtaskCtrls.length})', style: TextStyle(color: textSub, fontSize: 12)),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _subtaskCtrls.add(TextEditingController());
                                    });
                                  },
                                  icon: const Icon(Icons.add, size: 16, color: Color(0xFF059669)),
                                  label: const Text('Add Step', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12.5)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (int i = 0; i < _subtaskCtrls.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF059669).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _subtaskCtrls[i],
                                        style: TextStyle(color: textTitle, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Item ${i + 1}: e.g. Flash bootloader, run hardware bench test...',
                                          hintStyle: TextStyle(color: isDark ? Colors.white24 : const Color(0xFF94A3B8), fontSize: 12.5),
                                          filled: true,
                                          fillColor: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(color: Color(0xFF059669), width: 1.4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_subtaskCtrls.length > 1) ...[
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                                        tooltip: 'Remove',
                                        onPressed: () {
                                          setState(() {
                                            _subtaskCtrls.removeAt(i);
                                          });
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. MOBILE BOTTOM ACTION BAR
          if (isMobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                border: Border(top: BorderSide(color: cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: cardBorder),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: textSub, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSaving ? null : _saveTask,
                      icon: _isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(
                        _isSaving ? 'Saving...' : (isEdit ? 'Save Changes' : 'Create Task'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (isMobile) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        body: mainContent,
      );
    }

    return Scaffold(
      body: BotanicalBackground(cleanDesktop: MediaQuery.sizeOf(context).width >= 900, 
        showThemeToggle: false,
        child: mainContent,
      ),
    );
  }
}