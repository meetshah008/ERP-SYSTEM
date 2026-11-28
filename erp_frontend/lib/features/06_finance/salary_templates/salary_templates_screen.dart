import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class SalaryTemplatesScreen extends StatefulWidget {
  const SalaryTemplatesScreen({super.key});

  @override
  State<SalaryTemplatesScreen> createState() => _SalaryTemplatesScreenState();
}

class _SalaryTemplatesScreenState extends State<SalaryTemplatesScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _templates = [];
  List<dynamic> _employees = [];
  List<dynamic> _categories = [];
  List<dynamic> _masterComponents = [];
  final Set<int> _selectedEmpIds = {};
  String _search = '';
  int? _categoryFilterId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0.0;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/payroll/templates')),
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/payroll/structures')),
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/hr/categories?status=ACTIVE')),
        ApiClient.get(Uri.parse('${ApiClient.apiHost}/api/payroll/components')),
      ]);
      final tBody = jsonDecode(res[0].body);
      final eBody = jsonDecode(res[1].body);
      final cBody = jsonDecode(res[2].body);
      if (res[0].statusCode == 200 && res[1].statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _templates = tBody['data'] ?? [];
          _masterComponents = (jsonDecode(res[3].body)['data'] as List?) ?? [];
          _employees = eBody['data'] ?? [];
          _categories = cBody['data'] ?? [];
          _loading = false;
        });
      } else {
        throw Exception(tBody['message'] ?? eBody['message'] ?? 'Failed to load templates');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _parseCustomAllowances(dynamic raw) {
    try {
      final list = raw is List ? raw : jsonDecode('${raw ?? '[]'}');
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  double _componentAmount(dynamic comp, double basic) {
    final mode = '${comp['calc_mode'] ?? 'FIXED'}';
    final val = _num(comp['value_override'] ?? comp['default_value']);
    if (mode == 'PERCENT_OF_BASIC') {
      return (basic * val) / 100.0;
    }
    return val;
  }

  Map<String, double> _calculateBreakup({
    required double gross,
    required double basicPct,
    required double hraPct,
    required double convFixed,
    required List<Map<String, dynamic>> customAllowances,
    required bool pf,
    required bool esi,
    required bool pt,
    List<dynamic> linkedComponents = const [],
  }) {
    final basic = (gross * basicPct) / 100.0;
    final hra = (basic * hraPct) / 100.0;
    final conv = convFixed.clamp(0.0, (gross - basic - hra).clamp(0.0, gross));
    final customSum = customAllowances.fold<double>(0, (s, c) => s + _num(c['amount']));

    const coreCodes = {'BASIC', 'HRA', 'CONV', 'SPECIAL', 'PF_EE', 'ESI_EE', 'PT'};
    double extraEarn = 0;
    double extraDed = 0;
    for (final comp in linkedComponents) {
      final code = '${comp['code'] ?? ''}'.toUpperCase();
      if (coreCodes.contains(code)) continue;
      final type = '${comp['component_type'] ?? ''}';
      final amt = _componentAmount(comp, basic);
      if (type == 'EARNING') {
        extraEarn += amt;
      } else if (type == 'DEDUCTION') {
        extraDed += amt;
      }
    }

    final special = (gross - basic - hra - conv - customSum - extraEarn).clamp(0.0, gross);
    final pfCut = pf ? (basic.clamp(0.0, 15000.0) * 0.12) : 0.0;
    final esiCut = (esi && gross <= 21000.0) ? (gross * 0.0075) : 0.0;
    final ptCut = pt ? (gross > 10000 ? 200.0 : (gross > 7500 ? 175.0 : 0.0)) : 0.0;
    final net = (gross - pfCut - esiCut - ptCut - extraDed).clamp(0.0, gross);
    return {
      'gross': gross,
      'basic': basic,
      'hra': hra,
      'conv': conv,
      'custom': customSum + extraEarn,
      'special': special,
      'pf': pfCut,
      'esi': esiCut,
      'pt': ptCut,
      'extraDed': extraDed,
      'net': net,
    };
  }

  Widget _previewBox(Map<String, double> b) {
    final extraDed = b['extraDed'] ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Salary Breakup Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E))),
          const SizedBox(height: 6),
          Text('Gross: ₹${b['gross']!.toStringAsFixed(0)}  ->  Basic: ₹${b['basic']!.toStringAsFixed(0)}  |  HRA: ₹${b['hra']!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
          Text('Conveyance: ₹${b['conv']!.toStringAsFixed(0)}  |  Custom/Linked: ₹${b['custom']!.toStringAsFixed(0)}  |  Special: ₹${b['special']!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
          Text(
            'PF: -₹${b['pf']!.toStringAsFixed(0)}  |  ESI: -₹${b['esi']!.toStringAsFixed(0)}  |  PT: -₹${b['pt']!.toStringAsFixed(0)}${extraDed > 0 ? '  |  Other Ded: -₹${extraDed.toStringAsFixed(0)}' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
          const Divider(height: 12),
          Text('Net In-Hand: ₹${b['net']!.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E))),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext ctx, TextEditingController ctrl) async {
    final init = DateTime.tryParse(ctrl.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: ctx,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      ctrl.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _showTemplateDialog({dynamic existing, bool isClone = false}) async {
    final nameCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (isClone ? '${existing['template_name']} (Copy)' : '${existing['template_name']}'),
    );
    final descCtrl = TextEditingController(text: '${existing?['description'] ?? ''}');
    final basicCtrl = TextEditingController(text: '${existing?['basic_percent'] ?? 50}');
    final hraCtrl = TextEditingController(text: '${existing?['hra_percent'] ?? 40}');
    final convCtrl = TextEditingController(text: '${existing?['conveyance_fixed'] ?? 1600}');
    final sampleGrossCtrl = TextEditingController(text: '35000');
    final customAllowances = _parseCustomAllowances(existing?['custom_allowances_json']);
    final customNameCtrl = TextEditingController();
    final customAmtCtrl = TextEditingController();

    String salaryType = existing?['salary_type'] ?? 'MONTHLY';
    bool saving = false;
    final selectedCompIds = <int>{
      for (final it in (existing?['items'] as List? ?? []))
        if (it['component_id'] != null) it['component_id'] as int,
    };
    if (selectedCompIds.isEmpty && existing != null) {
      for (final c in _masterComponents) {
        final code = '${c['code'] ?? ''}'.toUpperCase();
        if (code == 'BASIC' ||
            code == 'HRA' ||
            code == 'CONV' ||
            code == 'SPECIAL' ||
            (code == 'PF_EE' && existing['pf_applicable'] == 1) ||
            (code == 'ESI_EE' && existing['esi_applicable'] == 1) ||
            (code == 'PT' && existing['pt_applicable'] == 1)) {
          selectedCompIds.add(c['component_id'] as int);
        }
      }
    }

    final selectedCatIds = <int>{
      for (final cid in (existing?['category_ids'] as List? ?? []))
        if (cid != null) cid as int,
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final selectedComps = _masterComponents
              .where((c) => selectedCompIds.contains(c['component_id']))
              .toList();
          final hasPf = selectedComps.any((c) => '${c['code'] ?? ''}'.toUpperCase() == 'PF_EE');
          final hasEsi = selectedComps.any((c) => '${c['code'] ?? ''}'.toUpperCase() == 'ESI_EE');
          final hasPt = selectedComps.any((c) => '${c['code'] ?? ''}'.toUpperCase() == 'PT');

          final preview = _calculateBreakup(
            gross: _num(sampleGrossCtrl.text),
            basicPct: _num(basicCtrl.text),
            hraPct: _num(hraCtrl.text),
            convFixed: _num(convCtrl.text),
            customAllowances: customAllowances,
            pf: hasPf,
            esi: hasEsi,
            pt: hasPt,
            linkedComponents: selectedComps,
          );
          return AlertDialog(
            title: Text(existing == null || isClone ? 'Create Salary Template' : 'Edit Salary Template'),
            content: SizedBox(
              width: 470,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Template Name', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: salaryType,
                            decoration: const InputDecoration(labelText: 'Salary Type', border: OutlineInputBorder()),
                            items: const ['MONTHLY', 'DAILY', 'HOURLY'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (v) => setS(() => salaryType = v ?? 'MONTHLY'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: sampleGrossCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setS(() {}),
                            decoration: const InputDecoration(labelText: 'Test Gross (₹)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: basicCtrl, keyboardType: TextInputType.number, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'Basic %', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: hraCtrl, keyboardType: TextInputType.number, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'HRA % of Basic', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: convCtrl, keyboardType: TextInputType.number, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: 'Conveyance ₹', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(flex: 2, child: TextField(controller: customNameCtrl, decoration: const InputDecoration(labelText: 'Custom Allowance (e.g. Medical)', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: customAmtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount ₹', isDense: true, border: OutlineInputBorder()))),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.teal),
                          onPressed: () {
                            if (customNameCtrl.text.trim().isEmpty || _num(customAmtCtrl.text) <= 0) return;
                            setS(() {
                              customAllowances.add({'name': customNameCtrl.text.trim(), 'amount': _num(customAmtCtrl.text)});
                              customNameCtrl.clear();
                              customAmtCtrl.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    if (customAllowances.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: customAllowances.asMap().entries.map((entry) {
                          return Chip(
                            label: Text('${entry.value['name']}: ₹${_num(entry.value['amount']).toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                            onDeleted: () => setS(() => customAllowances.removeAt(entry.key)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),

                    if (_masterComponents.isNotEmpty) ...[
                      const Divider(height: 18),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Linked Salary Components', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _masterComponents.where((c) => c['is_active'] == 1).map((c) {
                          final cid = c['component_id'] as int;
                          final picked = selectedCompIds.contains(cid);
                          return FilterChip(
                            label: Text('${c['name']}', style: const TextStyle(fontSize: 11.5)),
                            selected: picked,
                            onSelected: (v) => setS(() {
                              if (v) {
                                selectedCompIds.add(cid);
                              } else {
                                selectedCompIds.remove(cid);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],

                    if (_categories.isNotEmpty) ...[
                      const Divider(height: 18),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Linked HR Categories (Default Template)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _categories.map((cat) {
                          final catId = cat['category_id'] as int;
                          final picked = selectedCatIds.contains(catId);
                          return FilterChip(
                            label: Text('${cat['category_name']}', style: const TextStyle(fontSize: 11.5)),
                            selected: picked,
                            onSelected: (v) => setS(() {
                              if (v) {
                                selectedCatIds.add(catId);
                              } else {
                                selectedCatIds.remove(catId);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],

                    _previewBox(preview),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    _msg('Template name is required.');
                    return;
                  }
                  setS(() => saving = true);
                  try {
                    final res = await ApiClient.post(
                      Uri.parse('${ApiClient.apiHost}/api/payroll/templates'),
                      body: jsonEncode({
                        if (existing != null && !isClone) 'template_id': existing['template_id'],
                        'template_name': nameCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'salary_type': salaryType,
                        'basic_percent': _num(basicCtrl.text),
                        'hra_percent': _num(hraCtrl.text),
                        'conveyance_fixed': _num(convCtrl.text),
                        'custom_allowances': customAllowances,
                        'pf_applicable': hasPf,
                        'esi_applicable': hasEsi,
                        'pt_applicable': hasPt,
                        'ot_eligible': true,
                        'items': selectedCompIds.map((cid) {
                          final comp = _masterComponents.firstWhere((c) => c['component_id'] == cid);
                          return {
                            'component_id': cid,
                            'calc_mode': comp['calc_mode'] ?? 'FIXED',
                            'value_override': _num(comp['default_value']),
                          };
                        }).toList(),
                        'category_ids': selectedCatIds.toList(),
                      }),
                    );
                    final body = jsonDecode(res.body);
                    if ((res.statusCode == 200 || res.statusCode == 201) && body['success'] == true) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _msg(body['message'] ?? 'Template saved!');
                      await _loadData();
                    } else {
                      throw Exception(body['message'] ?? 'Failed to save template');
                    }
                  } catch (e) {
                    setS(() => saving = false);
                    _msg(e.toString());
                  }
                },
                child: Text(saving ? 'Saving...' : 'Save Template'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteTemplate(dynamic tpl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template?'),
        content: Text('Remove "${tpl['template_name']}" from active templates?'),
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
    if (ok != true) return;
    final res = await ApiClient.delete(Uri.parse('${ApiClient.apiHost}/api/payroll/templates/${tpl['template_id']}'));
    if (res.statusCode == 200) {
      _msg('Template removed.');
      await _loadData();
    }
  }

  Future<void> _applyTemplate(dynamic emp, int templateId) async {
    final tpl = _templates.firstWhere((t) => t['template_id'] == templateId, orElse: () => null);
    if (tpl == null) return;
    final grossCtrl = TextEditingController(
      text: _num(emp['gross_monthly'] ?? emp['salary_base'] ?? 20000).toStringAsFixed(0),
    );
    final now = DateTime.now();
    final effCtrl = TextEditingController(
      text: '${now.year}-${String.fromCharCode(48)}${now.month}'.replaceFirst('0${now.month}', now.month.toString().padLeft(2, '0')) + '-01',
    );
    final customAllowances = _parseCustomAllowances(tpl['custom_allowances_json']);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final preview = _calculateBreakup(
            gross: _num(grossCtrl.text),
            basicPct: _num(tpl['basic_percent']),
            hraPct: _num(tpl['hra_percent']),
            convFixed: _num(tpl['conveyance_fixed']),
            customAllowances: customAllowances,
            pf: false,
            esi: false,
            pt: false,
          );
          return AlertDialog(
            title: Text('Confirm Template: "${tpl['template_name']}"'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Employee: ${emp['full_name']} (${emp['emp_code']})', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: grossCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setS(() {}),
                          decoration: const InputDecoration(labelText: 'Monthly Gross (₹)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: effCtrl,
                          readOnly: true,
                          onTap: () => _pickDate(ctx, effCtrl),
                          decoration: const InputDecoration(
                            labelText: 'Effective From',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _previewBox(preview),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final res = await ApiClient.post(
                    Uri.parse('${ApiClient.apiHost}/api/payroll/templates/apply'),
                    body: jsonEncode({
                      'employee_id': emp['employee_id'],
                      'template_id': templateId,
                      'gross_monthly': _num(grossCtrl.text),
                      'effective_from': effCtrl.text.trim(),
                    }),
                  );
                  final body = jsonDecode(res.body);
                  if (res.statusCode == 200 && body['success'] == true) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _msg(body['message'] ?? 'Template applied!');
                    await _loadData();
                  } else {
                    _msg(body['message'] ?? 'Failed to apply');
                  }
                },
                child: const Text('Confirm & Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEmployeeBreakup(dynamic emp) async {
    final tpl = _templates.firstWhere((t) => t['template_id'] == emp['template_id'], orElse: () => null);
    final gross = _num(emp['gross_monthly'] ?? emp['salary_base']);
    final tplItems = (tpl?['items'] as List?) ?? [];
    final b = _calculateBreakup(
      gross: gross,
      basicPct: _num(tpl?['basic_percent'] ?? 50),
      hraPct: _num(tpl?['hra_percent'] ?? 40),
      convFixed: _num(tpl?['conveyance_fixed'] ?? 1600),
      customAllowances: _parseCustomAllowances(tpl?['custom_allowances_json']),
      pf: emp['pf_applicable'] == 1 || tpl?['pf_applicable'] == 1,
      esi: emp['esi_applicable'] == 1 || tpl?['esi_applicable'] == 1,
      pt: emp['pt_applicable'] == 1 || tpl?['pt_applicable'] == 1,
      linkedComponents: tplItems,
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Salary Breakup — ${emp['full_name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Template: ${emp['template_name'] ?? 'Custom'} • Effective: ${emp['effective_from'] ?? '-'}'),
              const SizedBox(height: 12),
              _previewBox(b),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showEmployeeHistory(dynamic emp) async {
    final res = await ApiClient.get(
      Uri.parse('${ApiClient.apiHost}/api/payroll/structures/${emp['employee_id']}/history'),
    );
    final body = jsonDecode(res.body);
    final history = (body['data'] as List?) ?? [];
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Template History — ${emp['full_name']}'),
        content: SizedBox(
          width: 460,
          height: 360,
          child: history.isEmpty
              ? const Center(child: Text('No salary history recorded yet.'))
              : ListView.builder(
            itemCount: history.length,
            itemBuilder: (_, i) {
              final h = history[i];
              final isCurrent = h['is_current'] == 1;
              return Card(
                child: ListTile(
                  title: Text(
                    '${h['template_name'] ?? 'Custom'} — ₹${_num(h['gross_monthly']).toStringAsFixed(0)} ${isCurrent ? '(Current)' : ''}',
                    style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal),
                  ),
                  subtitle: Text(
                    'Effective: ${h['effective_from']} to ${h['effective_to'] ?? 'Present'}\nChanged by ${h['changed_by_name']} on ${h['changed_at']}',
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showBulkApplyDialog() async {
    if (_templates.isEmpty) return;
    int selectedTplId = _templates.first['template_id'];
    int? selectedCategoryId;
    final grossCtrl = TextEditingController();
    final now = DateTime.now();
    final effCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Bulk Apply Salary Template'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedEmpIds.isNotEmpty
                      ? 'Applying to ${_selectedEmpIds.length} selected employees'
                      : 'Select an HR Category to apply to all its active staff',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('bulk_tpl_$selectedTplId'),
                  initialValue: selectedTplId,
                  decoration: const InputDecoration(labelText: 'Salary Template', border: OutlineInputBorder()),
                  items: _templates.map<DropdownMenuItem<int>>((t) => DropdownMenuItem(value: t['template_id'], child: Text('${t['template_name']}'))).toList(),
                  onChanged: (v) => setS(() => selectedTplId = v!),
                ),
                if (_selectedEmpIds.isEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'HR Category', border: OutlineInputBorder()),
                    items: _categories
                        .map<DropdownMenuItem<int?>>(
                          (c) => DropdownMenuItem(
                            value: c['category_id'] as int,
                            child: Text('${c['category_name']} (${c['employee_count'] ?? 0} staff)'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setS(() {
                        selectedCategoryId = v;
                        final cat = _categories.firstWhere((c) => c['category_id'] == v, orElse: () => null);
                        if (cat != null && cat['default_template_id'] != null) {
                          final defTplId = cat['default_template_id'] as int;
                          if (_templates.any((t) => t['template_id'] == defTplId)) {
                            selectedTplId = defTplId;
                          }
                        }
                        if (cat != null && grossCtrl.text.trim().isEmpty && _num(cat['default_gross']) > 0) {
                          grossCtrl.text = _num(cat['default_gross']).toStringAsFixed(0);
                        }
                      });
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: effCtrl,
                  readOnly: true,
                  onTap: () => _pickDate(ctx, effCtrl),
                  decoration: const InputDecoration(labelText: 'Effective From', suffixIcon: Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: grossCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Override Gross ₹ (leave empty to keep existing)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final res = await ApiClient.post(
                  Uri.parse('${ApiClient.apiHost}/api/payroll/templates/bulk-apply'),
                  body: jsonEncode({
                    'template_id': selectedTplId,
                    if (_selectedEmpIds.isNotEmpty) 'employee_ids': _selectedEmpIds.toList(),
                    if (_selectedEmpIds.isEmpty && selectedCategoryId != null) 'category_id': selectedCategoryId,
                    if (_num(grossCtrl.text) > 0) 'gross_monthly': _num(grossCtrl.text),
                    'effective_from': effCtrl.text.trim(),
                  }),
                );
                final body = jsonDecode(res.body);
                if (res.statusCode == 200 && body['success'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() => _selectedEmpIds.clear());
                  _msg(body['message'] ?? 'Bulk applied!');
                  await _loadData();
                } else {
                  _msg(body['message'] ?? 'Bulk apply failed');
                }
              },
              child: const Text('Confirm & Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _employees.where((e) {
      if (_categoryFilterId != null && e['hr_category_id'] != _categoryFilterId) {
        return false;
      }
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return '${e['full_name']} ${e['emp_code']} ${e['department_name'] ?? ''} ${e['hr_category_name'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        title: const Text('Salary Templates (HR & Accounts)', style: TextStyle(fontWeight: FontWeight.w700)),
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
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                const Text(
                  'Company Salary Templates',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF03C3BD),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _showBulkApplyDialog,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: Text(_selectedEmpIds.isEmpty ? 'Bulk / Category Apply' : 'Apply to (${_selectedEmpIds.length})'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final cols = maxW >= 1100 ? 4 : (maxW >= 720 ? 2 : 1);
                const gap = 14.0;
                final cardWidth = (maxW - (gap * (cols - 1))) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    ..._templates.map((t) => _buildTemplateCard(t, width: cardWidth)),
                    _buildCreateTemplateCard(width: cardWidth),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                const Text('Employee Salary Templates (Preview, Switch & History)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 36,
                      child: DropdownButtonFormField<int?>(
                        initialValue: _categoryFilterId,
                        isDense: true,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('All HR Categories', style: TextStyle(fontSize: 12.5))),
                          ..._categories.map<DropdownMenuItem<int?>>(
                            (c) => DropdownMenuItem<int?>(
                              value: c['category_id'] as int,
                              child: Text('${c['category_name']}', style: const TextStyle(fontSize: 12.5)),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _categoryFilterId = v),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      height: 36,
                      child: TextField(
                    style: const TextStyle(fontSize: 13),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Search employee by name, ID...',
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF0F766E)),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...filtered.map((emp) => _buildEmployeeRow(emp)),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(dynamic t, {double width = 310}) {
    final custom = _parseCustomAllowances(t['custom_allowances_json']);
    final empCount = t['employees_count'] ?? 0;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SizedBox(
      width: width,
      height: isMobile ? null : 325,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t['template_name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0F172A)),
                  ),
                ),
                InkWell(
                  onTap: () => _showTemplateDialog(existing: t),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined, size: 17, color: Color(0xFF64748B)),
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF64748B)),
                  onSelected: (val) {
                    if (val == 'clone') _showTemplateDialog(existing: t, isClone: true);
                    if (val == 'delete') _deleteTemplate(t);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'clone', child: Text('Clone Template')),
                    PopupMenuItem(value: 'delete', child: Text('Delete Template', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${t['description'] ?? 'Standard company salary breakup'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _ruleRow('Basic Allowance:', '${_num(t['basic_percent']).toStringAsFixed(0)}% of Gross'),
            _ruleRow('HRA:', '${_num(t['hra_percent']).toStringAsFixed(0)}% of Basic'),
            _ruleRow('Conveyance:', '₹${_num(t['conveyance_fixed']).toStringAsFixed(0)} / mo'),
            _ruleRow(
              custom.isNotEmpty ? '${custom.first['name']}:' : 'Special Allowance:',
              custom.isNotEmpty ? '₹${_num(custom.first['amount']).toStringAsFixed(0)} / mo' : 'Remaining Balance',
            ),
            if (isMobile) const SizedBox(height: 10) else const Spacer(),
            const Divider(height: 18, color: Color(0xFFF1F5F9)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$empCount Staff Assigned', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                InkWell(
                  onTap: () => _showRulePreviewDialog(t),
                  child: const Text(
                    'Preview Rule',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Future<void> _showRulePreviewDialog(dynamic t) async {
    final grossCtrl = TextEditingController(text: '35000');
    final custom = _parseCustomAllowances(t['custom_allowances_json']);
    final items = (t['items'] as List?) ?? [];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final b = _calculateBreakup(
            gross: _num(grossCtrl.text),
            basicPct: _num(t['basic_percent']),
            hraPct: _num(t['hra_percent']),
            convFixed: _num(t['conveyance_fixed']),
            customAllowances: custom,
            pf: t['pf_applicable'] == 1,
            esi: t['esi_applicable'] == 1,
            pt: t['pt_applicable'] == 1,
            linkedComponents: items,
          );
          return AlertDialog(
            title: Text('Preview: ${t['template_name']}'),
            content: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: grossCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setS(() {}),
                    decoration: const InputDecoration(labelText: 'Sample Gross Salary (₹)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  _previewBox(b),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'EM';
    if (parts.length == 1) return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildEmployeeRow(dynamic emp) {
    final empId = emp['employee_id'] as int;
    final currentTplId = emp['template_id'] as int?;
    final fullName = '${emp['full_name'] ?? ''}';
    final empCode = '${emp['emp_code'] ?? ''}';
    final catName = '${emp['hr_category_name'] ?? ''}';
    final baseSub = '${emp['designation'] ?? emp['department_name'] ?? 'Staff'}';
    final subTitle = catName.isNotEmpty ? '$baseSub • $catName' : baseSub;
    final gross = _num(emp['gross_monthly'] ?? emp['salary_base']);
    final tplName = emp['template_name'];
    final hasTpl = tplName != null && '$tplName'.isNotEmpty;

    final avatarColors = [
      const Color(0xFF4F46E5),
      const Color(0xFF0D9488),
      const Color(0xFF7C3AED),
      const Color(0xFF0284C7),
      const Color(0xFF059669),
    ];
    final avatarColor = avatarColors[empId % avatarColors.length];
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Checkbox + Avatar + Name/ID + Designation
            Row(
              children: [
                Checkbox(
                  value: _selectedEmpIds.contains(empId),
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedEmpIds.add(empId);
                    } else {
                      _selectedEmpIds.remove(empId);
                    }
                  }),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: avatarColor.withValues(alpha: 0.12),
                  child: Text(
                    _initials(fullName),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: avatarColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              'ID: $empCode',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: Color(0xFFF1F5F9)),

            // Row 2: Monthly Gross + Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monthly Gross', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    const SizedBox(height: 2),
                    Text(
                      '₹${gross.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasTpl ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: hasTpl ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: hasTpl ? const Color(0xFF10B981) : const Color(0xFFD97706),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasTpl ? '$tplName' : 'Custom / Not assigned',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasTpl ? const Color(0xFF047857) : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 3: Template Dropdown + View Breakup + History
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('m_tpl_${empId}_$currentTplId'),
                      initialValue: _templates.any((t) => t['template_id'] == currentTplId) ? currentTplId : null,
                      hint: const Text('Select Template', style: TextStyle(fontSize: 12.5)),
                      isDense: true,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      items: _templates
                          .map<DropdownMenuItem<int>>(
                            (t) => DropdownMenuItem(value: t['template_id'], child: Text('${t['template_name']}', style: const TextStyle(fontSize: 12.5))),
                      )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) _applyTemplate(emp, val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'View Breakup',
                  icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => _showEmployeeBreakup(emp),
                ),
                IconButton(
                  tooltip: 'Template History',
                  icon: const Icon(Icons.history, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => _showEmployeeHistory(emp),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 💻 DESKTOP VIEW (existing return Container(...) waisa hi rahega)

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _selectedEmpIds.contains(empId),
            visualDensity: VisualDensity.compact,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedEmpIds.add(empId);
              } else {
                _selectedEmpIds.remove(empId);
              }
            }),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: avatarColor.withValues(alpha: 0.12),
            child: Text(
              _initials(fullName),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: avatarColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text('ID: $empCode', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monthly Gross', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    const SizedBox(height: 2),
                    Text('₹${gross.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF0F172A))),
                  ],
                ),
                Container(
                  height: 28,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: const Color(0xFFE2E8F0),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Status', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasTpl ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: hasTpl ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: hasTpl ? const Color(0xFF10B981) : const Color(0xFFD97706),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasTpl ? '$tplName' : 'Custom / Not assigned',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasTpl ? const Color(0xFF047857) : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 185,
            height: 36,
            child: DropdownButtonFormField<int>(
              key: ValueKey('d_tpl_${empId}_$currentTplId'),
              initialValue: _templates.any((t) => t['template_id'] == currentTplId) ? currentTplId : null,
              hint: const Text('Select Template', style: TextStyle(fontSize: 12.5)),
              isDense: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
              items: _templates
                  .map<DropdownMenuItem<int>>(
                    (t) => DropdownMenuItem(value: t['template_id'], child: Text('${t['template_name']}', style: const TextStyle(fontSize: 12.5))),
              )
                  .toList(),
              onChanged: (val) {
                if (val != null) _applyTemplate(emp, val);
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'View Breakup',
            icon: const Icon(Icons.visibility_outlined, size: 19, color: Color(0xFF64748B)),
            onPressed: () => _showEmployeeBreakup(emp),
          ),
          IconButton(
            tooltip: 'Template History',
            icon: const Icon(Icons.history, size: 19, color: Color(0xFF64748B)),
            onPressed: () => _showEmployeeHistory(emp),
          ),
        ],
      ),
    );
  }
  Widget _buildCreateTemplateCard({double width = 310}) {
    return SizedBox(
      width: width,
      height: 325,
      child: InkWell(
        onTap: () => _showTemplateDialog(),
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: const Color(0xFFCBD5E1),
            radius: 14,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.add, size: 22, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Create Custom Tier',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Add customized compensation\nmatrix for specialized roles',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}