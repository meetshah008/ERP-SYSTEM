import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';

class HrCategoryMasterScreen extends StatefulWidget {
  const HrCategoryMasterScreen({super.key});

  @override
  State<HrCategoryMasterScreen> createState() => _HrCategoryMasterScreenState();
}

class _HrCategoryMasterScreenState extends State<HrCategoryMasterScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _categories = [];
  String _search = '';
  String _statusFilter = 'ALL'; // ALL, ACTIVE, INACTIVE
  List<dynamic> _templates = [];
  List<dynamic> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _msg(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF0F766E),
      ),
    );
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/hr/categories')),
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/payroll/templates')),
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/hr/employees')),
      ]);
      final body = jsonDecode(results[0].body);
      final tplBody = results[1].statusCode == 200 ? jsonDecode(results[1].body) : null;
      final empBody = results[2].statusCode == 200 ? jsonDecode(results[2].body) : null;
      if (results[0].statusCode == 200 && body['success'] == true) {
        if (!mounted) return;
        setState(() {
          _categories = body['data'] ?? [];
          _templates = (tplBody is Map ? tplBody['data'] : null) ?? [];
          final rawEmps = (empBody is Map ? (empBody['employees'] ?? empBody['data']) : null) ?? [];
          _employees = (rawEmps as List)
              .where((e) => '${e['status'] ?? 'active'}'.toLowerCase() == 'active')
              .toList();
          _loading = false;
        });
      } else {
        throw Exception(body['message'] ?? 'Failed to load HR categories');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _showAssignMembersDialog({dynamic initialCategory}) async {
    final activeCats = _categories.where((c) => (c['is_active'] ?? 1) == 1).toList();
    final catChoices = activeCats.isNotEmpty ? activeCats : _categories;
    if (catChoices.isEmpty) {
      _msg('Create an HR Category first.', isError: true);
      return;
    }

    int selectedCatId = (initialCategory?['category_id'] ?? catChoices.first['category_id']) as int;
    Set<int> selectedEmpIdsForCat(int catId) => {
          for (final e in _employees)
            if (e['hr_category_id'] == catId && e['employee_id'] != null) e['employee_id'] as int,
        };

    Set<int> pickedEmpIds = selectedEmpIdsForCat(selectedCatId);
    String memberSearch = '';
    bool saving = false;

    final catNameById = {
      for (final c in _categories) c['category_id']: '${c['category_name'] ?? ''}',
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = memberSearch.trim().toLowerCase();
          final filteredEmps = _employees.where((e) {
            if (q.isEmpty) return true;
            final name = '${e['full_name'] ?? ''}'.toLowerCase();
            final code = '${e['emp_code'] ?? ''}'.toLowerCase();
            final desig = '${e['designation'] ?? ''}'.toLowerCase();
            return name.contains(q) || code.contains(q) || desig.contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Assign Members to HR Category'),
            content: SizedBox(
              width: 480,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: catChoices.any((c) => c['category_id'] == selectedCatId)
                        ? selectedCatId
                        : catChoices.first['category_id'] as int,
                    decoration: const InputDecoration(
                      labelText: 'Select HR Category',
                      border: OutlineInputBorder(),
                    ),
                    items: catChoices
                        .map<DropdownMenuItem<int>>(
                          (c) => DropdownMenuItem(
                            value: c['category_id'] as int,
                            child: Text('${c['category_name']} (${c['category_code']})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setS(() {
                        selectedCatId = v;
                        pickedEmpIds = selectedEmpIdsForCat(v);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search employee by name, code, or designation...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setS(() => memberSearch = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${pickedEmpIds.length} member(s) selected',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: filteredEmps.isEmpty
                        ? const Center(child: Text('No active employees found.'))
                        : ListView.builder(
                            itemCount: filteredEmps.length,
                            itemBuilder: (_, i) {
                              final e = filteredEmps[i];
                              final eid = e['employee_id'] as int;
                              final checked = pickedEmpIds.contains(eid);
                              final curCatId = e['hr_category_id'];
                              final otherCatName = (curCatId != null && curCatId != selectedCatId)
                                  ? catNameById[curCatId]
                                  : null;
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                activeColor: const Color(0xFF0F766E),
                                title: Text(
                                  '${e['full_name'] ?? ''} (${e['emp_code'] ?? ''})',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  otherCatName != null
                                      ? '${e['designation'] ?? '-'} • Currently: $otherCatName'
                                      : '${e['designation'] ?? '-'}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: otherCatName != null ? Colors.orange.shade800 : const Color(0xFF64748B),
                                  ),
                                ),
                                onChanged: (v) => setS(() {
                                  if (v == true) {
                                    pickedEmpIds.add(eid);
                                  } else {
                                    pickedEmpIds.remove(eid);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                ),
                onPressed: saving
                    ? null
                    : () async {
                        setS(() => saving = true);
                        try {
                          final res = await ApiClient.post(
                            Uri.parse('${ApiClient.apiHost}/api/hr/categories/$selectedCatId/assign-members'),
                            body: jsonEncode({'employee_ids': pickedEmpIds.toList()}),
                          );
                          final body = jsonDecode(res.body);
                          if (res.statusCode == 200 && body['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _msg(body['message'] ?? 'Members assigned!');
                            await _loadCategories();
                          } else {
                            setS(() => saving = false);
                            _msg(body['message'] ?? 'Failed to assign members.', isError: true);
                          }
                        } catch (e) {
                          setS(() => saving = false);
                          _msg('Error: $e', isError: true);
                        }
                      },
                child: Text(saving ? 'Saving...' : 'Save Members'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCategoryDialog({dynamic existing}) async {
    final nameCtrl = TextEditingController(text: '${existing?['category_name'] ?? ''}');
    final codeCtrl = TextEditingController(text: '${existing?['category_code'] ?? ''}');
    final descCtrl = TextEditingController(text: '${existing?['description'] ?? ''}');
    final grossCtrl = TextEditingController(
      text: existing?['default_gross'] != null ? '${existing['default_gross']}' : '',
    );
    int? selectedTemplateId = existing?['default_template_id'] as int?;
    bool isActive = (existing?['is_active'] ?? 1) == 1;
    bool saving = false;
    String? formError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Add HR Category' : 'Edit HR Category'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (formError != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(formError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12.5)),
                    ),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Category Name * (e.g. Junior Developer)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Category Code * (e.g. CAT-JD)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _templates.any((t) => t['template_id'] == selectedTemplateId)
                        ? selectedTemplateId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Default Salary Template (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('None')),
                      ..._templates.map<DropdownMenuItem<int?>>(
                        (t) => DropdownMenuItem<int?>(
                          value: t['template_id'] as int,
                          child: Text('${t['template_name']}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setS(() => selectedTemplateId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: grossCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Default Monthly Gross ₹ (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active Status'),
                    subtitle: Text(isActive ? 'Active (available for assignment)' : 'Inactive'),
                    value: isActive,
                    onChanged: (v) => setS(() => isActive = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              onPressed: saving
                  ? null
                  : () async {
                final name = nameCtrl.text.trim();
                final code = codeCtrl.text.trim().toUpperCase();
                if (name.isEmpty) {
                  setS(() => formError = 'Category Name is required.');
                  return;
                }
                if (code.isEmpty) {
                  setS(() => formError = 'Category Code is required.');
                  return;
                }
                setS(() {
                  saving = true;
                  formError = null;
                });
                try {
                  final payload = jsonEncode({
                    'category_name': name,
                    'category_code': code,
                    'description': descCtrl.text.trim(),
                    'default_template_id': selectedTemplateId,
                    'default_gross': double.tryParse(grossCtrl.text.trim()),
                    'is_active': isActive,
                  });
                  final res = existing == null
                      ? await ApiClient.post(
                    Uri.parse('${ApiClient.apiHost}/api/hr/categories'),
                    body: payload,
                  )
                      : await ApiClient.put(
                    Uri.parse('${ApiClient.apiHost}/api/hr/categories/${existing['category_id']}'),
                    body: payload,
                  );
                  final body = jsonDecode(res.body);
                  if ((res.statusCode == 200 || res.statusCode == 201) && body['success'] == true) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _msg(body['message'] ?? 'Category saved!');
                    await _loadCategories();
                  } else {
                    setS(() {
                      saving = false;
                      formError = body['message'] ?? 'Failed to save category.';
                    });
                  }
                } catch (e) {
                  setS(() {
                    saving = false;
                    formError = e.toString().replaceFirst('Exception: ', '');
                  });
                }
              },
              child: Text(saving ? 'Saving...' : 'Save Category'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(dynamic cat) async {
    final empCount = int.tryParse('${cat['employee_count'] ?? 0}') ?? 0;
    if (empCount > 0) {
      final deactivate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Permanently Delete'),
          content: Text(
            '"${cat['category_name']}" currently has $empCount assigned employee(s). Permanent deletion is blocked.\n\nWould you like to deactivate this category instead?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deactivate Instead'),
            ),
          ],
        ),
      );
      if (deactivate != true) return;
      final res = await ApiClient.delete(
        Uri.parse('${ApiClient.apiHost}/api/hr/categories/${cat['category_id']}?deactivate=true'),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _msg(body['message'] ?? 'Category deactivated.');
        await _loadCategories();
      } else {
        _msg(body['message'] ?? 'Failed to deactivate.', isError: true);
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete HR Category?'),
        content: Text('Are you sure you want to permanently delete "${cat['category_name']}" (${cat['category_code']})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final res = await ApiClient.delete(
      Uri.parse('${ApiClient.apiHost}/api/hr/categories/${cat['category_id']}'),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['success'] == true) {
      _msg(body['message'] ?? 'Category deleted.');
      await _loadCategories();
    } else {
      _msg(body['message'] ?? 'Could not delete category.', isError: true);
    }
  }

  List<dynamic> get _filtered {
    final q = _search.trim().toLowerCase();
    return _categories.where((c) {
      final active = (c['is_active'] ?? 1) == 1;
      if (_statusFilter == 'ACTIVE' && !active) return false;
      if (_statusFilter == 'INACTIVE' && active) return false;
      if (q.isEmpty) return true;
      return '${c['category_name']} ${c['category_code']}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        title: const Text('HR Category Master', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F766E),
                side: const BorderSide(color: Color(0xFF0F766E)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showAssignMembersDialog(),
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Assign Members'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showCategoryDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Category'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _loadCategories, child: const Text('Retry')),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadCategories,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _statusFilter == 'ALL',
                      onSelected: (_) => setState(() => _statusFilter = 'ALL'),
                    ),
                    ChoiceChip(
                      label: const Text('Active'),
                      selected: _statusFilter == 'ACTIVE',
                      onSelected: (_) => setState(() => _statusFilter = 'ACTIVE'),
                    ),
                    ChoiceChip(
                      label: const Text('Inactive'),
                      selected: _statusFilter == 'INACTIVE',
                      onSelected: (_) => setState(() => _statusFilter = 'INACTIVE'),
                    ),
                  ],
                ),
                SizedBox(
                  width: 300,
                  height: 36,
                  child: TextField(
                    style: const TextStyle(fontSize: 13),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Search by name or code...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 17, color: Color(0xFF94A3B8)),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (list.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Center(
                  child: Text('No HR categories found.', style: TextStyle(color: Color(0xFF64748B))),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('CATEGORY NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                          Expanded(flex: 2, child: Text('CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                          Expanded(flex: 3, child: Text('DESCRIPTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                          Expanded(flex: 2, child: Text('EMPLOYEES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                          Expanded(flex: 2, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                          SizedBox(width: 108, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                        ],
                      ),
                    ),
                    ...list.map((c) {
                      final active = (c['is_active'] ?? 1) == 1;
                      final empCount = c['employee_count'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c['category_name']}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                  if (c['default_template_name'] != null)
                                    Text(
                                      'Template: ${c['default_template_name']}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF0F766E)),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('${c['category_code']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text('${c['description'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('$empCount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: active ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  active ? 'Active' : 'Inactive',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: active ? const Color(0xFF047857) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 108,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message: 'Assign Members',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _showAssignMembersDialog(initialCategory: c),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.group_add_outlined, size: 18, color: Color(0xFF0F766E)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: 'Edit',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _showCategoryDialog(existing: c),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.edit_outlined, size: 18),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: 'Delete',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _deleteCategory(c),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}