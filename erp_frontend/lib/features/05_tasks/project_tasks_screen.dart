import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/network/api_client.dart';
import 'task_details_screen.dart';
import 'project_edit_screen.dart';
import 'task_form_screen.dart';


class ProjectTasksScreen extends StatefulWidget {
  const ProjectTasksScreen({super.key});

  @override
  State<ProjectTasksScreen> createState() => _ProjectTasksScreenState();
}

class _ProjectTasksScreenState extends State<ProjectTasksScreen> with SingleTickerProviderStateMixin {
  static String get _apiHost => ApiClient.apiHost;

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
  final ScrollController _deptScrollController = ScrollController();


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
  String _genViewMode = 'KANBAN'; // 'KANBAN' or 'LIST'
  String _genMobileColumnTab = 'TODO'; // 'TODO', 'IN_PROGRESS', 'DONE'

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
    _deptScrollController.dispose();
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
      final res = await http.get(Uri.parse('$_apiHost/api/projects'));
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
      final res = await http.get(Uri.parse('$_apiHost/api/hr/departments'));
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
      final res = await http.get(Uri.parse('$_apiHost/api/tasks'));
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
      final res = await http.get(Uri.parse('$_apiHost/api/hr/employees'));
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
      final res = await http.get(Uri.parse('$_apiHost/api/projects/$projectId'));
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
        Uri.parse('$_apiHost/api/tasks/$taskId/status'),
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
        Uri.parse('$_apiHost/api/projects/subtasks/$subtaskId'),
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
        final dialogBg = isDark ? const Color(0xFF111113) : Colors.white;
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
              boxShadow: const [],
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
                              Uri.parse('$_apiHost/api/projects/${prj['project_id']}'),
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
        final dialogBg = isDark ? const Color(0xFF111113) : Colors.white;
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
              boxShadow: const [],
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
                              Uri.parse('$_apiHost/api/tasks/${task['task_id']}'),
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
                boxShadow: const [],
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
                                            Uri.parse('$_apiHost/api/projects/$projectId/materials'),
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
        final dialogBg = isDark ? const Color(0xFF111113) : Colors.white;
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
              boxShadow: const [],
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
                              Uri.parse('$_apiHost/api/projects/materials/${m['material_id']}'),
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
    final cardBg = isDark ? const Color(0xFF111113) : Colors.white;
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
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 620;

            // 📱 MOBILE VIEW: Minimal monochrome tabs
            if (isNarrow) {
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Tab 1: Projects
                    InkWell(
                      onTap: () => setState(() => _activeTopView = 0),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: _activeTopView == 0
                              ? Border(
                                  bottom: BorderSide(
                                    color: isDark ? Colors.white : const Color(0xFF09090B),
                                    width: 2.2,
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          'Projects',
                          style: TextStyle(
                            color: _activeTopView == 0
                                ? (isDark ? Colors.white : const Color(0xFF09090B))
                                : (isDark ? Colors.white60 : const Color(0xFF71717A)),
                            fontSize: 14.5,
                            fontWeight: _activeTopView == 0 ? FontWeight.bold : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Tab 2: General tasks
                    InkWell(
                      onTap: () => setState(() => _activeTopView = 1),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: _activeTopView == 1
                              ? Border(
                                  bottom: BorderSide(
                                    color: isDark ? Colors.white : const Color(0xFF09090B),
                                    width: 2.2,
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          'General tasks',
                          style: TextStyle(
                            color: _activeTopView == 1
                                ? (isDark ? Colors.white : const Color(0xFF09090B))
                                : (isDark ? Colors.white60 : const Color(0xFF71717A)),
                            fontSize: 14.5,
                            fontWeight: _activeTopView == 1 ? FontWeight.bold : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Primary Button on Mobile: #18181B (kaala) with safed text
                    InkWell(
                      onTap: () {
                        if (_activeTopView == 0) {
                          _openCreateProjectDialog();
                        } else {
                          _openCreateTaskDialog(preselectedProjectId: null);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF27272A) : const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded, size: 15, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              _activeTopView == 0 ? 'Project' : 'Task',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
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

            // 💻 DESKTOP / WEB VIEW (100% UNTOUCHED)
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

            return ClipRRect(
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
                  child: Row(
                    children: [
                      switcher,
                      const Spacer(),
                      actionButton,
                    ],
                  ),
                ),
              ),
            );
          },
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
          height: 40,
          decoration: BoxDecoration(
            color: isCompact
                ? (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAFAFA))
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.9)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCompact
                  ? (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7))
                  : cardBorder,
              width: 1.0,
            ),
            boxShadow: const [],
          ),
          child: TextField(
            controller: _projectSearchController,
            onChanged: (val) => setState(() => _projectSearchQuery = val),
            style: TextStyle(
              color: isCompact ? (isDark ? Colors.white : const Color(0xFF09090B)) : textTitle,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search projects (name, PRJ-001, client)...',
              hintStyle: TextStyle(
                color: isCompact ? (isDark ? Colors.white38 : const Color(0xFF71717A)) : textSub.withValues(alpha: 0.6),
                fontSize: 12,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: isCompact ? (isDark ? Colors.white54 : const Color(0xFF71717A)) : const Color(0xFF10B981),
                size: 18,
              ),
              suffixIcon: _projectSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        color: isCompact ? const Color(0xFF71717A) : textSub,
                        size: 16,
                      ),
                      onPressed: () {
                        _projectSearchController.clear();
                        setState(() => _projectSearchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        );

        // Helper to scroll left / right smoothly
        void scrollDept(double offset) {
          if (_deptScrollController.hasClients) {
            final target = (_deptScrollController.offset + offset)
                .clamp(0.0, _deptScrollController.position.maxScrollExtent);
            _deptScrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            );
          }
        }

        // Department Chips Row with Left/Right Arrows, Mouse Wheel & Drag Support
        final deptChipsWidget = Row(
          children: [
            // ◀ Left Scroll Button
            InkWell(
              onTap: () => scrollDept(-220),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder, width: 1.1),
                ),
                child: Icon(Icons.chevron_left_rounded, size: 18, color: textSub),
              ),
            ),
            const SizedBox(width: 6),

            // Scrollable Chips Viewport
            Expanded(
              child: Listener(
                // Mouse wheel ko horizontal scroll me convert karta hai
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent && _deptScrollController.hasClients) {
                    final target = (_deptScrollController.offset + pointerSignal.scrollDelta.dy * 1.5)
                        .clamp(0.0, _deptScrollController.position.maxScrollExtent);
                    _deptScrollController.jumpTo(target);
                  }
                },
                child: ScrollConfiguration(
                  // Mouse drag aur touch drag allow karta hai
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: _deptScrollController,
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
                                    ? (isCompact
                                        ? null
                                        : const LinearGradient(
                                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ))
                                    : null,
                                color: isSelected
                                    ? (isCompact ? (isDark ? Colors.white : const Color(0xFF18181B)) : null)
                                    : (isCompact
                                        ? (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAFAFA))
                                        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.75))),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? (isCompact ? (isDark ? Colors.white : const Color(0xFF18181B)) : const Color(0xFF10B981))
                                      : (isCompact ? (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7)) : cardBorder),
                                  width: 1.0,
                                ),
                                boxShadow: isSelected && !isCompact
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
                                        ? (isCompact ? (isDark ? const Color(0xFF09090B) : Colors.white) : Colors.white)
                                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    df['name'],
                                    style: TextStyle(
                                      color: isSelected
                                          ? (isCompact ? (isDark ? const Color(0xFF09090B) : Colors.white) : Colors.white)
                                          : textTitle,
                                      fontSize: 12.5,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isCompact
                                              ? (isDark ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.2))
                                              : Colors.white.withValues(alpha: 0.25))
                                          : (isCompact
                                              ? (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF4F4F5))
                                              : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0))),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        color: isSelected
                                            ? (isCompact ? (isDark ? const Color(0xFF09090B) : Colors.white) : Colors.white)
                                            : textSub,
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
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // ▶ Right Scroll Button
            InkWell(
              onTap: () => scrollDept(220),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder, width: 1.1),
                ),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: textSub),
              ),
            ),
          ],
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
            clipBehavior: Clip.none,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 460,
              mainAxisExtent: 210,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final prj = filtered[index];
              return _ProjectUnitCard(
                prj: prj,
                cardBg: cardBg,
                cardBorder: cardBorder,
                textTitle: textTitle,
                textSub: textSub,
                isDark: isDark,
                onTap: () {
                  setState(() => _selectedProject = prj);
                  _fetchProjectDetails(prj['project_id']);
                },
                onEdit: () => _openEditProjectDialog(prj),
                onDelete: () => _confirmDeleteProject(prj),
              );
            },
          ),
      ],
    );
  }

  // ================= ⚡ VIEW B: GENERAL TASKS (KANBAN & LIST) =================
  Widget _buildGeneralTasksKanbanView(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final isDark = ThemeController.isDarkMode.value;
    final taskCardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final allGeneral = _generalTasks;
    final filtered = _filteredGeneralTasks;

    final todo = filtered.where((t) => _taskStatus(t) == 'TODO').toList();
    final inProgress = filtered.where((t) => _taskStatus(t) == 'IN_PROGRESS').toList();
    final done = filtered.where((t) => _taskStatus(t) == 'DONE').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Slim Compact Header (~55px height saving over 140px)
        _buildGeneralTasksHero(allGeneral, cardBg, cardBorder, textTitle, textSub, isDark),
        if (allGeneral.isNotEmpty) ...[
          const SizedBox(height: 12),
          // 2. Toolbar with Board ⮂ List View Switcher
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
        const SizedBox(height: 12),
        if (allGeneral.isEmpty)
          _buildGeneralTasksEmptyState(cardBg, cardBorder, textTitle, textSub, isDark)
        else if (_genViewMode == 'LIST')
        // 3A. Modern Compact List / Table View
          _buildGeneralTasksListView(filtered, cardBg, cardBorder, textTitle, textSub, isDark)
        else
        // 3B. High-Density Kanban Board with Independent Column Scrolling
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 820;
              if (isCompact) {
                // 📱 MOBILE: Direct tasks list - no outer column box, no duplicate header, natural page scrolling!
                final activeList = _genMobileColumnTab == 'TODO'
                    ? todo
                    : (_genMobileColumnTab == 'IN_PROGRESS' ? inProgress : done);
                final activeColor = _genMobileColumnTab == 'TODO'
                    ? const Color(0xFF3B82F6)
                    : (_genMobileColumnTab == 'IN_PROGRESS'
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981));
                final activeTitle = _genMobileColumnTab == 'TODO'
                    ? 'To Do'
                    : (_genMobileColumnTab == 'IN_PROGRESS' ? 'In Progress' : 'Completed');

                if (activeList.isEmpty) {
                  return _buildKanbanColumnEmptyState(activeTitle, isDark, cardBorder, textTitle, textSub);
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeList.length,
                  padding: const EdgeInsets.only(top: 4, bottom: 20),
                  itemBuilder: (context, i) => _buildGeneralTaskCard(
                    activeList[i],
                    activeColor,
                    taskCardBg,
                    cardBorder,
                    textTitle,
                    textSub,
                    isDark,
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildKanbanColumn('To Do', Icons.radio_button_unchecked_rounded, todo, const Color(0xFF3B82F6), cardBg, cardBorder, textTitle, textSub)),
                  const SizedBox(width: 14),
                  Expanded(child: _buildKanbanColumn('In Progress', Icons.timelapse_rounded, inProgress, const Color(0xFFF59E0B), cardBg, cardBorder, textTitle, textSub)),
                  const SizedBox(width: 14),
                  Expanded(child: _buildKanbanColumn('Completed', Icons.task_alt_rounded, done, const Color(0xFF10B981), cardBg, cardBorder, textTitle, textSub)),
                ],
              );
            },
          ),
      ],
    );
  }

  // ---------- 🟢 GENERAL TASKS: SLIM HERO SUMMARY ----------
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
    final overdue = tasks.where((t) => _isTaskOverdue(t)).length;
    final completed = tasks.where((t) => _taskStatus(t) == 'DONE').length;
    final progress = total > 0 ? (completed / total) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;

        // 📱 MOBILE VIEW: Clean, modern, matching Image 2
        if (isNarrow) {
          final todoCount = tasks.where((t) => _taskStatus(t) == 'TODO').length;
          final inProgCount = tasks.where((t) => _taskStatus(t) == 'IN_PROGRESS').length;
          final doneCount = tasks.where((t) => _taskStatus(t) == 'DONE').length;

          return Container(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Title + Subtitle + Notification Bell Button Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'General tasks',
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF09090B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$total tasks · ${(progress * 100).round()}% done',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : const Color(0xFF71717A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Notification Bell in rounded box
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          size: 19,
                          color: isDark ? Colors.white : const Color(0xFF09090B),
                        ),
                        onPressed: _isLoading ? null : _refreshAll,
                        tooltip: 'Refresh',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Monochrome Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 4.5,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : const Color(0xFFE4E4E7),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.white : const Color(0xFF18181B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Status Tabs with Pill Badges (To do, In progress, Done)
                Row(
                  children: [
                    _buildMobileKanbanTabItem('To do', todoCount, _genMobileColumnTab == 'TODO', () {
                      setState(() => _genMobileColumnTab = 'TODO');
                    }, isDark ? Colors.white : const Color(0xFF09090B), isDark ? Colors.white60 : const Color(0xFF71717A), isDark),
                    const SizedBox(width: 18),
                    _buildMobileKanbanTabItem('In progress', inProgCount, _genMobileColumnTab == 'IN_PROGRESS', () {
                      setState(() => _genMobileColumnTab = 'IN_PROGRESS');
                    }, isDark ? Colors.white : const Color(0xFF09090B), isDark ? Colors.white60 : const Color(0xFF71717A), isDark),
                    const SizedBox(width: 18),
                    _buildMobileKanbanTabItem('Done', doneCount, _genMobileColumnTab == 'DONE', () {
                      setState(() => _genMobileColumnTab = 'DONE');
                    }, isDark ? Colors.white : const Color(0xFF09090B), isDark ? Colors.white60 : const Color(0xFF71717A), isDark),
                  ],
                ),
              ],
            ),
          );
        }

        // 💻 DESKTOP / WEB VIEW (100% UNTOUCHED)
        final titleRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'General Tasks',
                  style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$total task${total == 1 ? '' : 's'} • ${(progress * 100).round()}% done',
                  style: TextStyle(color: textSub, fontSize: 11),
                ),
              ],
            ),
          ],
        );

        final pills = Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildGeneralTaskStatPill('Total', '$total', Icons.layers_outlined, const Color(0xFF3B82F6), isDark, cardBorder, textTitle, textSub),
            _buildGeneralTaskStatPill('In Progress', '$inProgress', Icons.timelapse_rounded, const Color(0xFFF59E0B), isDark, cardBorder, textTitle, textSub),
            _buildGeneralTaskStatPill('Overdue', '$overdue', Icons.warning_amber_rounded, const Color(0xFFEF4444), isDark, cardBorder, textTitle, textSub, selected: _genOnlyOverdue, onTap: () => setState(() => _genOnlyOverdue = !_genOnlyOverdue)),
            _buildGeneralTaskStatPill('Completed', '$completed', Icons.task_alt_rounded, const Color(0xFF10B981), isDark, cardBorder, textTitle, textSub),
            IconButton(
              tooltip: 'Refresh tasks',
              onPressed: _isLoading ? null : _refreshAll,
              icon: Icon(Icons.refresh_rounded, size: 17, color: textSub),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              style: IconButton.styleFrom(
                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.82),
                side: BorderSide(color: cardBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder, width: 1.1),
          ),
          child: Row(
            children: [
              titleRow,
              const Spacer(),
              pills,
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileKanbanTabItem(
    String label,
    int count,
    bool isSelected,
    VoidCallback onTap,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    final titleCol = isDark ? Colors.white : const Color(0xFF09090B);
    final mutedCol = isDark ? Colors.white60 : const Color(0xFF71717A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: isSelected
              ? Border(
                  bottom: BorderSide(
                    color: titleCol,
                    width: 2.2,
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? titleCol : mutedCol,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? titleCol : mutedCol,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: isDark ? 0.22 : 0.12)
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.78)),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? color.withValues(alpha: 0.55) : cardBorder,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: textTitle, fontSize: 11.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: textSub, fontSize: 10.5),
          ),
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

  // ---------- 🔍 GENERAL TASKS: TOOLBAR WITH BOARD/LIST TOGGLE ----------
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 850;

        // 📱 MOBILE TOKENS (User palette)
        final mBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7);
        final mTitle = isDark ? Colors.white : const Color(0xFF09090B);
        final mBody = isDark ? Colors.white70 : const Color(0xFF52525B);
        final mMuted = isDark ? Colors.white38 : const Color(0xFF71717A);
        final mInputFill = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAFAFA);

        final searchField = SizedBox(
          height: 38,
          child: TextField(
            controller: _genTaskSearchController,
            onChanged: (val) => setState(() => _genTaskSearchQuery = val),
            style: TextStyle(color: isCompact ? mTitle : textTitle, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search tasks, #ID, assignee...',
              hintStyle: TextStyle(
                color: isCompact ? mMuted : textSub.withValues(alpha: 0.65),
                fontSize: 12.5,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 17,
                color: isCompact ? mMuted : textSub,
              ),
              suffixIcon: _genTaskSearchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 15),
                color: isCompact ? mMuted : textSub,
                onPressed: () {
                  _genTaskSearchController.clear();
                  setState(() => _genTaskSearchQuery = '');
                },
              )
                  : null,
              filled: true,
              fillColor: isCompact ? mInputFill : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.95)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isCompact ? mBorder : cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isCompact ? mBorder : cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isCompact ? (isDark ? Colors.white : const Color(0xFF18181B)) : const Color(0xFF10B981),
                  width: 1.2,
                ),
              ),
            ),
          ),
        );

        // View Switcher (Board vs List)
        final viewSwitcher = Container(
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isCompact
                ? mInputFill
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.92)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isCompact ? mBorder : cardBorder, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildViewModeOption('KANBAN', Icons.view_kanban_outlined, 'Board', isDark),
              _buildViewModeOption('LIST', Icons.format_list_bulleted_rounded, 'List', isDark),
            ],
          ),
        );

        final filterWidgets = <Widget>[
          _buildGeneralPriorityMenu(isCompact ? mBorder : cardBorder, isCompact ? mTitle : textTitle, isCompact ? mBody : textSub, isDark, isMobile: isCompact),
          _buildGeneralAssigneeMenu(isCompact ? mBorder : cardBorder, isCompact ? mTitle : textTitle, isCompact ? mBody : textSub, isDark, isMobile: isCompact),
          _buildGeneralSortMenu(isCompact ? mBorder : cardBorder, isCompact ? mTitle : textTitle, isCompact ? mBody : textSub, isDark, isMobile: isCompact),
          if (filtersActive) _buildGeneralResetButton(isCompact ? mBorder : cardBorder, isDark),
          viewSwitcher,
        ];

        return Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isCompact
                ? (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFFFFFF))
                : cardBg,
            borderRadius: BorderRadius.circular(14),
            border: isCompact ? Border.all(color: mBorder, width: 1.0) : Border.all(color: cardBorder, width: 1.1),
            boxShadow: isCompact
                ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
                : null,
          ),
          child: isCompact
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchField,
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(children: filterWidgets),
              ),
            ],
          )
              : Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 10),
              ...filterWidgets,
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewModeOption(String mode, IconData icon, String label, bool isDark) {
    final isSelected = _genViewMode == mode;
    return InkWell(
      onTap: () => setState(() => _genViewMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF10B981) : (isDark ? Colors.white70 : const Color(0xFF334155)),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _generalToolbarDecoration(bool isActive, bool isDark, Color cardBorder, {bool isMobile = false}) {
    if (isMobile) {
      return BoxDecoration(
        color: isActive
            ? (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFF4F4F5))
            : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAFAFA)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? (isDark ? Colors.white : const Color(0xFF18181B))
              : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7)),
          width: 1.0,
        ),
      );
    }
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

  Widget _buildGeneralPriorityMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark, {bool isMobile = false}) {
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
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder, isMobile: isMobile),
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

  Widget _buildGeneralAssigneeMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark, {bool isMobile = false}) {
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
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder, isMobile: isMobile),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: isActive ? (isDark ? Colors.white : const Color(0xFF09090B)) : textSub,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? (isDark ? Colors.white : const Color(0xFF09090B)) : textTitle,
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

  Widget _buildGeneralSortMenu(Color cardBorder, Color textTitle, Color textSub, bool isDark, {bool isMobile = false}) {
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
            decoration: _generalToolbarDecoration(isActive, isDark, cardBorder, isMobile: isMobile),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 15,
                  color: isActive ? (isDark ? Colors.white : const Color(0xFF09090B)) : textSub,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? (isDark ? Colors.white : const Color(0xFF09090B)) : textTitle,
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

  // ---------- 🗂️ GENERAL TASKS: KANBAN COLUMN (INDEPENDENT SCROLLING) ----------
  Widget _buildKanbanColumn(
      String title,
      IconData icon,
      List<dynamic> list,
      Color headerColor,
      Color cardBg,
      Color cardBorder,
      Color textTitle,
      Color textSub, {
        bool isMobile = false,
      }) {
    final isDark = ThemeController.isDarkMode.value;
    final taskCardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      height: isMobile ? 420 : 620, // 👈 Pinned fixed height for independent internal column scrolling!
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned Column Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: headerColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 14, color: headerColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 13.5),
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
          const SizedBox(height: 10),
          // Scrollable Cards List
          Expanded(
            child: list.isEmpty
                ? _buildKanbanColumnEmptyState(title, isDark, cardBorder, textTitle, textSub)
                : ListView.builder(
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              itemBuilder: (context, i) => _buildGeneralTaskCard(
                list[i],
                headerColor,
                taskCardBg,
                cardBorder,
                textTitle,
                textSub,
                isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 📋 COMPACT LIST / TABLE VIEW ----------
  Widget _buildGeneralTasksListView(
      List<dynamic> list,
      Color cardBg,
      Color cardBorder,
      Color textTitle,
      Color textSub,
      bool isDark,
      ) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text('No tasks match your filters.', style: TextStyle(color: textSub, fontSize: 13)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final task = list[index];
        final status = _taskStatus(task);
        final isDone = status == 'DONE';
        final priority = (task['priority'] ?? 'MEDIUM').toString().toUpperCase();
        final priColor = _generalPriorityColor(priority);
        final isOverdue = _isTaskOverdue(task);
        final workerName = (task['assigned_worker'] ?? '').toString().trim();
        final dueChip = _buildTaskDueDateChip(task, isDone, textSub);
        final taskCardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

        final nextStatus = status == 'TODO'
            ? 'IN_PROGRESS'
            : status == 'IN_PROGRESS'
            ? 'DONE'
            : 'TODO';

        return _HoverCardItem(
          cardBg: isDone ? taskCardBg.withValues(alpha: 0.8) : taskCardBg,
          cardBorder: isOverdue ? const Color(0xFFEF4444).withValues(alpha: 0.5) : cardBorder,
          isDark: isDark,
          borderRadius: 12,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: () => _openTaskDetailsDialog(task),
          child: Row(
            children: [
              // 1. Status Check Icon
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _updateTaskStatus(task['task_id'], nextStatus),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : (status == 'IN_PROGRESS' ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded),
                    color: isDone ? const Color(0xFF10B981) : (status == 'IN_PROGRESS' ? const Color(0xFFF59E0B) : textSub),
                    size: 20,
                  ),
                ),
              ),

              // 2. Priority indicator & ID
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: priColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priority,
                  style: TextStyle(color: priColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
              if (task['task_id'] != null) ...[
                const SizedBox(width: 6),
                Text('#${task['task_id']}', style: TextStyle(color: textSub.withValues(alpha: 0.5), fontSize: 10.5, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(width: 10),

              // 3. Title & Optional Desc
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task['title'] ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDone ? textSub : textTitle,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 4. Due Date Chip
              if (dueChip != null) ...[
                dueChip,
                const SizedBox(width: 10),
              ],

              // 5. Worker Avatar & Name
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: _avatarColorForName(workerName),
                    child: Text(
                      workerName.isNotEmpty ? workerName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(
                      workerName.isEmpty ? 'Unassigned' : workerName,
                      style: TextStyle(color: textSub, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // 6. Action Buttons
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF10B981)),
                tooltip: 'Edit task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => _openEditTaskDialog(task),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                tooltip: 'Delete task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => _confirmDeleteTask(task),
              ),
            ],
          ),
        );
      },
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
    return _GeneralTaskKanbanCard(
      task: task,
      columnColor: columnColor,
      taskCardBg: taskCardBg,
      cardBorder: cardBorder,
      textTitle: textTitle,
      textSub: textSub,
      isDark: isDark,
      onTap: () => _openTaskDetailsDialog(task),
      onEdit: () => _openEditTaskDialog(task),
      onDelete: () => _confirmDeleteTask(task),
      onStatusChange: (id, next) => _updateTaskStatus(id, next),
      getPriorityColor: _generalPriorityColor,
      getAvatarColor: _avatarColorForName,
      buildDueDateChip: _buildTaskDueDateChip,
      getTaskStatus: _taskStatus,
      getTaskStatusLabel: _taskStatusLabel,
      isTaskOverdue: _isTaskOverdue,
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
                color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE4E4E7)),
              ),
              child: Text(
                prj['project_code'] ?? 'PRJ',
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF18181B), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF52525B), fontSize: 10.5, fontWeight: FontWeight.bold),
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
            boxShadow: const [],
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
                return _ProjectWorkspaceTaskCard(
                  task: t,
                  taskCardBg: taskCardBg,
                  cardBorder: cardBorder,
                  textTitle: textTitle,
                  textSub: textSub,
                  isDark: isDark,
                  isMobile: isMobile,
                  onToggleStatus: () {
                    final isDone = t['status'] == 'DONE';
                    final next = isDone ? 'TODO' : 'DONE';
                    _updateTaskStatus(t['task_id'], next);
                  },
                  onOpenDetails: () => _openTaskDetailsDialog(t),
                  onEdit: () => _openTaskDetailsDialog(t),
                  onDelete: () => _confirmDeleteTask(t),
                  onToggleSubtask: (subtaskId, val) => _toggleSubtask(subtaskId, val),
                  onDeleteSubtask: (subtaskId) async {
                    try {
                      await http.delete(Uri.parse('$_apiHost/api/projects/subtasks/$subtaskId'));
                      if (_selectedProject != null) _fetchProjectDetails(_selectedProject!['project_id']);
                    } catch (_) {}
                  },
                  onUpdateStatus: (taskId, next) => _updateTaskStatus(taskId, next),
                  onAddSubtask: (taskId, title) => _openAddSubtaskDialog(taskId, title),
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
            boxShadow: const [],
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
            boxShadow: const [],
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
                    boxShadow: const [],
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

// =========================================================================
// 📂 1. PROJECT CARD (HOVER ANIMATED - MATCHING DEPARTMENTS)
// =========================================================================
class _ProjectUnitCard extends StatefulWidget {
  final dynamic prj;
  final Color cardBg;
  final Color cardBorder;
  final Color textTitle;
  final Color textSub;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProjectUnitCard({
    required this.prj,
    required this.cardBg,
    required this.cardBorder,
    required this.textTitle,
    required this.textSub,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ProjectUnitCard> createState() => _ProjectUnitCardState();
}

class _ProjectUnitCardState extends State<_ProjectUnitCard> {
  bool _hovered = false;
  static const Color _accent = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    final prj = widget.prj;
    final totalTasks = prj['total_tasks'] ?? 0;
    final completedTasks = prj['completed_tasks'] ?? 0;
    final progress = totalTasks > 0 ? (completedTasks / totalTasks) : 0.0;
    final isDark = widget.isDark;
    final textTitle = widget.textTitle;
    final textSub = widget.textSub;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: widget.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovered
                ? _accent.withValues(alpha: 0.55)
                : widget.cardBorder,
            width: _hovered ? 1.4 : 1.1,
          ),
          boxShadow: const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onTap,
                hoverColor: _accent.withValues(alpha: 0.03),
                child: Padding(
                  padding: const EdgeInsets.all(18),
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
                            child: Text(
                              prj['project_code'] ?? 'PRJ',
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
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
                            child: Text(
                              prj['status'] ?? 'Active',
                              style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
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
                                  widget.onEdit();
                                } else if (val == 'delete') {
                                  widget.onDelete();
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
                                        decoration: const BoxDecoration(
                                          color: Color(0x23EF4444),
                                          borderRadius: BorderRadius.all(Radius.circular(8)),
                                        ),
                                        child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.redAccent),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
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
                      Text(
                        prj['project_name'] ?? 'Untitled Project',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// ⚡ 2. GENERAL TASK KANBAN CARD (HOVER ANIMATED)
// =========================================================================
class _GeneralTaskKanbanCard extends StatefulWidget {
  final dynamic task;
  final Color columnColor;
  final Color taskCardBg;
  final Color cardBorder;
  final Color textTitle;
  final Color textSub;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(int, String) onStatusChange;
  final Color Function(String) getPriorityColor;
  final Color Function(String) getAvatarColor;
  final Widget? Function(dynamic, bool, Color) buildDueDateChip;
  final String Function(dynamic) getTaskStatus;
  final String Function(String) getTaskStatusLabel;
  final bool Function(dynamic) isTaskOverdue;

  const _GeneralTaskKanbanCard({
    required this.task,
    required this.columnColor,
    required this.taskCardBg,
    required this.cardBorder,
    required this.textTitle,
    required this.textSub,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChange,
    required this.getPriorityColor,
    required this.getAvatarColor,
    required this.buildDueDateChip,
    required this.getTaskStatus,
    required this.getTaskStatusLabel,
    required this.isTaskOverdue,
  });

  @override
  State<_GeneralTaskKanbanCard> createState() => _GeneralTaskKanbanCardState();
}

class _GeneralTaskKanbanCardState extends State<_GeneralTaskKanbanCard> {
  bool _hovered = false;
  static const Color _accent = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final status = widget.getTaskStatus(task);
    final isDone = status == 'DONE';
    final isOverdue = widget.isTaskOverdue(task);
    final priority = (task['priority'] ?? 'MEDIUM').toString().toUpperCase();
    final priorityColor = widget.getPriorityColor(priority);
    final workerName = (task['assigned_worker'] ?? '').toString().trim();
    final subtasks = (task['subtasks'] as List<dynamic>?) ?? [];
    final doneSubtasks = subtasks
        .where((s) => s['is_completed'] == 1 || s['is_completed'] == true)
        .length;
    final dueChip = widget.buildDueDateChip(task, isDone, widget.textSub);

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

    final isMobile = MediaQuery.of(context).size.width < 820;
    final mobileTextTitle = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final mobileTextSub = widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // 📱 MOBILE: DESIGN B (ULTRA-COMPACT LIST ITEM - 55-60PX HEIGHT)
    if (isMobile) {
      return _buildMobileCompactListItem(
        context: context,
        task: task,
        status: status,
        isDone: isDone,
        isOverdue: isOverdue,
        priority: priority,
        priorityColor: priorityColor,
        workerName: workerName,
        subtasks: subtasks,
        doneSubtasks: doneSubtasks,
        nextStatus: nextStatus,
        mobileTextTitle: mobileTextTitle,
        mobileTextSub: mobileTextSub,
      );
    }

    final cardTitleColor = isDone
        ? widget.textTitle.withValues(alpha: 0.72)
        : widget.textTitle;

    final baseBorderColor = isOverdue
        ? const Color(0xFFEF4444).withValues(alpha: 0.5)
        : isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.28)
            : widget.cardBorder;

    final hoverBorderColor = isOverdue
        ? const Color(0xFFEF4444).withValues(alpha: 0.7)
        : _accent.withValues(alpha: 0.55);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 11),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: isDone ? widget.taskCardBg.withValues(alpha: 0.84) : widget.taskCardBg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: _hovered ? hoverBorderColor : baseBorderColor,
            width: _hovered ? 1.4 : (isOverdue ? 1.3 : 1.1),
          ),
          boxShadow: const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: widget.onTap,
            hoverColor: _accent.withValues(alpha: 0.03),
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
                            color: widget.textSub.withValues(alpha: 0.55),
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
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                        tooltip: 'Delete task',
                        splashRadius: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    task['title'] ?? 'Untitled',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDone ? widget.textTitle.withValues(alpha: 0.72) : widget.textTitle,
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
                      style: TextStyle(color: widget.textSub, fontSize: 11.5, height: 1.3),
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
                        Icon(Icons.checklist_rounded, size: 12.5, color: widget.textSub),
                        const SizedBox(width: 4),
                        Text(
                          '$doneSubtasks/${subtasks.length} subtasks',
                          style: TextStyle(color: widget.textSub, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          '${((doneSubtasks / subtasks.length) * 100).round()}%',
                          style: TextStyle(
                            color: doneSubtasks == subtasks.length
                                ? const Color(0xFF10B981)
                                : widget.textSub,
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
                        backgroundColor: widget.isDark
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 9,
                            backgroundColor: widget.getAvatarColor(workerName),
                            child: Text(
                              workerName.isNotEmpty ? workerName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (task['assignees'] is List && (task['assignees'] as List).length > 1) ...[
                            const SizedBox(width: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+${(task['assignees'] as List).length - 1}',
                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          workerName.isEmpty ? 'Unassigned' : workerName,
                          style: TextStyle(color: widget.textTitle, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Move to ${widget.getTaskStatusLabel(nextStatus)}',
                        child: InkWell(
                          onTap: () => widget.onStatusChange(task['task_id'], nextStatus),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.columnColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: widget.columnColor.withValues(alpha: 0.24),
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(nextIcon, size: 12, color: widget.columnColor),
                                const SizedBox(width: 3),
                                Text(
                                  nextLabel,
                                  style: TextStyle(
                                    color: widget.columnColor,
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
      ),
    );
  }

  // ================= 📱 ULTRA-COMPACT MOBILE LIST ITEM (DESIGN B) =================
  Widget _buildMobileCompactListItem({
    required BuildContext context,
    required dynamic task,
    required String status,
    required bool isDone,
    required bool isOverdue,
    required String priority,
    required Color priorityColor,
    required String workerName,
    required List<dynamic> subtasks,
    required int doneSubtasks,
    required String nextStatus,
    required Color mobileTextTitle,
    required Color mobileTextSub,
  }) {
    DateTime? due;
    if (task['due_date'] != null) {
      try {
        due = DateTime.parse(task['due_date'].toString());
      } catch (_) {}
    }

    final assignees = (task['assignees'] is List) ? (task['assignees'] as List) : [];
    final assigneesCount = assignees.length;

    String? dueLabel;
    Color dueColor = mobileTextSub;
    if (due != null) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dueLabel = '${due.day} ${months[due.month - 1]}';
      if (isDone) {
        dueColor = const Color(0xFF10B981);
      } else if (isOverdue) {
        dueColor = const Color(0xFFEF4444);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: isDone
            ? (widget.isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF4F4F5))
            : (widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? const Color(0xFFEF4444).withValues(alpha: 0.35)
              : (widget.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE4E4E7)),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.22 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Status Toggle Check Icon
                InkWell(
                  onTap: () => widget.onStatusChange(task['task_id'], nextStatus),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 9, top: 1, bottom: 1),
                    child: Icon(
                      isDone
                          ? Icons.check_circle_rounded
                          : (status == 'IN_PROGRESS'
                              ? Icons.timelapse_rounded
                              : Icons.radio_button_unchecked_rounded),
                      size: 21,
                      color: isDone
                          ? (widget.isDark ? Colors.white : const Color(0xFF18181B))
                          : (status == 'IN_PROGRESS' ? const Color(0xFFF59E0B) : (widget.isDark ? Colors.white54 : const Color(0xFF71717A))),
                    ),
                  ),
                ),

                // 2. Middle Content (Title + Meta row)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Line 1: Title (#09090B)
                      Text(
                        task['title'] ?? 'Untitled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDone
                              ? (widget.isDark ? Colors.white38 : const Color(0xFF71717A))
                              : (widget.isDark ? Colors.white : const Color(0xFF09090B)),
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          letterSpacing: -0.2,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Line 2: Meta Info (Body #52525B, Muted #71717A)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            priority,
                            style: TextStyle(
                              color: priorityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (task['task_id'] != null) ...[
                            Text(' · ', style: TextStyle(color: widget.isDark ? Colors.white38 : const Color(0xFF71717A), fontSize: 10)),
                            Text('#${task['task_id']}', style: TextStyle(color: widget.isDark ? Colors.white60 : const Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.w500)),
                          ],
                          if (subtasks.isNotEmpty) ...[
                            Text(' · ', style: TextStyle(color: widget.isDark ? Colors.white38 : const Color(0xFF71717A), fontSize: 10)),
                            Icon(Icons.checklist_rounded, size: 11, color: doneSubtasks == subtasks.length ? (widget.isDark ? Colors.white : const Color(0xFF18181B)) : (widget.isDark ? Colors.white60 : const Color(0xFF52525B))),
                            const SizedBox(width: 2),
                            Text(
                              '$doneSubtasks/${subtasks.length}',
                              style: TextStyle(
                                color: doneSubtasks == subtasks.length ? (widget.isDark ? Colors.white : const Color(0xFF18181B)) : (widget.isDark ? Colors.white70 : const Color(0xFF52525B)),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (workerName.isNotEmpty) ...[
                            Text(' · ', style: TextStyle(color: widget.isDark ? Colors.white38 : const Color(0xFF71717A), fontSize: 10)),
                            Flexible(
                              child: Text(
                                workerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF52525B), fontSize: 10.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 3. Right: Due Date Chip (#F4F4F5 / #E4E4E7)
                if (dueLabel != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                          : (widget.isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F4F5)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isOverdue
                            ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                            : (widget.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE4E4E7)),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      dueLabel,
                      style: TextStyle(
                        color: isOverdue
                            ? const Color(0xFFEF4444)
                            : (widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF52525B)),
                        fontSize: 10,
                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // 4. Right: Worker Avatar (+1 count badge)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: widget.getAvatarColor(workerName),
                      child: Text(
                        workerName.isNotEmpty ? workerName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (assigneesCount > 1) ...[
                      const SizedBox(width: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: widget.isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF4F4F5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: widget.isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE4E4E7),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '+${assigneesCount - 1}',
                          style: TextStyle(
                            color: widget.isDark ? Colors.white : const Color(0xFF09090B),
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // 5. Right: 3-dots Menu for Edit / Delete
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 16, color: widget.isDark ? Colors.white54 : const Color(0xFF71717A)),
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Options',
                  onSelected: (val) {
                    if (val == 'edit') widget.onEdit();
                    if (val == 'delete') widget.onDelete();
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'edit',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 15, color: widget.isDark ? Colors.white : const Color(0xFF18181B)),
                          const SizedBox(width: 8),
                          const Text('Edit Task', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 15, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text('Delete Task', style: TextStyle(fontSize: 12.5, color: Colors.redAccent)),
                        ],
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
}

// =========================================================================
// 📋 3. PROJECT WORKSPACE TASK ITEM (HOVER ANIMATED)
// =========================================================================
class _ProjectWorkspaceTaskCard extends StatefulWidget {
  final dynamic task;
  final Color taskCardBg;
  final Color cardBorder;
  final Color textTitle;
  final Color textSub;
  final bool isDark;
  final bool isMobile;
  final VoidCallback onToggleStatus;
  final VoidCallback onOpenDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(int, bool) onToggleSubtask;
  final Function(int) onDeleteSubtask;
  final Function(int, String) onUpdateStatus;
  final Function(int, String) onAddSubtask;

  const _ProjectWorkspaceTaskCard({
    required this.task,
    required this.taskCardBg,
    required this.cardBorder,
    required this.textTitle,
    required this.textSub,
    required this.isDark,
    required this.isMobile,
    required this.onToggleStatus,
    required this.onOpenDetails,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleSubtask,
    required this.onDeleteSubtask,
    required this.onUpdateStatus,
    required this.onAddSubtask,
  });

  @override
  State<_ProjectWorkspaceTaskCard> createState() => _ProjectWorkspaceTaskCardState();
}

class _ProjectWorkspaceTaskCardState extends State<_ProjectWorkspaceTaskCard> {
  bool _hovered = false;
  static const Color _accent = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final subtasks = (t['subtasks'] as List<dynamic>?) ?? [];
    final priority = (t['priority'] ?? 'MEDIUM').toString().toUpperCase();
    final isDone = t['status'] == 'DONE';

    Color priColor = Colors.grey;
    if (priority == 'URGENT') priColor = const Color(0xFFEF4444);
    if (priority == 'HIGH') priColor = const Color(0xFFF97316);
    if (priority == 'MEDIUM') priColor = const Color(0xFFF59E0B);
    if (priority == 'LOW') priColor = const Color(0xFF10B981);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 14),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        padding: EdgeInsets.symmetric(
          horizontal: widget.isMobile ? 14 : 18,
          vertical: widget.isMobile ? 12 : 16,
        ),
        decoration: BoxDecoration(
          color: widget.taskCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? _accent.withValues(alpha: 0.55) : widget.cardBorder,
            width: _hovered ? 1.4 : 1.1,
          ),
          boxShadow: const [],
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
                  onTap: widget.onToggleStatus,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1, right: 10),
                    child: Icon(
                      isDone ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: isDone ? const Color(0xFF10B981) : widget.textSub,
                      size: 21,
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onOpenDetails,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t['title'] ?? '',
                                  style: TextStyle(
                                    color: isDone ? widget.textSub : widget.textTitle,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: widget.textSub.withValues(alpha: 0.4)),
                            ],
                          ),
                          if (t['description'] != null && t['description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              t['description'],
                              style: TextStyle(color: widget.textSub, fontSize: 12, height: 1.3),
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
                  onPressed: widget.onEdit,
                ),
                const SizedBox(width: 4),
                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                  tooltip: 'Delete Task',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onDelete,
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
                  color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
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
                                onChanged: (val) => widget.onToggleSubtask(st['subtask_id'], val ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                st['title'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: stDone ? widget.textSub : widget.textTitle,
                                  decoration: stDone ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              onPressed: () => widget.onDeleteSubtask(st['subtask_id']),
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
                    Text(t['assigned_worker'] ?? 'Unassigned', style: TextStyle(color: widget.textTitle, fontSize: 12)),
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
                    widget.onUpdateStatus(t['task_id'], next);
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
                        color: isDone ? const Color(0xFF10B981) : (t['status'] == 'IN_PROGRESS' ? const Color(0xFFD97706) : widget.textSub),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // + Add Item Link
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => widget.onAddSubtask(t['task_id'], t['title'] ?? ''),
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
      ),
    );
  }
}
// =========================================================================
// 🖱️ REUSABLE HOVER CARD ITEM (SMOOTH LIFT & GLOW)
// =========================================================================
class _HoverCardItem extends StatefulWidget {
  final Widget child;
  final Color cardBg;
  final Color cardBorder;
  final bool isDark;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const _HoverCardItem({
    required this.child,
    required this.cardBg,
    required this.cardBorder,
    required this.isDark,
    this.borderRadius = 13,
    this.margin,
    this.padding,
    this.onTap,
  });

  @override
  State<_HoverCardItem> createState() => _HoverCardItemState();
}

class _HoverCardItemState extends State<_HoverCardItem> {
  bool _hovered = false;
  static const Color _accent = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: widget.margin,
        transform: Matrix4.translationValues(0, _hovered ? -2.5 : 0, 0),
        decoration: BoxDecoration(
          color: widget.cardBg,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _hovered ? _accent.withValues(alpha: 0.55) : widget.cardBorder,
            width: _hovered ? 1.4 : 1.1,
          ),
          boxShadow: const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap,
            hoverColor: _accent.withValues(alpha: 0.03),
            child: Padding(
              padding: widget.padding ?? const EdgeInsets.all(12),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}