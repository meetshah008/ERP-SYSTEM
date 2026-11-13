import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';

class TaskDetailsScreen extends StatefulWidget {
  final dynamic taskId;
  final dynamic initialTask;
  final dynamic projectId;
  final List<dynamic>? employees;
  final VoidCallback? onTaskUpdated;

  const TaskDetailsScreen({
    super.key,
    required this.taskId,
    this.initialTask,
    this.projectId,
    this.employees,
    this.onTaskUpdated,
  });

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  Map<String, dynamic>? _task;
  List<dynamic> _employees = [];
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  // Edit Form Controllers
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _newSubtaskCtrl = TextEditingController();
  String _selectedPriority = 'MEDIUM';
  String _selectedStatus = 'TODO';
  int? _selectedAssigneeId;
  DateTime? _selectedDueDate;

  // Log Hours Form Controllers (Inline - NO POPUP)
  final _logHoursCtrl = TextEditingController();
  final _logDescCtrl = TextEditingController();
  int? _logWorkerId;
  bool _isLoggingHours = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTask != null && widget.initialTask is Map) {
      _task = Map<String, dynamic>.from(widget.initialTask as Map);
      _initFormValues();
    }
    if (widget.employees != null && widget.employees!.isNotEmpty) {
      _employees = List<dynamic>.from(widget.employees!);
      final empId = _task?['assigned_to'] != null ? int.tryParse(_task!['assigned_to'].toString()) : null;
      _logWorkerId = empId ?? (_employees.isNotEmpty ? int.tryParse(_employees.first['employee_id'].toString()) : null);
    }
    _fetchTaskDetails();
    if (_employees.isEmpty) {
      _fetchEmployees();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _newSubtaskCtrl.dispose();
    _logHoursCtrl.dispose();
    _logDescCtrl.dispose();
    super.dispose();
  }

  void _initFormValues() {
    if (_task == null) return;
    _titleCtrl.text = _task!['title']?.toString() ?? '';
    _descCtrl.text = _task!['description']?.toString() ?? '';
    _hoursCtrl.text = (_task!['estimated_hours'] ?? 0).toString();
    _selectedPriority = (_task!['priority'] ?? 'MEDIUM').toString().toUpperCase();
    _selectedStatus = (_task!['status'] ?? 'TODO').toString().toUpperCase();
    if (_task!['assigned_to'] != null) {
      _selectedAssigneeId = int.tryParse(_task!['assigned_to'].toString());
    }
    if (_task!['due_date'] != null) {
      _selectedDueDate = DateTime.tryParse(_task!['due_date'].toString().split('T')[0]);
    }
    _logWorkerId = _selectedAssigneeId ?? (_employees.isNotEmpty ? int.tryParse(_employees.first['employee_id'].toString()) : null);
  }

  Future<void> _fetchTaskDetails() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/tasks/${widget.taskId}'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null && data['data'] is Map) {
          if (mounted) {
            setState(() {
              _task = Map<String, dynamic>.from(data['data'] as Map);
              _initFormValues();
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchEmployees() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _employees = (data['data'] is List) ? List<dynamic>.from(data['data']) : [];
            if (_logWorkerId == null && _employees.isNotEmpty) {
              _logWorkerId = int.tryParse(_employees.first['employee_id'].toString());
            }
          });
        }
      }
    } catch (_) {}
  }

  // 1. UPDATE TASK STATUS LIVE
  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _selectedStatus = newStatus;
      if (_task != null) _task!['status'] = newStatus;
      _hasChanges = true;
    });

    try {
      await http.put(
        Uri.parse('http://localhost:5000/api/tasks/${widget.taskId}/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': newStatus}),
      );
      widget.onTaskUpdated?.call();
      _showSnackbar('Task status changed to $newStatus', isSuccess: true);
    } catch (e) {
      _showSnackbar('Error updating status: $e', isSuccess: false);
    }
  }

  // 2. SAVE FULL TASK DETAILS (From Inline Edit Mode)
  Future<void> _saveTaskChanges() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showSnackbar('Task Title is required', isSuccess: false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'title': title,
        'description': _descCtrl.text.trim(),
        'priority': _selectedPriority,
        'status': _selectedStatus,
        'assigned_to': _selectedAssigneeId ?? _task?['assigned_to'] ?? 1,
        'project_id': _task?['project_id'] ?? widget.projectId,
        'estimated_hours': double.tryParse(_hoursCtrl.text.trim()) ?? 0,
        'due_date': _selectedDueDate?.toIso8601String().split('T')[0],
      };

      final res = await http.put(
        Uri.parse('http://localhost:5000/api/tasks/${widget.taskId}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        _hasChanges = true;
        setState(() => _isEditing = false);
        _fetchTaskDetails();
        widget.onTaskUpdated?.call();
        _showSnackbar('Task updated successfully!', isSuccess: true);
      } else {
        _showSnackbar('Failed to update task: ${res.body}', isSuccess: false);
      }
    } catch (e) {
      _showSnackbar('Network error: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 3. TOGGLE SUBTASK (Checklist item)
  Future<void> _toggleSubtask(dynamic subtaskId, bool isCompleted) async {
    setState(() {
      final rawSubtasks = _task?['subtasks'];
      if (rawSubtasks is List) {
        for (final st in rawSubtasks) {
          if (st['subtask_id'] == subtaskId) {
            st['is_completed'] = isCompleted ? 1 : 0;
            break;
          }
        }
      }
      _hasChanges = true;
    });

    try {
      await http.put(
        Uri.parse('http://localhost:5000/api/projects/subtasks/$subtaskId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'is_completed': isCompleted}),
      );
      widget.onTaskUpdated?.call();
    } catch (_) {}
  }

  // 4. ADD NEW SUBTASK (Inline input - NO POPUP)
  Future<void> _addNewSubtask() async {
    final title = _newSubtaskCtrl.text.trim();
    if (title.isEmpty) return;

    _newSubtaskCtrl.clear();
    try {
      final res = await http.post(
        Uri.parse('http://localhost:5000/api/projects/tasks/${widget.taskId}/subtasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title}),
      );

      if (res.statusCode == 201) {
        _hasChanges = true;
        _fetchTaskDetails();
        widget.onTaskUpdated?.call();
      }
    } catch (_) {}
  }

  // 5. DELETE SUBTASK
  Future<void> _deleteSubtask(dynamic subtaskId) async {
    setState(() {
      if (_task?['subtasks'] != null && _task!['subtasks'] is List) {
        (_task!['subtasks'] as List<dynamic>).removeWhere((s) => s['subtask_id'] == subtaskId);
      }
      _hasChanges = true;
    });

    try {
      await http.delete(Uri.parse('http://localhost:5000/api/projects/subtasks/$subtaskId'));
      widget.onTaskUpdated?.call();
    } catch (_) {}
  }

  // 6. LOG WORK HOURS (Inline input - NO POPUP)
  Future<void> _logWorkHours() async {
    final hours = double.tryParse(_logHoursCtrl.text.trim());
    if (hours == null || hours <= 0) {
      _showSnackbar('Please enter valid hours spent', isSuccess: false);
      return;
    }
    if (_logWorkerId == null) {
      _showSnackbar('Please select worker', isSuccess: false);
      return;
    }

    setState(() => _isLoggingHours = true);
    try {
      final projectId = _task?['project_id'] ?? widget.projectId ?? 1;
      final res = await http.post(
        Uri.parse('http://localhost:5000/api/projects/$projectId/timesheets'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'task_id': widget.taskId,
          'employee_id': _logWorkerId,
          'hours_spent': hours,
          'description': _logDescCtrl.text.trim(),
          'log_date': DateTime.now().toIso8601String().split('T')[0],
        }),
      );

      if (res.statusCode == 201) {
        _logHoursCtrl.clear();
        _logDescCtrl.clear();
        _hasChanges = true;
        _fetchTaskDetails();
        widget.onTaskUpdated?.call();
        _showSnackbar('Logged $hours hours successfully!', isSuccess: true);
      }
    } catch (e) {
      _showSnackbar('Error logging hours: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isLoggingHours = false);
    }
  }

  // 7. DELETE WHOLE TASK
  Future<void> _deleteTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Task', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to delete "${_task?['title'] ?? 'this task'}"? All checklist subtasks will also be deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(Uri.parse('http://localhost:5000/api/tasks/${widget.taskId}'));
      if (res.statusCode == 200) {
        widget.onTaskUpdated?.call();
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (_) {}
  }

  void _showSnackbar(String msg, {required bool isSuccess}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? const Color(0xFF059669) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'URGENT':
        return const Color(0xFFEF4444);
      case 'HIGH':
        return const Color(0xFFF97316);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      case 'LOW':
      default:
        return const Color(0xFF10B981);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':
        return const Color(0xFF10B981);
      case 'IN_PROGRESS':
        return const Color(0xFF2563EB);
      case 'TODO':
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0);
    final inputBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC);

    final rawSubtasks = _task?['subtasks'];
    final subtasks = rawSubtasks is List ? rawSubtasks : [];
    final rawTimesheets = _task?['timesheets'];
    final timesheets = rawTimesheets is List ? rawTimesheets : [];

    final doneSubtasks = subtasks.where((s) {
      final comp = s['is_completed'];
      return comp == 1 || comp == true || comp == '1';
    }).length;
    final totalSubtasks = subtasks.length;
    final subtaskProgress = totalSubtasks > 0 ? (doneSubtasks / totalSubtasks) : 0.0;

    final priority = (_task?['priority'] ?? _selectedPriority).toString().toUpperCase();
    final status = (_task?['status'] ?? _selectedStatus).toString().toUpperCase();
    final isDone = status == 'DONE';
    final priColor = _getPriorityColor(priority);
    final statColor = _getStatusColor(status);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF030D08) : const Color(0xFFF1F5F9),
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            children: [
              // 1. TOP APP BAR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardBg.withValues(alpha: 0.9),
                  border: Border(bottom: BorderSide(color: cardBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: textTitle,
                      tooltip: 'Back to Tasks',
                      onPressed: () => Navigator.pop(context, _hasChanges),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Task Details',
                                style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#${widget.taskId}',
                                  style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          if (_task?['project_name'] != null)
                            Text(
                              'Project: ${_task!['project_name']} (${_task!['project_code'] ?? 'PRJ'})',
                              style: TextStyle(color: textSub, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),

                    // Toggle Edit Mode Button
                    IconButton(
                      icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_note_rounded, color: _isEditing ? Colors.redAccent : const Color(0xFF2563EB)),
                      tooltip: _isEditing ? 'Cancel Edit' : 'Edit Task Details',
                      onPressed: () => setState(() {
                        if (_isEditing) _initFormValues();
                        _isEditing = !_isEditing;
                      }),
                    ),

                    // Delete Task Button
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      tooltip: 'Delete Task',
                      onPressed: _deleteTask,
                    ),
                  ],
                ),
              ),

              // 2. MAIN BODY (Scrollable Screen)
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // A. INLINE EDIT PANEL (If editing mode is active - NO POPUP)
                                if (_isEditing)
                                  _buildInlineEditCard(cardBg, cardBorder, textTitle, textSub, inputBg, isDark)
                                else ...[
                                  // B. HERO TASK STATUS CARD
                                  _buildHeroTaskCard(cardBg, cardBorder, textTitle, textSub, priColor, statColor, isDone, priority, status),
                                  const SizedBox(height: 16),

                                  // C. WORKER & ESTIMATES ROW
                                  _buildWorkerAndEstimatesRow(cardBg, cardBorder, textTitle, textSub, isDark),
                                  const SizedBox(height: 16),

                                  // D. DESCRIPTION CARD
                                  _buildDescriptionCard(cardBg, cardBorder, textTitle, textSub),
                                  const SizedBox(height: 16),

                                  // E. SUBTASKS CHECKLIST CARD (Interactive checklist + inline add)
                                  _buildChecklistCard(cardBg, cardBorder, textTitle, textSub, inputBg, subtasks, doneSubtasks, totalSubtasks, subtaskProgress, isDark),
                                  const SizedBox(height: 16),

                                  // F. TIME TRACKING & LOGGED HOURS (Interactive timesheet + inline log)
                                  _buildTimeTrackingCard(cardBg, cardBorder, textTitle, textSub, inputBg, timesheets, isDark),
                                  const SizedBox(height: 30),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= SUB-COMPONENTS (ALL FULL SCREEN - ZERO POPUPS) =================

  // 1. HERO TASK CARD
  Widget _buildHeroTaskCard(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    Color priColor,
    Color statColor,
    bool isDone,
    String priority,
    String status,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Priority & Status Badges
          Row(
            children: [
              // Priority Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: priColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: priColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_rounded, size: 14, color: priColor),
                    const SizedBox(width: 4),
                    Text(priority, style: TextStyle(color: priColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Status Dropdown / Cycle Pill
              PopupMenuButton<String>(
                tooltip: 'Change Status',
                onSelected: _updateStatus,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'TODO', child: Text('⏳ TO DO')),
                  const PopupMenuItem(value: 'IN_PROGRESS', child: Text('⚡ IN PROGRESS')),
                  const PopupMenuItem(value: 'DONE', child: Text('✅ COMPLETED')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDone ? Icons.check_circle_rounded : Icons.pending_rounded, size: 14, color: statColor),
                      const SizedBox(width: 4),
                      Text(status, style: TextStyle(color: statColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 16, color: statColor),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Quick Toggle Checkbox
              IconButton(
                icon: Icon(
                  isDone ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: isDone ? const Color(0xFF10B981) : textSub,
                  size: 26,
                ),
                tooltip: isDone ? 'Mark as Not Done' : 'Mark as Done',
                onPressed: () => _updateStatus(isDone ? 'TODO' : 'DONE'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 2: Task Title
          Text(
            _task?['title'] ?? 'Task',
            style: TextStyle(
              color: isDone ? textSub : textTitle,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              decoration: isDone ? TextDecoration.lineThrough : null,
            ),
          ),

          // Row 3: Linked Project & Due Date
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_task?['project_name'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF6366F1)),
                      const SizedBox(width: 5),
                      Text(
                        'Project: ${_task!['project_name']}',
                        style: const TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              if (_task?['due_date'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 5),
                      Text(
                        'Due: ${_task!['due_date'].toString().split('T')[0]}',
                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 2. WORKER & ESTIMATES ROW
  Widget _buildWorkerAndEstimatesRow(Color cardBg, Color cardBorder, Color textTitle, Color textSub, bool isDark) {
    final worker = _task?['assigned_worker'] ?? 'Unassigned';
    final empCode = _task?['emp_code'] ?? 'N/A';
    final desig = _task?['worker_designation'] ?? 'Operator';
    final estHours = (_task?['estimated_hours'] ?? 0).toString();
    final actHours = (_task?['actual_hours'] ?? 0).toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final children = [
          // Assignee Card
          Expanded(
            flex: isNarrow ? 0 : 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                    child: Text(
                      worker.toString().isNotEmpty ? worker.toString()[0].toUpperCase() : 'W',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned To', style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(worker.toString(), style: TextStyle(color: textTitle, fontSize: 14.5, fontWeight: FontWeight.bold)),
                        Text('$empCode • $desig', style: TextStyle(color: textSub, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: isNarrow ? 0 : 14, height: isNarrow ? 12 : 0),

          // Hours & Estimates Card
          Expanded(
            flex: isNarrow ? 0 : 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated', style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Text('${estHours}h', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  Container(height: 35, width: 1, color: cardBorder),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Actual Logged', style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.hourglass_bottom_rounded, size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text('${actHours}h', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ];

        return isNarrow ? Column(children: children) : Row(children: children);
      },
    );
  }

  // 3. DESCRIPTION CARD
  Widget _buildDescriptionCard(Color cardBg, Color cardBorder, Color textTitle, Color textSub) {
    final desc = (_task?['description'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes_rounded, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text('Description & Work Brief', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc.isNotEmpty ? desc : 'No detailed description provided for this task.',
            style: TextStyle(
              color: desc.isNotEmpty ? textTitle.withValues(alpha: 0.9) : textSub,
              fontSize: 13.5,
              height: 1.5,
              fontStyle: desc.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }

  // 4. CHECKLIST / SUBTASKS CARD (Inline interactive - NO POPUP)
  Widget _buildChecklistCard(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    Color inputBg,
    List<dynamic> subtasks,
    int doneCount,
    int totalCount,
    double progress,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist_rtl_rounded, size: 18, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text('Checklist & Subtasks', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              Text('$doneCount of $totalCount completed', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
          const SizedBox(height: 14),

          // Subtasks List
          if (subtasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No checklist items yet. Add steps below to track progress.', style: TextStyle(color: textSub, fontSize: 12.5, fontStyle: FontStyle.italic)),
            )
          else
            ...subtasks.map((st) {
              final comp = st['is_completed'];
              final isComp = comp == 1 || comp == true || comp == '1';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isComp,
                      activeColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) => _toggleSubtask(st['subtask_id'], val ?? false),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        st['title']?.toString() ?? '',
                        style: TextStyle(
                          color: isComp ? textSub : textTitle,
                          fontSize: 13,
                          decoration: isComp ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'Remove',
                      onPressed: () => _deleteSubtask(st['subtask_id']),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 10),

          // INLINE ADD SUBTASK FIELD (NO POPUP!)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newSubtaskCtrl,
                  style: TextStyle(color: textTitle, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add a new checklist step...',
                    hintStyle: TextStyle(color: textSub, fontSize: 12.5),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10B981))),
                  ),
                  onSubmitted: (_) => _addNewSubtask(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Step', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _addNewSubtask,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 5. TIME TRACKING & LOGGED HOURS CARD (Inline interactive - NO POPUP)
  Widget _buildTimeTrackingCard(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    Color inputBg,
    List<dynamic> timesheets,
    bool isDark,
  ) {
    final validLogWorkers = _employees.where((e) => e['employee_id'] != null).toList();
    final hasWorker = validLogWorkers.any((e) => int.tryParse(e['employee_id'].toString()) == _logWorkerId);
    final safeLogWorkerValue = hasWorker ? _logWorkerId : (validLogWorkers.isNotEmpty ? int.tryParse(validLogWorkers.first['employee_id'].toString()) : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_filled_rounded, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text('Work Timesheets & Logged Hours', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          // Logged timesheets list
          if (timesheets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('No hours logged on this task yet.', style: TextStyle(color: textSub, fontSize: 12.5, fontStyle: FontStyle.italic)),
            )
          else
            ...timesheets.map((ts) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.timer_rounded, size: 16, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ts['worker_name']?.toString() ?? 'Worker', style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.bold)),
                          if (ts['description'] != null && ts['description'].toString().isNotEmpty)
                            Text(ts['description'].toString(), style: TextStyle(color: textSub, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${ts['hours_spent']} hrs', style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(ts['log_date']?.toString().split('T')[0] ?? '', style: TextStyle(color: textSub, fontSize: 10.5)),
                      ],
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),

          // INLINE LOG HOURS FORM (NO POPUP!)
          Text('Log Time on this Task', style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // Worker selector
              if (validLogWorkers.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    value: safeLogWorkerValue,
                    decoration: InputDecoration(
                      labelText: 'Worker',
                      labelStyle: TextStyle(color: textSub, fontSize: 12),
                      filled: true,
                      fillColor: inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                    ),
                    dropdownColor: cardBg,
                    style: TextStyle(color: textTitle, fontSize: 12.5),
                    items: validLogWorkers.map<DropdownMenuItem<int>>((e) {
                      final empId = int.tryParse(e['employee_id'].toString()) ?? 0;
                      return DropdownMenuItem<int>(
                        value: empId,
                        child: Text(e['full_name']?.toString() ?? 'Staff', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _logWorkerId = val),
                  ),
                ),

              // Hours input
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _logHoursCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: textTitle, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Hours',
                    hintText: 'e.g. 2.5',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                  ),
                ),
              ),

              // Work note
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _logDescCtrl,
                  style: TextStyle(color: textTitle, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Work Done Note',
                    hintText: 'What was worked on?',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                  ),
                ),
              ),

              // Submit Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isLoggingHours
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Log Time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _isLoggingHours ? null : _logWorkHours,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 6. INLINE EDIT CARD (WHEN USER CLICKS EDIT IN TOP BAR - NO POPUP)
  Widget _buildInlineEditCard(Color cardBg, Color cardBorder, Color textTitle, Color textSub, Color inputBg, bool isDark) {
    final priorityList = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'];
    final safePriorityValue = priorityList.contains(_selectedPriority.toUpperCase()) ? _selectedPriority.toUpperCase() : 'MEDIUM';

    final statusList = ['TODO', 'IN_PROGRESS', 'DONE'];
    final safeStatusValue = statusList.contains(_selectedStatus.toUpperCase()) ? _selectedStatus.toUpperCase() : 'TODO';

    final validAssignees = _employees.where((e) => e['employee_id'] != null).toList();
    final hasAssignee = validAssignees.any((e) => int.tryParse(e['employee_id'].toString()) == _selectedAssigneeId);
    final safeAssigneeValue = hasAssignee ? _selectedAssigneeId : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
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
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('Edit Task Details', style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _isEditing = false),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Title
          TextField(
            controller: _titleCtrl,
            style: TextStyle(color: textTitle, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Task Title',
              labelStyle: TextStyle(color: textSub),
              filled: true,
              fillColor: inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
            ),
          ),
          const SizedBox(height: 12),

          // Description
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            style: TextStyle(color: textTitle, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Description',
              labelStyle: TextStyle(color: textSub),
              filled: true,
              fillColor: inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
            ),
          ),
          const SizedBox(height: 14),

          // Row: Priority & Status
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: safePriorityValue,
                  decoration: InputDecoration(
                    labelText: 'Priority',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  dropdownColor: cardBg,
                  style: TextStyle(color: textTitle, fontSize: 13),
                  items: priorityList.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (val) => setState(() => _selectedPriority = val ?? 'MEDIUM'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: safeStatusValue,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  dropdownColor: cardBg,
                  style: TextStyle(color: textTitle, fontSize: 13),
                  items: statusList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() => _selectedStatus = val ?? 'TODO'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row: Assignee & Hours
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: safeAssigneeValue,
                  decoration: InputDecoration(
                    labelText: 'Assign Worker',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  dropdownColor: cardBg,
                  style: TextStyle(color: textTitle, fontSize: 13),
                  hint: const Text('Select Worker'),
                  items: validAssignees.map<DropdownMenuItem<int>>((e) {
                    final empId = int.tryParse(e['employee_id'].toString()) ?? 0;
                    return DropdownMenuItem<int>(
                      value: empId,
                      child: Text('${e['full_name']} (${e['emp_code'] ?? 'EMP'})', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedAssigneeId = val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hoursCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: textTitle, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Est. Hours',
                    labelStyle: TextStyle(color: textSub, fontSize: 12),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _isEditing = false),
                child: Text('Cancel', style: TextStyle(color: textSub)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save Task Changes', style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : _saveTaskChanges,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
