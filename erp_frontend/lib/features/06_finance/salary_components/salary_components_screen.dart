import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class SalaryComponentsScreen extends StatefulWidget {
  const SalaryComponentsScreen({super.key});

  @override
  State<SalaryComponentsScreen> createState() => _SalaryComponentsScreenState();
}

class _SalaryComponentsScreenState extends State<SalaryComponentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<dynamic> _components = [];


  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadComponents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0.0;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadComponents() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiClient.apiHost}/api/payroll/components'),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (!mounted) return;
        setState(() {
          _components = body['data'] ?? [];
          _loading = false;
        });
      } else {
        throw Exception(body['message'] ?? 'Failed to load components');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showComponentDialog({dynamic existing, String? initialType}) async {
    final nameCtrl = TextEditingController(text: '${existing?['name'] ?? ''}');
    final codeCtrl = TextEditingController(text: '${existing?['code'] ?? ''}');
    final valCtrl = TextEditingController(text: '${existing?['default_value'] ?? 0}');
    String compType = existing?['component_type'] ?? initialType ?? 'EARNING';
    String calcMode = existing?['calc_mode'] ?? 'FIXED';
    bool isTaxable = (existing?['is_taxable'] ?? 1) == 1;
    bool isActive = (existing?['is_active'] ?? 1) == 1;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Add Salary Component' : 'Edit Salary Component'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Component Name (e.g. Basic Salary)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    enabled: existing == null,
                    decoration: const InputDecoration(
                      labelText: 'Component Code (e.g. BASIC)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Component Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  RadioGroup<String>(
                    groupValue: compType,
                    onChanged: (v) {
                      if (v != null) setS(() => compType = v);
                    },
                    child: const Column(
                      children: [
                        RadioListTile<String>(
                          dense: true,
                          value: 'EARNING',
                          title: Text('Earning — Added to salary'),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          value: 'DEDUCTION',
                          title: Text('Deduction — Deducted from salary'),
                        ),

                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: calcMode,
                    decoration: const InputDecoration(
                      labelText: 'Calculation Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'FIXED', child: Text('Fixed Amount (₹)')),
                      DropdownMenuItem(value: 'PERCENT_OF_BASIC', child: Text('Percentage of Basic (%)')),
                    ],
                    onChanged: (v) => setS(() => calcMode = v ?? 'FIXED'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: calcMode == 'FIXED' ? 'Default Amount (₹)' : 'Default Percentage (%)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    dense: true,
                    title: const Text('Taxable Component'),
                    value: isTaxable,
                    onChanged: (v) => setS(() => isTaxable = v ?? true),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Active'),
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
                final cleanName = nameCtrl.text.trim();
                final cleanCode = codeCtrl.text.trim().toUpperCase();
                final parsedVal = double.tryParse(valCtrl.text.trim());
                if (cleanName.isEmpty) {
                  _msg('Component Name is required.');
                  return;
                }
                if (cleanCode.isEmpty) {
                  _msg('Component Code is required.');
                  return;
                }
                if (parsedVal == null || parsedVal < 0) {
                  _msg('Amount / Percentage cannot be negative.');
                  return;
                }
                setS(() => saving = true);
                try {
                  final res = await ApiClient.post(
                    Uri.parse('${ApiClient.apiHost}/api/payroll/components'),
                    body: jsonEncode({
                      if (existing != null) 'component_id': existing['component_id'],
                      'name': cleanName,
                      'code': cleanCode,
                      'component_type': compType,
                      'calc_mode': calcMode,
                      'default_value': parsedVal,
                      'is_taxable': isTaxable,
                      'is_active': isActive,
                    }),
                  );
                  final body = jsonDecode(res.body);
                  if ((res.statusCode == 200 || res.statusCode == 201) && body['success'] == true) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _msg(body['message'] ?? 'Component saved!');
                    await _loadComponents();
                  } else {
                    throw Exception(body['message'] ?? 'Failed to save component');
                  }
                } catch (e) {
                  setS(() => saving = false);
                  _msg(e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: Text(saving ? 'Saving...' : 'Save Component'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComponent(dynamic c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove / Deactivate Component?'),
        content: Text('Do you want to remove "${c['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await ApiClient.delete(
        Uri.parse('${ApiClient.apiHost}/api/payroll/components/${c['component_id']}'),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _msg(body['message'] ?? 'Component updated.');
        await _loadComponents();
      } else {
        throw Exception(body['message'] ?? 'Failed to delete component');
      }
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final earnings = _components.where((c) => c['component_type'] == 'EARNING').toList();
    final deductions = _components.where((c) => c['component_type'] != 'EARNING').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        title: const Text('Salary Components', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<String>(
              onSelected: (type) => _showComponentDialog(initialType: type),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'EARNING', child: Text('Earning')),
                PopupMenuItem(value: 'DEDUCTION', child: Text('Deduction')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Add Component', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF0F766E),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF0F766E),
          tabs: [
            Tab(text: 'Earnings (${earnings.length})'),
            Tab(text: 'Benefits & Deductions (${deductions.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadComponents, child: const Text('Retry')),
          ],
        ),
      )
          : TabBarView(
        controller: _tabs,
        children: [
          _buildTable(earnings),
          _buildTable(deductions),
        ],
      ),
    );
  }

  Widget _buildTable(List<dynamic> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No salary components found.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                    Expanded(flex: 3, child: Text('COMPONENT NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    Expanded(flex: 2, child: Text('TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    Expanded(flex: 2, child: Text('CALCULATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    Expanded(flex: 2, child: Text('AMOUNT / %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    Expanded(flex: 1, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    SizedBox(width: 104, child: Text('ACTION', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                  ],
                ),
              ),
              ...list.map((c) {
                final isFixed = c['calc_mode'] == 'FIXED';
                final valText = isFixed
                    ? '₹${_num(c['default_value']).toStringAsFixed(0)}'
                    : '${_num(c['default_value']).toStringAsFixed(1)}%';
                final active = c['is_active'] == 1;
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
                            Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
                            Text('${c['code']}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      Expanded(flex: 2, child: Text('${c['component_type']}', style: const TextStyle(fontSize: 12.5))),
                      Expanded(
                        flex: 2,
                        child: Text(isFixed ? 'Fixed Amount' : '% of Basic', style: const TextStyle(fontSize: 12.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(valText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          active ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.green.shade700 : Colors.grey,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 104,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _showComponentDialog(existing: c),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () => _deleteComponent(c),
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
    );
  }
}