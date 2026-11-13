import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';

class ProjectEditScreen extends StatefulWidget {
  final Map<String, dynamic>? project; // null means CREATE mode, passed means EDIT mode
  final int? nextProjectNumber;
  final VoidCallback? onProjectUpdated;

  const ProjectEditScreen({
    super.key,
    this.project,
    this.nextProjectNumber,
    this.onProjectUpdated,
  });

  @override
  State<ProjectEditScreen> createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends State<ProjectEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isLoadingData = false;

  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _clientCtrl;
  late TextEditingController _descCtrl;

  int? _selectedLeaderId;
  int? _selectedDeptId;
  String _selectedStatus = 'Active';
  String _selectedPriority = 'MEDIUM';
  DateTime? _startDate;
  DateTime? _targetEndDate;
  final List<int> _selectedMemberIds = [];

  List<dynamic> _employees = [];
  List<dynamic> _departments = [];

  bool get isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    final p = widget.project;

    _codeCtrl = TextEditingController(text: isEdit ? (p!['project_code'] ?? '') : 'PRJ-${widget.nextProjectNumber ?? 101}');
    _nameCtrl = TextEditingController(text: isEdit ? (p!['project_name'] ?? '') : '');
    _clientCtrl = TextEditingController(text: isEdit ? (p!['client_name'] ?? '') : '');
    _descCtrl = TextEditingController(text: isEdit ? (p!['description'] ?? '') : '');
    _selectedLeaderId = isEdit ? p!['project_leader_id'] : null;
    _selectedDeptId = isEdit ? p!['department_id'] : null;
    _selectedStatus = isEdit ? (p!['status'] ?? 'Active') : 'Active';
    _selectedPriority = isEdit ? (p!['priority'] ?? 'MEDIUM').toString().toUpperCase() : 'MEDIUM';

    if (isEdit && p!['start_date'] != null) {
      try {
        _startDate = DateTime.parse(p['start_date'].toString().split('T')[0]);
      } catch (_) {}
    } else {
      _startDate = DateTime.now();
    }

    if (isEdit && p!['target_end_date'] != null) {
      try {
        _targetEndDate = DateTime.parse(p['target_end_date'].toString().split('T')[0]);
      } catch (_) {}
    } else {
      _targetEndDate = DateTime.now().add(const Duration(days: 30));
    }

    _loadInitialData();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _clientCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    try {
      // 1. Fetch Employees
      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final data = jsonDecode(empRes.body);
        if (data['success'] == true && data['data'] != null) {
          _employees = data['data'];
          if (!isEdit && _employees.isNotEmpty && _selectedLeaderId == null) {
            _selectedLeaderId = _employees[0]['employee_id'];
          }
        }
      }

      // 2. Fetch Departments
      final deptRes = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
      if (deptRes.statusCode == 200) {
        final data = jsonDecode(deptRes.body);
        if (data['success'] == true && data['data'] != null) {
          _departments = data['data'];
          // 👇 Ye 3 lines add karo taaki pehle se bana hua department select ho
          if (!isEdit && _departments.isNotEmpty && _selectedDeptId == null) {
            _selectedDeptId = int.tryParse(_departments[0]['department_id']?.toString() ?? '');
          }
        }
      }

      // 3. If Edit mode, load project members
      if (isEdit) {
        final prjId = widget.project!['project_id'];
        final prjRes = await http.get(Uri.parse('http://localhost:5000/api/projects/$prjId'));
        if (prjRes.statusCode == 200) {
          final data = jsonDecode(prjRes.body);
          if (data['success'] == true && data['data'] != null) {
            final details = data['data'];
            if (details['members'] != null && details['members'] is List) {
              _selectedMemberIds.clear();
              for (final m in details['members']) {
                if (m['employee_id'] != null) {
                  _selectedMemberIds.add(m['employee_id'] as int);
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all required fields!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'project_code': _codeCtrl.text.trim().toUpperCase(),
        'project_name': _nameCtrl.text.trim(),
        'client_name': _clientCtrl.text.trim().isEmpty ? null : _clientCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'department_id': _selectedDeptId,
        'project_leader_id': _selectedLeaderId,
        'priority': _selectedPriority,
        'status': _selectedStatus,
        'start_date': _startDate != null ? _formatDateDb(_startDate!) : null,
        'target_end_date': _targetEndDate != null ? _formatDateDb(_targetEndDate!) : null,
        'member_ids': _selectedMemberIds,
      };

      final http.Response res;
      if (isEdit) {
        final projectId = widget.project!['project_id'];
        res = await http.put(
          Uri.parse('http://localhost:5000/api/projects/$projectId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } else {
        res = await http.post(
          Uri.parse('http://localhost:5000/api/projects'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      }

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if ((res.statusCode == 200 || res.statusCode == 201) && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(isEdit ? 'Project updated successfully!' : 'Project created successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        widget.onProjectUpdated?.call();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? (isEdit ? 'Failed to update project' : 'Failed to create project')),
            backgroundColor: Colors.redAccent,
          ),
        );
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

  String _formatDateDb(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDateDisplay(DateTime? d) {
    if (d == null) return 'Select Date';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
          // 1. TOP HEADER
          _buildHeader(textTitle, textSub, cardBorder, isDark, isMobile),

          // 2. FORM CONTENT
          Expanded(
            child: _isLoadingData
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                : Form(
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
                        // CARD 1: Identity & Status
                        _buildCard(
                          title: 'Project Identity & Status',
                          subtitle: 'Unique code, project name, delivery priority and stage',
                          icon: Icons.folder_special_outlined,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            // Row 1: Code & Status
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Project Code *', isDark),
                                  TextFormField(
                                    controller: _codeCtrl,
                                    textCapitalization: TextCapitalization.characters,
                                    style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.bold),
                                    decoration: _inputDecoration('e.g. PRJ-101', Icons.tag_rounded, isDark),
                                    validator: (v) => v!.trim().isEmpty ? 'Project code required' : null,
                                  ),
                                ],
                              ),
                              second: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Lifecycle Status', isDark),
                                  DropdownButtonFormField<String>(
                                    value: _selectedStatus,
                                    isExpanded: true,
                                    dropdownColor: cardBg,
                                    style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.w600),
                                    decoration: _inputDecoration('Status', Icons.flag_outlined, isDark),
                                    items: const [
                                      DropdownMenuItem(value: 'Active', child: Text('Active (In Progress)')),
                                      DropdownMenuItem(value: 'Planning', child: Text('Planning Stage')),
                                      DropdownMenuItem(value: 'On Hold', child: Text('On Hold (Paused)')),
                                      DropdownMenuItem(value: 'Completed', child: Text('Completed (Delivered)')),
                                      DropdownMenuItem(value: 'Archived', child: Text('Archived')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedStatus = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Row 2: Project Title
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Project Name / Title *', isDark),
                                TextFormField(
                                  controller: _nameCtrl,
                                  style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold),
                                  decoration: _inputDecoration('e.g. Embedded Hardware Batch Assembly', Icons.assignment_outlined, isDark),
                                  validator: (v) => v!.trim().isEmpty ? 'Project name is required' : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Row 3: Priority Selector Chips
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Project Priority Level', isDark),
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
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // CARD 2: Department, Client & Team Leadership
                        _buildCard(
                          title: 'Department, Client & Leadership',
                          subtitle: 'Assign owner, responsible department, and customer details',
                          icon: Icons.people_outline_rounded,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Responsible Department', isDark),
                                  DropdownButtonFormField<int?>(
                                    value: _selectedDeptId,
                                    isExpanded: true,
                                    dropdownColor: cardBg,
                                    style: TextStyle(color: textTitle, fontSize: 13.5),
                                    decoration: _inputDecoration('Department', Icons.apartment_rounded, isDark),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('General / Cross-functional', style: TextStyle(color: Colors.grey)),
                                        ),
                                        ..._departments.map<DropdownMenuItem<int?>>((d) {
                                          final deptId = int.tryParse(d['department_id']?.toString() ?? '') ?? (d['department_id'] as int?);
                                          final deptName = (d['name'] ?? d['department_name'] ?? 'Department').toString();
                                          return DropdownMenuItem<int?>(
                                            value: deptId,
                                            child: Text(deptName),
                                          );
                                        }),
                                      ],
                                    onChanged: (val) => setState(() => _selectedDeptId = val),
                                  ),
                                ],
                              ),
                              second: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Client / Customer Name', isDark),
                                  TextFormField(
                                    controller: _clientCtrl,
                                    style: TextStyle(color: textTitle, fontSize: 13.5),
                                    decoration: _inputDecoration('e.g. Apex Tech Solutions', Icons.business_outlined, isDark),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Project Leader Dropdown
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Project Leader / Manager', isDark),
                                DropdownButtonFormField<int?>(
                                  value: _selectedLeaderId,
                                  isExpanded: true,
                                  dropdownColor: cardBg,
                                  style: TextStyle(color: textTitle, fontSize: 13.5),
                                  decoration: _inputDecoration('Select Project Lead', Icons.shield_outlined, isDark),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Unassigned (No Leader)', style: TextStyle(color: Colors.grey)),
                                    ),
                                    ..._employees.map<DropdownMenuItem<int?>>((e) {
                                      return DropdownMenuItem<int?>(
                                        value: e['employee_id'],
                                        child: Text('${e['full_name']} (${e['emp_code'] ?? 'EMP'})'),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) => setState(() => _selectedLeaderId = val),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Multi-Select Team Members Chips
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildLabel('Assigned Team Members (${_selectedMemberIds.length})', isDark),
                                    if (_selectedMemberIds.isNotEmpty)
                                      InkWell(
                                        onTap: () => setState(() => _selectedMemberIds.clear()),
                                        child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                  ),
                                  child: _employees.isEmpty
                                      ? Text('No employees found', style: TextStyle(color: textSub, fontSize: 12))
                                      : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _employees.map<Widget>((e) {
                                      final id = e['employee_id'] as int;
                                      final isSelected = _selectedMemberIds.contains(id);
                                      return FilterChip(
                                        selected: isSelected,
                                        showCheckmark: true,
                                        checkmarkColor: Colors.white,
                                        selectedColor: const Color(0xFF059669),
                                        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        label: Text(
                                          '${e['full_name']} (${e['emp_code'] ?? 'EMP'})',
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : textTitle,
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: isSelected ? const Color(0xFF059669) : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                                          ),
                                        ),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedMemberIds.add(id);
                                            } else {
                                              _selectedMemberIds.remove(id);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // CARD 3: Timeline & Dates
                        _buildCard(
                          title: 'Delivery Timeline & Deadlines',
                          subtitle: 'Set the kickoff date and estimated target completion',
                          icon: Icons.calendar_month_outlined,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            _buildResponsiveRow(
                              isMobile: isMobile,
                              first: _buildDatePickerField(
                                label: 'Start Date (Kickoff)',
                                date: _startDate,
                                isDark: isDark,
                                textTitle: textTitle,
                                textSub: textSub,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) setState(() => _startDate = picked);
                                },
                              ),
                              second: _buildDatePickerField(
                                label: 'Target Completion Date',
                                date: _targetEndDate,
                                isDark: isDark,
                                textTitle: textTitle,
                                textSub: textSub,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _targetEndDate ?? DateTime.now().add(const Duration(days: 30)),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) setState(() => _targetEndDate = picked);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // CARD 4: Technical Scope & Description
                        _buildCard(
                          title: 'Technical Scope & Deliverables',
                          subtitle: 'Architecture specs, requirements, deliverables & notes',
                          icon: Icons.description_outlined,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: cardBorder,
                          textTitle: textTitle,
                          textSub: textSub,
                          children: [
                            _buildLabel('Scope Description & Technical Deliverables', isDark),
                            TextFormField(
                              controller: _descCtrl,
                              minLines: 4,
                              maxLines: 8,
                              style: TextStyle(color: textTitle, fontSize: 13.5),
                              decoration: _inputDecoration(
                                'Enter detailed project scope, customer expectations, architecture, notes...',
                                Icons.notes_rounded,
                                isDark,
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
          if (isMobile) _buildMobileBottomBar(isDark, cardBorder),
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
      body: BotanicalBackground(
        showThemeToggle: false,
        child: mainContent,
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
                  isEdit ? 'Edit Project Scope' : 'Create Deliverable Project',
                  style: TextStyle(
                    color: textTitle,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isEdit
                      ? 'Code: ${_codeCtrl.text} • Scope, Timeline & Team Allocation'
                      : 'Initialize new project deliverable, leader, timeline & team',
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
            onPressed: _isSaving ? null : _saveProject,
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
              _isSaving ? 'Saving...' : (isEdit ? (isMobile ? 'Save' : 'Save Changes') : (isMobile ? 'Create' : 'Create Project')),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
            ),
          ),
        ],
      ),
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

  Widget _buildMobileBottomBar(bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: borderColor),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
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
              onPressed: _isSaving ? null : _saveProject,
              icon: _isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 16),
              label: Text(
                _isSaving ? 'Saving...' : (isEdit ? 'Save Changes' : 'Create Project'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveRow({
    required bool isMobile,
    required Widget first,
    required Widget second,
  }) {
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

  Widget _buildPriorityChip(String key, String label, Color color) {
    final isSelected = _selectedPriority == key;
    final isDark = ThemeController.isDarkMode.value;

    return InkWell(
      onTap: () => setState(() => _selectedPriority = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.12)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: isSelected ? color : Colors.grey, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF475569)),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime? date,
    required bool isDark,
    required Color textTitle,
    required Color textSub,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label, isDark),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined, color: Color(0xFF059669), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatDateDisplay(date),
                    style: TextStyle(
                      color: date != null ? textTitle : textSub,
                      fontSize: 13,
                      fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: textSub, size: 20),
              ],
            ),
          ),
        ),
      ],
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

  InputDecoration _inputDecoration(String hint, IconData? icon, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white30 : const Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: icon != null
          ? Icon(icon, color: const Color(0xFF059669), size: 18)
          : null,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.5)),
    );
  }
}