import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../core/theme/theme_controller.dart';
import 'task_details_screen.dart';
import 'project_edit_screen.dart';
import 'task_form_screen.dart';


class ProjectTasksScreen extends StatefulWidget {
  const ProjectTasksScreen({super.key});

  @override
  State<ProjectTasksScreen> createState() => _ProjectTasksScreenState();
}

class _ProjectTasksScreenState extends State<ProjectTasksScreen> with SingleTickerProviderStateMixin {
  // Main view mode: 0 = Projects Hub, 1 = General Tasks (Kanban)
  int _activeTopView = 0;

  List<dynamic> _projects = [];
  List<dynamic> _allTasks = [];
  List<dynamic> _employees = [];
  List<dynamic> _departments = [];
  bool _isLoading = true;

  // Projects View: Search & Department Filter
  String _selectedDeptFilter = 'ALL';
  String _projectSearchQuery = '';
  final TextEditingController _projectSearchController = TextEditingController();

  // Selected Project (Detailed Workspace)
  Map<String, dynamic>? _selectedProject;
  Map<String, dynamic>? _projectDetails;
  bool _isLoadingDetails = false;

  late TabController _tabController;

  // Search & Status Filter (Screenshot 3 style)
  String _taskSearchQuery = '';
  String _selectedStatusFilter = 'ALL'; // 'ALL', 'TODO', 'IN_PROGRESS', 'REVIEW', 'DONE'
  final TextEditingController _taskSearchController = TextEditingController();

  // General Tasks Board: Search, filters & sorting
  String _genTaskSearchQuery = '';
  final TextEditingController _genTaskSearchController = TextEditingController();
  String _genPriorityFilter = 'ALL';
  String _genAssigneeFilter = 'ALL';
  String _genSortOption = 'SMART'; // SMART, DUE_DATE, PRIORITY, NEWEST
  bool _genOnlyOverdue = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _taskSearchController.dispose();
    _genTaskSearchController.dispose();
    _projectSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchProjects(),
      _fetchAllTasks(),
      _fetchEmployees(),
      _fetchDepartments(),
    ]);
    setState(() => _isLoading = false);
  }

  // 1. PROJECTS MANGWANA
  Future<void> _fetchProjects() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/projects'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() => _projects = data['data'] ?? []);
        }
      }
    } catch (_) {}
  }

  // 1.1 DEPARTMENTS MANGWANA
  Future<void> _fetchDepartments() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() => _departments = data['data'] ?? []);
        }
      }
    } catch (_) {}
  }

  // 1.2 DEPARTMENT FILTER LIST WITH LIVE PROJECT COUNTS
  List<Map<String, dynamic>> _getDepartmentFilterList() {
    final Map<String, Map<String, dynamic>> deptMap = {};

    // First populate from fetched departments
    for (final d in _departments) {
      final name = (d['name'] ?? d['department_name'] ?? '').toString().trim();
      final id = d['department_id']?.toString() ?? '';
      if (name.isNotEmpty) {
        deptMap[name.toLowerCase()] = {
          'id': id,
          'name': name,
          'count': 0,
        };
      }
    }

    // Next count projects & dynamically add any department assigned to a project
    int unassignedCount = 0;
    for (final p in _projects) {
      final deptName = (p['department_name'] ?? '').toString().trim();
      final deptId = p['department_id']?.toString() ?? '';
      if (deptName.isNotEmpty) {
        final key = deptName.toLowerCase();
        if (!deptMap.containsKey(key)) {
          deptMap[key] = {
            'id': deptId,
            'name': deptName,
            'count': 0,
          };
        }
        final currentCount = deptMap[key]!['count'] as int? ?? 0;
        deptMap[key]!['count'] = currentCount + 1;
      } else {
        unassignedCount++;
      }
    }

    final List<Map<String, dynamic>> list = [
      {
        'key': 'ALL',
        'name': 'All Departments',
        'count': _projects.length,
        'icon': Icons.grid_view_rounded,
      }
    ];

    for (final entry in deptMap.values) {
      list.add({
        'key': entry['name'],
        'name': entry['name'],
        'count': entry['count'],
        'icon': Icons.apartment_rounded,
      });
    }

    if (unassignedCount > 0) {
      list.add({
        'key': 'UNASSIGNED',
        'name': 'General / Other',
        'count': unassignedCount,
        'icon': Icons.folder_outlined,
      });
    }

    return list;
  }

  // 1.3 FILTERED PROJECTS GETTER
  List<dynamic> get _filteredProjects {
    return _projects.where((p) {
      // A. Department Filter
      if (_selectedDeptFilter != 'ALL') {
        final deptName = (p['department_name'] ?? '').toString().trim().toLowerCase();
        if (_selectedDeptFilter == 'UNASSIGNED') {
          if (deptName.isNotEmpty) return false;
        } else {
          if (deptName != _selectedDeptFilter.trim().toLowerCase()) return false;
        }
      }

      // B. Search Filter
      if (_projectSearchQuery.trim().isNotEmpty) {
        final q = _projectSearchQuery.trim().toLowerCase();
        final name = (p['project_name'] ?? '').toString().toLowerCase();
        final code = (p['project_code'] ?? '').toString().toLowerCase();
        final client = (p['client_name'] ?? '').toString().toLowerCase();
        final leader = (p['leader_name'] ?? '').toString().toLowerCase();
        final dept = (p['department_name'] ?? '').toString().toLowerCase();
        final desc = (p['description'] ?? '').toString().toLowerCase();

        final matches = name.contains(q) ||
            code.contains(q) ||
            client.contains(q) ||
            leader.contains(q) ||
            dept.contains(q) ||
            desc.contains(q);
        if (!matches) return false;
      }

      return true;
    }).toList();
  }

  // ================= ⚡ GENERAL TASKS: LOGIC & FILTERS =================
  List<dynamic> get _generalTasks =>
      _allTasks.where((t) => t['project_id'] == null).toList();

  bool get _hasGeneralTaskFilters =>
      _genTaskSearchQuery.trim().isNotEmpty ||
      _genPriorityFilter != 'ALL' ||
      _genAssigneeFilter != 'ALL' ||
      _genOnlyOverdue;

  DateTime get _todayDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _parseTaskDueDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _taskStatus(dynamic task) =>
      (task['status'] ?? 'TODO').toString().toUpperCase();

  String _taskStatusLabel(String status) {
    switch (status) {
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'DONE':
        return 'Completed';
      default:
        return 'To Do';
    }
  }

  bool _isTaskOverdue(dynamic task) {
    if (_taskStatus(task) == 'DONE') return false;
    final due = _parseTaskDueDate(task['due_date']);
    return due != null && due.isBefore(_todayDate);
  }

  int _generalPriorityRank(dynamic priority) {
    switch ((priority ?? 'MEDIUM').toString().toUpperCase()) {
      case 'URGENT':
        return 0;
      case 'HIGH':
        return 1;
      case 'LOW':
        return 3;
      default:
        return 2;
    }
  }

  Color _generalPriorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'URGENT':
        return const Color(0xFFEF4444);
      case 'HIGH':
        return const Color(0xFFF97316);
      case 'LOW':
        return const Color(0xFF10B981);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  int _compareTaskDueDates(dynamic a, dynamic b) {
    final dateA = _parseTaskDueDate(a);
    final dateB = _parseTaskDueDate(b);
    if (dateA == null && dateB == null) return 0;
    if (dateA == null) return 1; // Tasks without a deadline go last
    if (dateB == null) return -1;
    return dateA.compareTo(dateB);
  }

  int _compareGeneralTasks(dynamic a, dynamic b) {
    final idA = int.tryParse(a['task_id']?.toString() ?? '') ?? 0;
    final idB = int.tryParse(b['task_id']?.toString() ?? '') ?? 0;
    final newestFirst = idB.compareTo(idA);

    switch (_genSortOption) {
      case 'NEWEST':
        return newestFirst;
      case 'PRIORITY':
        final priority = _generalPriorityRank(a['priority'])
            .compareTo(_generalPriorityRank(b['priority']));
        return priority != 0 ? priority : _compareTaskDueDates(a['due_date'], b['due_date']);
      case 'DUE_DATE':
        final due = _compareTaskDueDates(a['due_date'], b['due_date']);
        return due != 0
            ? due
            : _generalPriorityRank(a['priority'])
                .compareTo(_generalPriorityRank(b['priority']));
      case 'SMART':
      default:
        final overdueA = _isTaskOverdue(a);
        final overdueB = _isTaskOverdue(b);
        if (overdueA != overdueB) return overdueA ? -1 : 1;
        final due = _compareTaskDueDates(a['due_date'], b['due_date']);
        if (due != 0) return due;
        final priority = _generalPriorityRank(a['priority'])
            .compareTo(_generalPriorityRank(b['priority']));
        return priority != 0 ? priority : newestFirst;
    }
  }

  List<dynamic> get _filteredGeneralTasks {
    final query = _genTaskSearchQuery.trim().toLowerCase();
    final filtered = _generalTasks.where((task) {
      if (query.isNotEmpty) {
        final haystack = [
          task['title'],
          task['description'],
          task['assigned_worker'],
          task['emp_code'],
          task['task_id'],
          task['task_id'] == null ? null : '#${task['task_id']}',
        ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(' ');
        if (!haystack.contains(query)) return false;
      }

      final priority = (task['priority'] ?? 'MEDIUM').toString().toUpperCase();
      if (_genPriorityFilter != 'ALL' && priority != _genPriorityFilter) {
        return false;
      }

      final worker = (task['assigned_worker'] ?? '').toString().trim();
      if (_genAssigneeFilter != 'ALL' &&
          worker.toLowerCase() != _genAssigneeFilter.toLowerCase()) {
        return false;
      }

      if (_genOnlyOverdue && !_isTaskOverdue(task)) return false;

      return true;
    }).toList();

    filtered.sort(_compareGeneralTasks);
    return filtered;
  }

  List<String> get _generalTaskAssignees {
    final names = <String>{};
    for (final task in _generalTasks) {
      final name = (task['assigned_worker'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
    final list = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  void _resetGeneralTaskFilters() {
    _genTaskSearchController.clear();
    setState(() {
      _genTaskSearchQuery = '';
      _genPriorityFilter = 'ALL';
      _genAssigneeFilter = 'ALL';
      _genSortOption = 'SMART';
      _genOnlyOverdue = false;
    });
  }

  // 2. SAARE TASKS MANGWANA
  Future<void> _fetchAllTasks() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/tasks'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() => _allTasks = data['data'] ?? []);
        }
      }
    } catch (_) {}
  }

  // 3. EMPLOYEES MANGWANA
  Future<void> _fetchEmployees() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() => _employees = data['data'] ?? []);
        }
      }
    } catch (_) {}
  }

  // 4. PROJECT DETAILS MANGWANA
  Future<void> _fetchProjectDetails(int projectId) async {
    setState(() => _isLoadingDetails = true);
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/projects/$projectId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _projectDetails = data['data'];
            _isLoadingDetails = false;
          });
        }
      }
    } catch (_) {
      setState(() => _isLoadingDetails = false);
    }
  }

  // 5. TASK STATUS UPDATE (TODO -> IN_PROGRESS -> DONE)
  Future<void> _updateTaskStatus(int taskId, String newStatus) async {
    try {
      final res = await http.put(
        Uri.parse('http://localhost:5000/api/tasks/$taskId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        _fetchAllTasks();
        if (_selectedProject != null) {
          _fetchProjectDetails(_selectedProject!['project_id']);
        }
        _fetchProjects();
      }
    } catch (_) {}
  }

  // 6. SUBTASK STATUS TICK / UNTICK
  Future<void> _toggleSubtask(int subtaskId, bool isCompleted) async {
    try {
      final res = await http.put(
        Uri.parse('http://localhost:5000/api/projects/subtasks/$subtaskId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'is_completed': isCompleted}),
      );
      if (res.statusCode == 200) {
        _fetchAllTasks();
        if (_selectedProject != null) {
          _fetchProjectDetails(_selectedProject!['project_id']);
        }
      }
    } catch (_) {}
  }

  // ================= 🗑️ MAST ULTRA-CLEAN DELETE PROJECT MODAL =================
  void _confirmDeleteProject(Map<String, dynamic> prj) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        final dialogBg = isDark ? const Color(0xFF0B132B) : Colors.white;
        final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: dialogBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Warning Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 36),
                ),
                const SizedBox(height: 18),

                Text(
                  'Delete Project?',
                  style: TextStyle(color: textTitle, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(color: textSub, fontSize: 13, height: 1.45),
                    children: [
                      const TextSpan(text: 'Are you sure you want to delete '),
                      TextSpan(
                        text: '"${prj['project_name']}"',
                        style: TextStyle(color: textTitle, fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: ' (${prj['project_code']})?\n\n',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                      const TextSpan(
                        text: '⚠️ All associated tasks, subtasks checklist, timesheets and deliverables will be permanently deleted.',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: textSub.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Keep Project', style: TextStyle(color: textTitle, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            final res = await http.delete(
                              Uri.parse('http://localhost:5000/api/projects/${prj['project_id']}'),
                            );
                            if (res.statusCode == 200) {
                              if (_selectedProject != null && _selectedProject!['project_id'] == prj['project_id']) {
                                setState(() => _selectedProject = null);
                              }
                              _refreshAll();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Project deleted successfully!'),
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
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Yes, Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= ✏️ EDIT PROJECT (DEDICATED FULL SCREEN) =================
  void _openEditProjectDialog(Map<String, dynamic> prj) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectEditScreen(
          project: prj,
          onProjectUpdated: () {
            _fetchProjects();
            if (_selectedProject != null) {
              _fetchProjectDetails(_selectedProject!['project_id']);
            }
          },
        ),
      ),
    );
    if (res == true) {
      _fetchProjects();
      if (_selectedProject != null) {
        _fetchProjectDetails(_selectedProject!['project_id']);
      }
    }
  }
  // ================= 🗑️ MAST DELETE TASK CONFIRMATION MODAL =================
  void _confirmDeleteTask(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        final dialogBg = isDark ? const Color(0xFF0B132B) : Colors.white;
        final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: dialogBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 32),
                ),
                const SizedBox(height: 16),
                Text('Delete Task?', style: TextStyle(color: textTitle, fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to remove "${task['title']}"?\nAll associated subtasks and checklist items will be removed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSub, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: TextStyle(color: textTitle)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            final res = await http.delete(
                              Uri.parse('http://localhost:5000/api/tasks/${task['task_id']}'),
                            );
                            print("DELETE STATUS: ${res.statusCode} -> ${res.body}");

                            if (res.statusCode == 200) {
                              _refreshAll();
                              if (_selectedProject != null) {
                                _fetchProjectDetails(_selectedProject!['project_id']);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Task deleted successfully!'), backgroundColor: Colors.redAccent),
                              );
                            } else {
                              // Agar 404 ya 500 error aaye toh screen par red message aayega!
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Delete Error: ${res.statusCode} - ${res.body}'), backgroundColor: Colors.red),
                              );
                            }
                          } catch (_) {}
                        },
                        child: const Text('Delete Task', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= ➕ ADD COMPONENT / MATERIAL DIALOG =================
  void _openAddComponentDialog(int projectId) {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    String selectedUnit = 'PCS';
    String selectedStatus = 'Required';
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final inputBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final inputBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);
          final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
          final subColor = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 480,
              decoration: BoxDecoration(
                color: dialogBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: inputBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 10)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.memory_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Add Project Component', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  SizedBox(height: 2),
                                  Text('Assign raw material or hardware component', style: TextStyle(color: Colors.white, fontSize: 11)),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.pop(ctx),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Form Body
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Component Name *', style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: nameCtrl,
                                style: TextStyle(color: titleColor, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'e.g. M10 High Tensile Bolts, Mild Steel Sheet 10mm',
                                  filled: true,
                                  fillColor: inputBg,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                ),
                                validator: (v) => v!.trim().isEmpty ? 'Component name is required' : null,
                              ),
                              const SizedBox(height: 14),

                              // Quantity & Unit
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Quantity Required *', style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          controller: qtyCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: TextStyle(color: titleColor, fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText: 'e.g. 500',
                                            filled: true,
                                            fillColor: inputBg,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                          ),
                                          validator: (v) => v!.trim().isEmpty ? 'Enter qty' : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 1,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Unit', style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        DropdownButtonFormField<String>(
                                          value: selectedUnit,
                                          dropdownColor: dialogBg,
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: inputBg,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                          ),
                                          items: ['PCS', 'KG', 'MTR', 'LTR', 'SET', 'BOX', 'NOS'].map((u) {
                                            return DropdownMenuItem(value: u, child: Text(u, style: TextStyle(color: titleColor, fontSize: 12)));
                                          }).toList(),
                                          onChanged: (val) => setModalState(() => selectedUnit = val ?? 'PCS'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Status Dropdown
                              Text('Initial Status', style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: selectedStatus,
                                dropdownColor: dialogBg,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: inputBorder)),
                                ),
                                items: ['Required', 'Issued', 'Consumed', 'Returned'].map((s) {
                                  return DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: titleColor, fontSize: 12)));
                                }).toList(),
                                onChanged: (val) => setModalState(() => selectedStatus = val ?? 'Required'),
                              ),
                              const SizedBox(height: 20),

                              // Action Buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subColor))),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                      if (formKey.currentState!.validate()) {
                                        setModalState(() => isSaving = true);
                                        try {
                                          final res = await http.post(
                                            Uri.parse('http://localhost:5000/api/projects/$projectId/materials'),
                                            headers: {'Content-Type': 'application/json'},
                                            body: jsonEncode({
                                              'material_name': nameCtrl.text.trim(),
                                              'unit': selectedUnit,
                                              'quantity_required': double.tryParse(qtyCtrl.text.trim()) ?? 1.0,
                                              'cost_per_unit': double.tryParse(costCtrl.text.trim()) ?? 0.0,
                                            }),
                                          );
                                          if (res.statusCode == 201) {
                                            Navigator.pop(ctx);
                                            _fetchProjectDetails(projectId);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Component added successfully!'), backgroundColor: Color(0xFF10B981)),
                                            );
                                          }
                                        } catch (_) {}
                                        setModalState(() => isSaving = false);
                                      }
                                    },
                                    child: isSaving
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Add Component', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ================= 🗑️ DELETE COMPONENT CONFIRMATION MODAL =================
  void _confirmDeleteComponent(Map<String, dynamic> m) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        final dialogBg = isDark ? const Color(0xFF0B132B) : Colors.white;
        final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white.withValues(alpha: 0.65) : const Color(0xFF64748B);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: dialogBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 25, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 28),
                ),
                const SizedBox(height: 14),
                Text('Remove Component?', style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Are you sure you want to remove "${m['material_name']}" from this project?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSub, fontSize: 12.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: TextStyle(color: textTitle)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            final res = await http.delete(
                              Uri.parse('http://localhost:5000/api/projects/materials/${m['material_id']}'),
                            );
                            if (res.statusCode == 200) {
                              if (_selectedProject != null) {
                                _fetchProjectDetails(_selectedProject!['project_id']);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Component removed successfully!'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } catch (_) {}
                        },
                        child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= ✏️ EDIT TASK (DEDICATED FULL SCREEN) =================
  void _openEditTaskDialog(Map<String, dynamic> task) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          task: task,
          projects: _projects,
          employees: _employees,
          onTaskSaved: () {
            _refreshAll();
            if (_selectedProject != null) {
              _fetchProjectDetails(_selectedProject!['project_id']);
            }
          },
        ),
      ),
    );
    if (res == true) {
      _refreshAll();
      if (_selectedProject != null) {
        _fetchProjectDetails(_selectedProject!['project_id']);
      }
    }
  }

  // ================= 🔍 FULL TASK DETAILS & CHECKLIST MODAL =================
  
  void _openAddSubtaskDialog(dynamic taskId, String? taskTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailsScreen(
          taskId: taskId,
          projectId: _selectedProject?['project_id'],
          employees: _employees,
          onTaskUpdated: () {
            _refreshAll();
            if (_selectedProject != null) {
              _fetchProjectDetails(_selectedProject!['project_id']);
            }
          },
        ),
      ),
    ).then((_) {
      _refreshAll();
      if (_selectedProject != null) {
        _fetchProjectDetails(_selectedProject!['project_id']);
      }
    });
  }

  void _openTaskDetailsDialog(dynamic task) {
    final Map<String, dynamic> taskMap = task is Map ? Map<String, dynamic>.from(task) : <String, dynamic>{};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailsScreen(
          taskId: taskMap['task_id'],
          initialTask: taskMap,
          projectId: taskMap['project_id'] ?? _selectedProject?['project_id'],
          employees: _employees,
          onTaskUpdated: () {
            _refreshAll();
            if (_selectedProject != null) {
              _fetchProjectDetails(_selectedProject!['project_id']);
            }
          },
        ),
      ),
    ).then((_) {
      _refreshAll();
      if (_selectedProject != null) {
        _fetchProjectDetails(_selectedProject!['project_id']);
      }
    });
  }

  // ================= 📝 CREATE TASK (DEDICATED FULL SCREEN) =================
  void _openCreateTaskDialog({int? preselectedProjectId}) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          preselectedProjectId: preselectedProjectId,
          projects: _projects,
          employees: _employees,
          onTaskSaved: () {
            _refreshAll();
            if (_selectedProject != null) {
              _fetchProjectDetails(_selectedProject!['project_id']);
            }
          },
        ),
      ),
    );
    if (res == true) {
      _refreshAll();
      if (_selectedProject != null) {
        _fetchProjectDetails(_selectedProject!['project_id']);
      }
    }
  }

  // ================= 🏗️ CREATE PROJECT (DEDICATED FULL SCREEN) =================
  void _openCreateProjectDialog() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectEditScreen(
          nextProjectNumber: 100 + _projects.length + 1,
          onProjectUpdated: _refreshAll,
        ),
      ),
    );
    if (res == true) {
      _refreshAll();
    }
  }
  // ================= 🎨 MAIN BUILD =================
  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final cardBg = isDark ? const Color(0xFF030D08).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.42);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.7);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF334155);

    // AGAR KOI PROJECT KHULA HAI TOH USKA WORKSPACE DIKHAO
    if (_selectedProject != null) {
      return _buildProjectWorkspaceView(cardBg, cardBorder, textTitle, textSub, isDark);
    }

    // MAIN SCREEN: TOP SWITCHER (Projects vs General Tasks)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP HEADER & SWITCHER
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder, width: 1.2),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 620;

                  final switcher = Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildViewTabButton(0, '📦 Projects', Icons.folder_copy_outlined, textTitle),
                        _buildViewTabButton(1, '⚡ General Tasks', Icons.bolt_rounded, textTitle),
                      ],
                    ),
                  );

                  final actionButton = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () {
                      if (_activeTopView == 0) {
                        _openCreateProjectDialog();
                      } else {
                        _openCreateTaskDialog(preselectedProjectId: null);
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      _activeTopView == 0 ? ' New Project' : ' Assign Task',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: switcher,
                        ),
                        const SizedBox(height: 10),
                        actionButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      switcher,
                      const Spacer(),
                      actionButton,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 2. ACTIVE VIEW
        if (_isLoading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF10B981))))
        else if (_activeTopView == 0)
          _buildProjectsGridView(cardBg, cardBorder, textTitle, textSub)
        else
          _buildGeneralTasksKanbanView(cardBg, cardBorder, textTitle, textSub),
      ],
    );
  }

  Widget _buildViewTabButton(int index, String label, IconData icon, Color textColor) {
    final isSelected = _activeTopView == index;
    return InkWell(
      onTap: () => setState(() => _activeTopView = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : textColor.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : textColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ================= 🔍 PROJECT FILTER & SEARCH BAR =================
  Widget _buildProjectFilterAndSearchBar(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final deptFilters = _getDepartmentFilterList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 750;

        // Search Bar Widget
        final searchBarWidget = Container(
          height: 42,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder, width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _projectSearchController,
            onChanged: (val) => setState(() => _projectSearchQuery = val),
            style: TextStyle(color: textTitle, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search projects (name, PRJ-001, client, lead)...',
              hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 18),
              suffixIcon: _projectSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: textSub, size: 16),
                      onPressed: () {
                        _projectSearchController.clear();
                        setState(() => _projectSearchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            ),
          ),
        );

        // Department Chips Row
        final deptChipsWidget = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: deptFilters.map((df) {
              final isSelected = _selectedDeptFilter.toLowerCase() == df['key'].toString().toLowerCase();
              final count = df['count'] as int;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedDeptFilter = df['key']);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFF059669), Color(0xFF10B981)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected
                          ? null
                          : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.75)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF10B981) : cardBorder,
                        width: 1.1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          df['icon'] as IconData,
                          size: 14,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          df['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : textTitle,
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: isSelected ? Colors.white : textSub,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchBarWidget,
              const SizedBox(height: 10),
              deptChipsWidget,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: deptChipsWidget),
            const SizedBox(width: 14),
            SizedBox(
              width: 300,
              child: searchBarWidget,
            ),
          ],
        );
      },
    );
  }

  // ================= 📂 VIEW A: PROJECTS GRID =================
  Widget _buildProjectsGridView(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final filtered = _filteredProjects;
    final isDark = ThemeController.isDarkMode.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Sleek Department Filter & Search Bar
        _buildProjectFilterAndSearchBar(cardBg, cardBorder, textTitle, textSub, isDark),
        const SizedBox(height: 16),

        // 2. Projects Grid or Empty State
        if (filtered.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.folder_off_outlined, size: 52, color: textSub.withValues(alpha: 0.4)),
                  const SizedBox(height: 14),
                  Text(
                    _projects.isEmpty
                        ? 'No active projects found.'
                        : 'No projects match the selected department or search.',
                    style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _projects.isEmpty
                        ? 'Click "+ New Project" to add your first project!'
                        : 'Try selecting "All Departments" or clearing the search text.',
                    style: TextStyle(color: textSub, fontSize: 12),
                  ),
                  if (_projects.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedDeptFilter = 'ALL';
                          _projectSearchController.clear();
                          _projectSearchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset Filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 460,
              mainAxisExtent: 210,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final prj = filtered[index];
              final totalTasks = prj['total_tasks'] ?? 0;
              final completedTasks = prj['completed_tasks'] ?? 0;
              final progress = totalTasks > 0 ? (completedTasks / totalTasks) : 0.0;

              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedProject = prj);
                      _fetchProjectDetails(prj['project_id']);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(prj['project_code'] ?? 'PRJ', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              if (prj['department_name'] != null && prj['department_name'].toString().trim().isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.apartment_rounded, size: 11, color: Color(0xFF3B82F6)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            prj['department_name'],
                                            style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(prj['status'] ?? 'Active', style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 4),
                              // 3-DOTS OPTIONS MENU (Edit & Delete)
                              Theme(
                                data: Theme.of(context).copyWith(
                                  cardColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                ),
                                child: PopupMenuButton<String>(
                                  icon: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.more_vert_rounded,
                                      size: 16,
                                      color: textTitle.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  padding: EdgeInsets.zero,
                                  elevation: 12,
                                  shadowColor: Colors.black.withValues(alpha: 0.3),
                                  offset: const Offset(0, 38),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
                                      width: 1.2,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      _openEditProjectDialog(prj);
                                    } else if (val == 'delete') {
                                      _confirmDeleteProject(prj);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      height: 44,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF10B981)),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Edit Project',
                                            style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(height: 1),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      height: 44,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Color(0x23EF4444),
                                              borderRadius: BorderRadius.all(Radius.circular(8)),
                                            ),
                                            child: Icon(Icons.delete_outline_rounded, size: 15, color: Colors.redAccent),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Delete Project',
                                          style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(prj['project_name'] ?? 'Untitled Project', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (prj['client_name'] != null && prj['client_name'].toString().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text('Product / Client: ${prj['client_name']}', style: TextStyle(color: textSub, fontSize: 12)),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(Icons.person_pin_rounded, color: Color(0xFF10B981), size: 16),
                              const SizedBox(width: 5),
                              Text('Lead: ${prj['leader_name'] ?? 'Unassigned'}', style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              const Icon(Icons.people_alt_outlined, color: Color(0xFF2563EB), size: 15),
                              const SizedBox(width: 4),
                              Text('${prj['total_members'] ?? 1} Members', style: TextStyle(color: textSub, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ================= ⚡ VIEW B: GENERAL TASKS (KANBAN BOARD) =================
  Widget _buildGeneralTasksKanbanView(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final isDark = ThemeController.isDarkMode.value;
    final allGeneral = _generalTasks;
    final filtered = _filteredGeneralTasks;

    final todo = filtered.where((t) => _taskStatus(t) == 'TODO').toList();
    final inProgress = filtered.where((t) => _taskStatus(t) == 'IN_PROGRESS').toList();
    final done = filtered.where((t) => _taskStatus(t) == 'DONE').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGeneralTasksHero(allGeneral, cardBg, cardBorder, textTitle, textSub, isDark),
        if (allGeneral.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildGeneralTasksToolbar(
            allGeneral.length,
            filtered.length,
            cardBg,
            cardBorder,
            textTitle,
            textSub,
            isDark,
          ),
        ],
        const SizedBox(height: 14),
        if (allGeneral.isEmpty)
          _buildGeneralTasksEmptyState(cardBg, cardBorder, textTitle, textSub, isDark)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 820;
              if (isCompact) {
                return Column(
                  children: [
                    _buildKanbanColumn(
                      'To Do',
                      Icons.radio_button_unchecked_rounded,
                      todo,
                      const Color(0xFF3B82F6),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                    const SizedBox(height: 14),
                    _buildKanbanColumn(
                      'In Progress',
                      Icons.timelapse_rounded,
                      inProgress,
                      const Color(0xFFF59E0B),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                    const SizedBox(height: 14),
                    _buildKanbanColumn(
                      'Completed',
                      Icons.task_alt_rounded,
                      done,
                      const Color(0xFF10B981),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildKanbanColumn(
                      'To Do',
                      Icons.radio_button_unchecked_rounded,
                      todo,
                      const Color(0xFF3B82F6),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildKanbanColumn(
                      'In Progress',
                      Icons.timelapse_rounded,
                      inProgress,
                      const Color(0xFFF59E0B),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildKanbanColumn(
                      'Completed',
                      Icons.task_alt_rounded,
                      done,
                      const Color(0xFF10B981),
                      cardBg,
                      cardBorder,
                      textTitle,
                      textSub,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  // ---------- 🟢 GENERAL TASKS: HERO SUMMARY ----------
  Widget _buildGeneralTasksHero(
    List<dynamic> tasks,
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final total = tasks.length;
    final inProgress = tasks.where((t) => _taskStatus(t) == 'IN_PROGRESS').length;
    final completed = tasks.where((t) => _taskStatus(t) == 'DONE').length;
    final overdue = tasks.where(_isTaskOverdue).length;
    final progress = total == 0 ? 0.0 : completed / total;
    final accentStart = isDark
        ? const Color(0xFF052E22).withValues(alpha: 0.82)
        : const Color(0xFFECFDF5);
    final accentEnd = isDark
        ? const Color(0xFF030D08).withValues(alpha: 0.68)
        : Colors.white.withValues(alpha: 0.85);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentStart, accentEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'General & Ad-hoc Tasks',
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Standalone tasks that are not tied to a project',
                      style: TextStyle(color: textSub, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh tasks',
                onPressed: _isLoading ? null : _refreshAll,
                icon: Icon(Icons.refresh_rounded, size: 18, color: textSub),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.82),
                  side: BorderSide(color: cardBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildGeneralTaskStatPill('Total', '$total', Icons.layers_outlined,
                    const Color(0xFF3B82F6), isDark, cardBorder, textTitle, textSub),
                _buildGeneralTaskStatPill('In Progress', '$inProgress', Icons.timelapse_rounded,
                    const Color(0xFFF59E0B), isDark, cardBorder, textTitle, textSub),
                _buildGeneralTaskStatPill(
                  'Overdue',
                  '$overdue',
                  Icons.warning_amber_rounded,
                  const Color(0xFFEF4444),
                  isDark,
                  cardBorder,
                  textTitle,
                  textSub,
                  selected: _genOnlyOverdue,
                  onTap: () => setState(() => _genOnlyOverdue = !_genOnlyOverdue),
                ),
                _buildGeneralTaskStatPill('Completed', '$completed', Icons.task_alt_rounded,
                    const Color(0xFF10B981), isDark, cardBorder, textTitle, textSub),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(progress * 100).round()}% complete',
                  style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneralTaskStatPill(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
    Color cardBorder,
    Color textTitle,
    Color textSub, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: isDark ? 0.22 : 0.12)
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.78)),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: selected ? color.withValues(alpha: 0.55) : cardBorder,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: textSub, fontSize: 11)),
        ],
      ),
    );

    if (onTap == null) return pill;

    return Tooltip(
      message: selected ? 'Show all tasks' : 'Show overdue tasks only',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: pill),
      ),
    );
  }

  // ---------- 🔍 GENERAL TASKS: SEARCH & FILTER TOOLBAR ----------
  Widget _buildGeneralTasksToolbar(
    int total,
    int showing,
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final filtersActive = _hasGeneralTaskFilters;

    final searchField = Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder, width: 1.1),
      ),
      child: TextField(
        controller: _genTaskSearchController,
        onChanged: (val) => setState(() => _genTaskSearchQuery = val),
        textInputAction: TextInputAction.search,
        style: TextStyle(color: textTitle, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search task, description, assignee or #ID...',
          hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 18),
          suffixIcon: _genTaskSearchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.clear_rounded, color: textSub, size: 16),
                  onPressed: () {
                    _genTaskSearchController.clear();
                    setState(() => _genTaskSearchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
      ),
    );

    final filterWidgets = <Widget>[
      _buildGeneralPriorityMenu(cardBorder, textTitle, textSub, isDark),
      _buildGeneralAssigneeMenu(cardBorder, textTitle, textSub, isDark),
      _buildGeneralSortMenu(cardBorder, textTitle, textSub, isDark),
      if (filtersActive) _buildGeneralResetButton(cardBorder, isDark),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 780;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(children: filterWidgets),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 10),
                  ...filterWidgets,
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(
                filtersActive ? Icons.filter_alt_rounded : Icons.view_kanban_outlined,
                size: 13,
                color: filtersActive ? const Color(0xFF10B981) : textSub,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  filtersActive
                      ? 'Showing $showing of $total tasks'
                      : '$total task${total == 1 ? '' : 's'} in this board',
                  style: TextStyle(
                    color: filtersActive ? const Color(0xFF059669) : textSub,
                    fontSize: 11.5,
                    fontWeight: filtersActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (filtersActive)
                InkWell(
                  onTap: _resetGeneralTaskFilters,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Clear all',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _generalToolbarDecoration(bool isActive, bool isDark, Color cardBorder) {
    const emerald = Color(0xFF10B981);
    return BoxDecoration(
      color: isActive
          ? emerald.withValues(alpha: isDark ? 0.18 : 0.1)
          : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.92)),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isActive ? emerald.withValues(alpha: 0.45) : cardBorder,
        width: 1.1,
      ),
    );
  }

  Widget _buildGeneralPriorityMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    const options = <String, String>{
      'ALL': 'All priorities',
      'URGENT': 'Urgent',
      'HIGH': 'High',
      'MEDIUM': 'Medium',
      'LOW': 'Low',
    };
    final isActive = _genPriorityFilter != 'ALL';
    final label = isActive ? options[_genPriorityFilter]! : 'Priority';
    final accent = isActive ? _generalPriorityColor(_genPriorityFilter) : textSub;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Theme(
        data: Theme.of(context).copyWith(cardColor: isDark ? const Color(0xFF0F172A) : Colors.white),
        child: PopupMenuButton<String>(
          tooltip: 'Filter by priority',
          initialValue: _genPriorityFilter,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cardBorder),
          ),
          onSelected: (value) => setState(() => _genPriorityFilter = value),
          itemBuilder: (ctx) => options.entries.map((entry) {
            final isSelected = _genPriorityFilter == entry.key;
            return PopupMenuItem<String>(
              value: entry.key,
              height: 40,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _generalPriorityColor(entry.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_rounded, size: 15, color: Color(0xFF10B981)),
                ],
              ),
            );
          }).toList(),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? accent : textTitle,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralAssigneeMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    final assignees = _generalTaskAssignees;
    final isActive = _genAssigneeFilter != 'ALL';
    final label = isActive ? _genAssigneeFilter : 'Assignee';
    final options = <String>['ALL', ...assignees];

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Theme(
        data: Theme.of(context).copyWith(cardColor: isDark ? const Color(0xFF0F172A) : Colors.white),
        child: PopupMenuButton<String>(
          tooltip: 'Filter by assignee',
          initialValue: _genAssigneeFilter,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cardBorder),
          ),
          onSelected: (value) => setState(() => _genAssigneeFilter = value),
          itemBuilder: (ctx) => options.map((name) {
            final isSelected = _genAssigneeFilter == name;
            return PopupMenuItem<String>(
              value: name,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    name == 'ALL' ? Icons.groups_rounded : Icons.person_rounded,
                    size: 15,
                    color: name == 'ALL' ? textSub : const Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name == 'ALL' ? 'All assignees' : name,
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_rounded, size: 15, color: Color(0xFF10B981)),
                ],
              ),
            );
          }).toList(),
          child: Container(
            height: 36,
            constraints: const BoxConstraints(maxWidth: 170),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: isActive ? const Color(0xFF10B981) : textSub,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? const Color(0xFF059669) : textTitle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralSortMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    const options = <String, String>{
      'SMART': 'Smart order',
      'DUE_DATE': 'Due date',
      'PRIORITY': 'Priority',
      'NEWEST': 'Newest first',
    };
    final isActive = _genSortOption != 'SMART';
    final label = options[_genSortOption] ?? 'Smart order';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Theme(
        data: Theme.of(context).copyWith(cardColor: isDark ? const Color(0xFF0F172A) : Colors.white),
        child: PopupMenuButton<String>(
          tooltip: 'Sort tasks',
          initialValue: _genSortOption,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cardBorder),
          ),
          onSelected: (value) => setState(() => _genSortOption = value),
          itemBuilder: (ctx) => options.entries.map((entry) {
            final isSelected = _genSortOption == entry.key;
            return PopupMenuItem<String>(
              value: entry.key,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    entry.key == 'SMART'
                        ? Icons.auto_awesome_rounded
                        : entry.key == 'DUE_DATE'
                            ? Icons.event_rounded
                            : entry.key == 'PRIORITY'
                                ? Icons.flag_rounded
                                : Icons.schedule_rounded,
                    size: 15,
                    color: isSelected ? const Color(0xFF10B981) : textSub,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_rounded, size: 15, color: Color(0xFF10B981)),
                ],
              ),
            );
          }).toList(),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 15,
                  color: isActive ? const Color(0xFF10B981) : textSub,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF059669) : textTitle,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralResetButton(Color cardBorder, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Reset search, filters & sorting',
        child: InkWell(
          onTap: _resetGeneralTaskFilters,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                width: 1.1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restart_alt_rounded, size: 15, color: Color(0xFFEF4444)),
                SizedBox(width: 5),
                Text(
                  'Reset',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTasksEmptyState(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1.1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.5),
            ),
            child: const Icon(Icons.bolt_rounded, size: 34, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 16),
          Text(
            'No general tasks yet',
            style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a standalone task for work that isn\'t part of a project.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textSub, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => _openCreateTaskDialog(preselectedProjectId: null),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'Assign Task',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 🗂️ GENERAL TASKS: KANBAN COLUMN ----------
  Widget _buildKanbanColumn(
    String title,
    IconData icon,
    List<dynamic> list,
    Color headerColor,
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
  ) {
    final isDark = ThemeController.isDarkMode.value;
    final taskCardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: headerColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: headerColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: headerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${list.length}',
                  style: TextStyle(color: headerColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (list.isEmpty)
            _buildKanbanColumnEmptyState(title, isDark, cardBorder, textTitle, textSub)
          else
            ...list.map(
              (task) => _buildGeneralTaskCard(
                task,
                headerColor,
                taskCardBg,
                cardBorder,
                textTitle,
                textSub,
                isDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKanbanColumnEmptyState(
    String title,
    bool isDark,
    Color cardBorder,
    Color textTitle,
    Color textSub,
  ) {
    final filtersActive = _hasGeneralTaskFilters;
    final message = filtersActive
        ? 'No matching tasks'
        : title == 'To Do'
            ? 'Nothing queued'
            : title == 'In Progress'
                ? 'No tasks in progress'
                : 'No completed tasks yet';
    final hint = filtersActive
        ? 'Try changing the search or filters.'
        : title == 'To Do'
            ? 'New tasks will appear here.'
            : title == 'In Progress'
                ? 'Start a task from To Do.'
                : 'Finished tasks land here.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(
            filtersActive ? Icons.search_off_rounded : Icons.inbox_rounded,
            size: 24,
            color: textSub.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textTitle.withValues(alpha: 0.82),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: textSub.withValues(alpha: 0.8), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Color _avatarColorForName(String name) {
    const palette = [
      Color(0xFF0EA5E9),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFF6366F1),
    ];
    if (name.trim().isEmpty) return const Color(0xFF64748B);
    final hash = name.trim().codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return palette[hash % palette.length];
  }

  String _formatTaskDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  Widget? _buildTaskDueDateChip(dynamic task, bool isDone, Color textSub) {
    final due = _parseTaskDueDate(task['due_date']);
    if (due == null) return null;

    final difference = due.difference(_todayDate).inDays;
    final Color color;
    final String label;

    if (isDone) {
      color = const Color(0xFF10B981);
      label = _formatTaskDate(due);
    } else if (difference < 0) {
      color = const Color(0xFFEF4444);
      label = difference == -1 ? 'Overdue by 1 day' : 'Overdue by ${-difference} days';
    } else if (difference == 0) {
      color = const Color(0xFFF97316);
      label = 'Due today';
    } else if (difference == 1) {
      color = const Color(0xFFF59E0B);
      label = 'Due tomorrow';
    } else if (difference <= 7) {
      color = const Color(0xFFF59E0B);
      label = 'Due in $difference days';
    } else {
      color = textSub;
      label = 'Due ${_formatTaskDate(due)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_rounded, size: 11.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTaskCard(
    dynamic task,
    Color columnColor,
    Color taskCardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final status = _taskStatus(task);
    final isDone = status == 'DONE';
    final isOverdue = _isTaskOverdue(task);
    final priority = (task['priority'] ?? 'MEDIUM').toString().toUpperCase();
    final priorityColor = _generalPriorityColor(priority);
    final workerName = (task['assigned_worker'] ?? '').toString().trim();
    final subtasks = (task['subtasks'] as List<dynamic>?) ?? [];
    final doneSubtasks = subtasks
        .where((s) => s['is_completed'] == 1 || s['is_completed'] == true)
        .length;
    final dueChip = _buildTaskDueDateChip(task, isDone, textSub);

    final nextStatus = status == 'TODO'
        ? 'IN_PROGRESS'
        : status == 'IN_PROGRESS'
            ? 'DONE'
            : 'TODO';
    final nextLabel = status == 'TODO'
        ? 'Start'
        : status == 'IN_PROGRESS'
            ? 'Complete'
            : 'Reopen';
    final nextIcon = status == 'TODO'
        ? Icons.play_arrow_rounded
        : status == 'IN_PROGRESS'
            ? Icons.check_rounded
            : Icons.replay_rounded;

    final borderColor = isOverdue
        ? const Color(0xFFEF4444).withValues(alpha: 0.5)
        : isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.28)
            : cardBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDone ? taskCardBg.withValues(alpha: 0.84) : taskCardBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor, width: isOverdue ? 1.3 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _openTaskDetailsDialog(task),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            priority,
                            style: TextStyle(
                              color: priorityColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task['task_id'] != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '#${task['task_id']}',
                        style: TextStyle(
                          color: textSub.withValues(alpha: 0.55),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF10B981)),
                      tooltip: 'Edit task',
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () => _openEditTaskDialog(task),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                      tooltip: 'Delete task',
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: () => _confirmDeleteTask(task),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  task['title'] ?? 'Untitled',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDone ? textTitle.withValues(alpha: 0.72) : textTitle,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    height: 1.25,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task['description'] != null && task['description'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task['description'],
                    style: TextStyle(color: textSub, fontSize: 11.5, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (dueChip != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: dueChip),
                ],
                if (subtasks.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 12.5, color: textSub),
                      const SizedBox(width: 4),
                      Text(
                        '$doneSubtasks/${subtasks.length} subtasks',
                        style: TextStyle(color: textSub, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${((doneSubtasks / subtasks.length) * 100).round()}%',
                        style: TextStyle(
                          color: doneSubtasks == subtasks.length
                              ? const Color(0xFF10B981)
                              : textSub,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: doneSubtasks / subtasks.length,
                      minHeight: 4,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation(
                        doneSubtasks == subtasks.length
                            ? const Color(0xFF10B981)
                            : const Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: _avatarColorForName(workerName),
                      child: Text(
                        workerName.isNotEmpty ? workerName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        workerName.isEmpty ? 'Unassigned' : workerName,
                        style: TextStyle(color: textTitle, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Move to ${_taskStatusLabel(nextStatus)}',
                      child: InkWell(
                        onTap: () => _updateTaskStatus(task['task_id'], nextStatus),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: columnColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: columnColor.withValues(alpha: 0.24),
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(nextIcon, size: 12, color: columnColor),
                              const SizedBox(width: 3),
                              Text(
                                nextLabel,
                                style: TextStyle(
                                  color: columnColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= 📱 MOBILE PROJECT CARD HEADER =================
  Widget _buildMobileProjectHeader(
    Map<String, dynamic> prj,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final softBank = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC);
    final softBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);
    final statusText = (prj['status'] ?? 'Active').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top controls: back + project code + status + options
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _selectedProject = null),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: softBank,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: softBorder),
                ),
                child: Icon(Icons.arrow_back_rounded, color: textTitle, size: 19),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Text(
                prj['project_code'] ?? 'PRJ',
                style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 10.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Spacer(),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: softBank,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: softBorder),
              ),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 19, color: textSub),
                padding: EdgeInsets.zero,
                tooltip: 'Project options',
                onSelected: (val) {
                  if (val == 'edit') _openEditProjectDialog(prj);
                  if (val == 'delete') _confirmDeleteProject(prj);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: Color(0xFF10B981)), SizedBox(width: 8), Text('Edit Project')]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Delete Project', style: TextStyle(color: Colors.redAccent))]),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Project name gets its own full-width line on mobile.
        Text(
          prj['project_name'] ?? 'Untitled Project',
          style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),

        // Full-width touch-friendly primary action.
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _openCreateTaskDialog(preselectedProjectId: prj['project_id']),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Task', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ================= 🏗️ CLEAN MOBILE-FRIENDLY WORKSPACE HEADER =================
  Widget _buildProjectWorkspaceView(Color cardBg, Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    final prj = _selectedProject!;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. MODERN PROJECT HERO CARD
        Container(
          padding: EdgeInsets.all(isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Mobile gets a dedicated stacked header so the project
              // name and + New Task button never fight for the same line.
              if (isMobile)
                _buildMobileProjectHeader(prj, textTitle, textSub, isDark)
              else
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: textTitle, size: 20),
                      onPressed: () => setState(() => _selectedProject = null),
                      tooltip: 'Back to Projects',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        prj['project_code'] ?? 'PRJ',
                        style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              prj['project_name'] ?? 'Untitled Project',
                              style: TextStyle(color: textTitle, fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              prj['status'] ?? 'Active',
                              style: const TextStyle(color: Color(0xFF059669), fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 1,
                      ),
                      onPressed: () => _openCreateTaskDialog(preselectedProjectId: prj['project_id']),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(isMobile ? 'Task' : 'New Task', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: textSub),
                      padding: EdgeInsets.zero,
                      onSelected: (val) {
                        if (val == 'edit') _openEditProjectDialog(prj);
                        if (val == 'delete') _confirmDeleteProject(prj);
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: Color(0xFF10B981)), SizedBox(width: 8), Text('Edit Project')])),
                        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Delete Project', style: TextStyle(color: Colors.redAccent))])),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Divider(height: 1, color: cardBorder.withValues(alpha: 0.6)),
              const SizedBox(height: 12),

              // Row 2: Lead Name, Client Name & Project Task Progress Bar
              Builder(
                builder: (context) {
                  final allTasks = (_projectDetails?['tasks'] as List<dynamic>?) ?? [];
                  final totalTasks = allTasks.length;
                  final doneTasks = allTasks.where((t) => t['status'] == 'DONE').length;
                  final double progress = totalTasks > 0 ? (doneTasks / totalTasks) : 0.0;

                  final leadChip = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF059669)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Lead: ${prj['leader_name'] ?? 'Unassigned'}',
                            style: TextStyle(color: textTitle, fontSize: 11.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );

                  final clientChip = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.business_outlined, size: 14, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Client: ${prj['client_name'] ?? 'Internal'}',
                            style: TextStyle(color: textTitle, fontSize: 11.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );

                  // Progress Percentage Indicator
                  final progressIndicator = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$doneTasks/$totalTasks Done (${(progress * 100).toInt()}%)',
                        style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: isMobile ? 60 : 120,
                        height: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                          ),
                        ),
                      ),
                    ],
                  );

                  // Mobile: stack the meta chips and progress instead of
                  // squeezing all three into a single row.
                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Chips wrap on narrow screens instead of overflowing.
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [leadChip, clientChip],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Task Progress',
                              style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              '$doneTasks/$totalTasks Done (${(progress * 100).toInt()}%)',
                              style: TextStyle(color: textTitle, fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Full-width bar is much easier to read on phones.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      leadChip,
                      const SizedBox(width: 8),
                      clientChip,
                      const Spacer(),
                      progressIndicator,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. MINIMAL FLAT UNDERLINE TABS (Directly on page, no card!)
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: textSub,
          indicatorColor: const Color(0xFF10B981),
          indicatorWeight: 2.5,
          labelPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          dividerColor: cardBorder.withValues(alpha: 0.5),
          tabs: const [
            Tab(text: 'Tasks & Checklist'),
            Tab(text: 'Team Members'),
            Tab(text: 'Timesheets'),
            Tab(text: 'Components'),
          ],
        ),
        const SizedBox(height: 20),

        if (_isLoadingDetails)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF10B981))))
        else
          SizedBox(
            height: 650,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProjectTasksTab(cardBg, cardBorder, textTitle, textSub),
                _buildProjectTeamTab(cardBg, cardBorder, textTitle, textSub),
                _buildProjectTimesheetTab(cardBg, cardBorder, textTitle, textSub),
                _buildProjectComponentsTab(cardBg, cardBorder, textTitle, textSub),
              ],
            ),
          ),
      ],
    );
  }
  // ================= 📋 MOBILE + DESKTOP RESPONSIVE TASK VIEW =================
  Widget _buildProjectTasksTab(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final allTasks = (_projectDetails?['tasks'] as List<dynamic>?) ?? [];
    final isDark = ThemeController.isDarkMode.value;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    // Solid Background so leaves don't bleed through
    final taskCardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    // Filter
    final filteredTasks = allTasks.where((task) {
      final title = (task['title'] ?? '').toString().toLowerCase();
      final desc = (task['description'] ?? '').toString().toLowerCase();
      final worker = (task['assigned_worker'] ?? '').toString().toLowerCase();
      final matchesQuery = _taskSearchQuery.isEmpty ||
          title.contains(_taskSearchQuery) ||
          desc.contains(_taskSearchQuery) ||
          worker.contains(_taskSearchQuery);

      if (!matchesQuery) return false;

      final status = (task['status'] ?? 'TODO').toString().toUpperCase();
      if (_selectedStatusFilter == 'ALL') return true;
      if (_selectedStatusFilter == 'TODO') return status == 'TODO';
      if (_selectedStatusFilter == 'IN_PROGRESS') return status == 'IN_PROGRESS';
      if (_selectedStatusFilter == 'DONE') return status == 'DONE';

      return true;
    }).toList();

    final totalCount = allTasks.length;
    final todoCount = allTasks.where((t) => (t['status'] ?? 'TODO') == 'TODO').length;
    final inProgressCount = allTasks.where((t) => t['status'] == 'IN_PROGRESS').length;
    final doneCount = allTasks.where((t) => t['status'] == 'DONE').length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CLEAN SEARCH & FILTER ROW (Directly on page, no wrapper card!)
          if (isMobile) ...[
            // Mobile: Search on top
            TextField(
              controller: _taskSearchController,
              onChanged: (val) => setState(() => _taskSearchQuery = val.trim().toLowerCase()),
              style: TextStyle(color: textTitle, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                hintStyle: TextStyle(color: textSub, fontSize: 12),
                prefixIcon: Icon(Icons.search, size: 18, color: textSub),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: taskCardBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
              ),
            ),
            const SizedBox(height: 12),
            // Filter chips scrollable
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusFilterChip('ALL', 'All ($totalCount)'),
                  _buildStatusFilterChip('TODO', 'To Do ($todoCount)'),
                  _buildStatusFilterChip('IN_PROGRESS', 'In Progress ($inProgressCount)'),
                  _buildStatusFilterChip('DONE', 'Done ($doneCount)'),
                ],
              ),
            ),
          ] else ...[
            // Desktop: Search + Filters in one clean horizontal line
            Row(
              children: [
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _taskSearchController,
                    onChanged: (val) => setState(() => _taskSearchQuery = val.trim().toLowerCase()),
                    style: TextStyle(color: textTitle, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search tasks...',
                      hintStyle: TextStyle(color: textSub, fontSize: 12),
                      prefixIcon: Icon(Icons.search, size: 17, color: textSub),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: taskCardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStatusFilterChip('ALL', 'All ($totalCount)'),
                        _buildStatusFilterChip('TODO', 'To Do ($todoCount)'),
                        _buildStatusFilterChip('IN_PROGRESS', 'In Progress ($inProgressCount)'),
                        _buildStatusFilterChip('DONE', 'Done ($doneCount)'),
                      ],
                    ),
                  ),
                ),
                Text(
                  '$doneCount of $totalCount completed',
                  style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // 2. CLEAN INDIVIDUAL TASK CARDS (Readable, Solid & Mobile Responsive)
          if (filteredTasks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No tasks found. Click "+ New Task" above!', style: TextStyle(color: textSub)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredTasks.length,
              itemBuilder: (context, idx) {
                final t = filteredTasks[idx];
                final subtasks = (t['subtasks'] as List<dynamic>?) ?? [];
                final priority = (t['priority'] ?? 'MEDIUM').toString().toUpperCase();
                final isDone = t['status'] == 'DONE';

                Color priColor = Colors.grey;
                if (priority == 'URGENT') priColor = const Color(0xFFEF4444);
                if (priority == 'HIGH') priColor = const Color(0xFFF97316);
                if (priority == 'MEDIUM') priColor = const Color(0xFFF59E0B);
                if (priority == 'LOW') priColor = const Color(0xFF10B981);

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 18,
                    vertical: isMobile ? 12 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: taskCardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorder),
                    // Left border gives a modern Kanban card feel based on priority:
                    boxShadow: [
                      BoxShadow(
                        color: priColor.withValues(alpha: 0.3),
                        offset: const Offset(-4, 0), // Priority line (Red for urgent, Orange for High/Medium)
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TOP ROW: Checkbox + Title + Action Icons
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              final next = isDone ? 'TODO' : 'DONE';
                              _updateTaskStatus(t['task_id'], next);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1, right: 10),
                              child: Icon(
                                isDone ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                color: isDone ? const Color(0xFF10B981) : textSub,
                                size: 21,
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _openTaskDetailsDialog(t),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t['title'],
                                            style: TextStyle(
                                              color: isDone ? textSub : textTitle,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              decoration: isDone ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: textSub.withValues(alpha: 0.4)),
                                      ],
                                    ),
                                    if (t['description'] != null && t['description'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        t['description'],
                                        style: TextStyle(color: textSub, fontSize: 12, height: 1.3),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Edit Button
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 17, color: Color(0xFF10B981)),
                            tooltip: 'Edit Task',
                            splashRadius: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => _openTaskDetailsDialog(t),
                          ),
                          const SizedBox(width: 4),
                          // Delete Button
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                            tooltip: 'Delete Task',
                            splashRadius: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => _confirmDeleteTask(t),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // MIDDLE ROW: Subtasks Checklist (Agar hain)
                      if (subtasks.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...subtasks.map((st) {
                                final stDone = st['is_completed'] == 1 || st['is_completed'] == true;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: Checkbox(
                                          value: stDone,
                                          activeColor: const Color(0xFF10B981),
                                          visualDensity: VisualDensity.compact,
                                          onChanged: (val) => _toggleSubtask(st['subtask_id'], val ?? false),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          st['title'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: stDone ? textSub : textTitle,
                                            decoration: stDone ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                        onPressed: () async {
                                          try {
                                            await http.delete(Uri.parse('http://localhost:5000/api/projects/subtasks/${st['subtask_id']}'));
                                            if (_selectedProject != null) _fetchProjectDetails(_selectedProject!['project_id']);
                                          } catch (_) {}
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],

                      // BOTTOM ROW: Badges (Wrap for clean Mobile & Desktop wrapping)
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Worker
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 9,
                                backgroundColor: const Color(0xFF10B981),
                                child: Text(
                                  (t['assigned_worker'] != null && t['assigned_worker'].isNotEmpty) ? t['assigned_worker'][0].toUpperCase() : 'W',
                                  style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(t['assigned_worker'] ?? 'Unassigned', style: TextStyle(color: textTitle, fontSize: 12)),
                            ],
                          ),

                          // Priority
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(color: priColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                            child: Text(priority, style: TextStyle(color: priColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          ),

                          // Status Pill (Clickable)
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              final current = t['status'] ?? 'TODO';
                              final next = current == 'TODO' ? 'IN_PROGRESS' : (current == 'IN_PROGRESS' ? 'DONE' : 'TODO');
                              _updateTaskStatus(t['task_id'], next);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: (isDone ? const Color(0xFF10B981) : (t['status'] == 'IN_PROGRESS' ? const Color(0xFFD97706) : Colors.grey)).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t['status'] ?? 'TODO',
                                style: TextStyle(
                                  color: isDone ? const Color(0xFF10B981) : (t['status'] == 'IN_PROGRESS' ? const Color(0xFFD97706) : textSub),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          // + Add Item Link
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _openAddSubtaskDialog(t['task_id'], t['title']),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF10B981)),
                                  SizedBox(width: 4),
                                  Text('+ Add item', style: TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
  // Filter Chip Helper
  Widget _buildStatusFilterChip(String key, String label) {
    final isSelected = _selectedStatusFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: Colors.transparent,
        selectedColor: const Color(0xFF10B981),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? const Color(0xFF10B981) : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        onSelected: (_) => setState(() => _selectedStatusFilter = key),
      ),
    );
  }

  // TAB 2: Team
  Widget _buildProjectTeamTab(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final members = (_projectDetails?['members'] as List<dynamic>?) ?? [];
    final isDark = ThemeController.isDarkMode.value;
    final itemBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return members.isEmpty
        ? Center(child: Text('No team members assigned yet.', style: TextStyle(color: textSub)))
        : GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, mainAxisExtent: 76, crossAxisSpacing: 14, mainAxisSpacing: 14),
      itemCount: members.length,
      itemBuilder: (context, idx) {
        final m = members[idx];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: itemBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                child: Text(
                  m['full_name'] != null && m['full_name'].toString().isNotEmpty ? m['full_name'][0].toUpperCase() : 'M',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(m['full_name'] ?? 'Unnamed', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(m['role_in_project'] ?? 'Member', style: TextStyle(color: textSub, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 3: Timesheets
  Widget _buildProjectTimesheetTab(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final timesheets = (_projectDetails?['timesheets'] as List<dynamic>?) ?? [];
    final isDark = ThemeController.isDarkMode.value;
    final itemBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return timesheets.isEmpty
        ? Center(child: Text('No work hours logged yet for this project.', style: TextStyle(color: textSub)))
        : ListView.builder(
      itemCount: timesheets.length,
      itemBuilder: (context, idx) {
        final ts = timesheets[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: itemBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Color(0xFFD97706), size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${ts['worker_name']} logged ${ts['hours_spent']} hrs: ${ts['description'] ?? ''}', style: TextStyle(color: textTitle, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 4: Components / Materials
  // TAB 4: Components / Materials
  Widget _buildProjectComponentsTab(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final prj = _selectedProject!;
    final materials = (_projectDetails?['materials'] as List<dynamic>?) ?? [];
    final isDark = ThemeController.isDarkMode.value;
    final itemBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Toolbar: Header + Add Component Button
          Row(
            children: [
              Text(
                'Components & Parts (${materials.length})',
                style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () => _openAddComponentDialog(prj['project_id']),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('+ Add Component', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (materials.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 40, color: textSub.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    Text('No components or parts assigned yet.', style: TextStyle(color: textSub)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2563EB), side: const BorderSide(color: Color(0xFF2563EB))),
                      onPressed: () => _openAddComponentDialog(prj['project_id']),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Component Now'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: materials.length,
              itemBuilder: (context, idx) {
                final m = materials[idx];
                final status = (m['status'] ?? 'Required').toString();

                Color statusColor = const Color(0xFF2563EB); // Blue for Issued
                if (status == 'Required') statusColor = const Color(0xFFF59E0B);
                if (status == 'Consumed') statusColor = const Color(0xFF10B981);
                if (status == 'Returned') statusColor = Colors.grey;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: itemBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.memory_rounded, color: Color(0xFF2563EB), size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m['material_name'] ?? 'Unnamed Component',
                              style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Required: ${m['quantity_required']} ${m['unit'] ?? 'PCS'}',
                              style: TextStyle(color: textSub, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 🗑️ Delete Component Button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                        tooltip: 'Remove Component',
                        splashRadius: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => _confirmDeleteComponent(m),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}