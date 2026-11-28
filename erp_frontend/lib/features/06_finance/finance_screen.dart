import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/session_manager.dart';
import 'bank_expenses/quick_bank_expense_tab.dart';

/// Accounts & Finance workspace.
///
/// Backend: /api/finance/* (see erp_backend/src/modules/04_finance).
/// Every action is gated by the same permission keys the backend checks.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Map<String, dynamic> _dashboard = {};
  List<dynamic> _accounts = [];
  List<dynamic> _years = [];
  List<dynamic> _vouchers = [];
  List<dynamic> _ledger = [];
  Map<String, dynamic> _ledgerAccount = {};
  List<dynamic> _trialBalance = [];
  Map<String, dynamic> _trialTotals = {};
  Map<String, dynamic> _profitLoss = {};
  Map<String, dynamic> _balanceSheet = {};
  List<dynamic> _vendors = [];
  List<dynamic> _customers = [];
  List<dynamic> _banks = [];
  List<dynamic> _bills = [];
  List<dynamic> _invoices = [];
  List<dynamic> _payments = [];
  Map<String, dynamic> _receivables = {};
  List<dynamic> _auditLog = [];
  List<dynamic> _numberSeries = [];
  final Map<String, TextEditingController> _seriesPrefixControllers = {};
  final Map<String, TextEditingController> _seriesLastControllers = {};

  bool _loading = true;
  bool _busy = false;
  String? _error;
  int? _selectedAccountId;
  int? _selectedYearId;
  String _voucherStatus = 'ALL';
  String _reportType = 'profit_loss';
  DateTimeRange? _range;
  Map<String, bool> _permissions = {};

  static const _types = ['Asset', 'Liability', 'Equity', 'Income', 'Expense'];
  static const _voucherTypes = [
    'Journal',
    'Payment',
    'Receipt',
    'Contra',
    'Sales',
    'Purchase'
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 12, vsync: this);
    _loadPermissionsAndData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final controller in _seriesPrefixControllers.values) {
      controller.dispose();
    }
    for (final controller in _seriesLastControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _can(String key) {
    final role = _roleSync;
    if (role == 'Super Admin') return true;
    return _permissions[key] ?? false;
  }

  String _roleSync = '';

  Future<void> _loadPermissionsAndData() async {
    try {
      final session = await SessionManager.getUserSession();
      final perms = await SessionManager.getPermissions();
      if (!mounted) return;
      setState(() {
        _roleSync = (session['role'] ?? '').toString();
        _permissions = perms;
      });
      await _loadAll();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _dateQuery {
    if (_range == null) return '';
    final from = _range!.start.toIso8601String().substring(0, 10);
    final to = _range!.end.toIso8601String().substring(0, 10);
    return '&from=$from&to=$to';
  }

  Future<Map<String, dynamic>> _fetch(String path) async {
    final res = await ApiClient.get(
      Uri.parse('${ApiClient.apiHost}/api/finance/$path'),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic> && body['success'] == true) return body;
      throw Exception(body is Map ? body['message'] : 'Request failed');
    }
    throw Exception('Request failed with status ${res.statusCode}');
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _fetch('dashboard'),
        _fetch('accounts'),
        _fetch('vouchers'),
        _fetch('trial-balance$_dateQuery'),
        _fetch('profit-loss$_dateQuery'),
        _fetch('balance-sheet$_dateQuery'),
        _fetch('parties'),
        _fetch('bills'),
        _fetch('invoices'),
        _fetch('payments'),
        _fetch('receivables'),
        _fetch('audit-log?limit=50'),
        _fetch('number-series'),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0];
        _accounts = (results[1]['data'] as List?) ?? [];
        _years = (results[1]['financialYears'] as List?) ?? [];
        _vouchers = (results[2]['data'] as List?) ?? [];
        _trialBalance = (results[3]['data'] as List?) ?? [];
        _trialTotals = (results[3]['totals'] as Map?)?.cast<String, dynamic>() ?? {};
        _profitLoss = results[4];
        _balanceSheet = results[5];
        _vendors = (results[6]['vendors'] as List?) ?? [];
        _customers = (results[6]['customers'] as List?) ?? [];
        _banks = (results[6]['banks'] as List?) ?? [];
        _bills = (results[7]['data'] as List?) ?? [];
        _invoices = (results[8]['data'] as List?) ?? [];
        _payments = (results[9]['data'] as List?) ?? [];
        _receivables = results[10];
        _auditLog = (results[11]['data'] as List?) ?? [];
        _numberSeries = (results[12]['data'] as List?) ?? [];
        for (final series in _numberSeries) {
          final docType = '${series['doc_type']}';
          _seriesPrefixControllers.putIfAbsent(
            docType,
            () => TextEditingController(text: '${series['prefix'] ?? ''}'),
          );
          _seriesLastControllers.putIfAbsent(
            docType,
            () => TextEditingController(text: '${series['last_number'] ?? 0}'),
          );
        }
        _selectedAccountId ??= _accounts.isNotEmpty
            ? int.tryParse('${_accounts.first['account_id']}')
            : null;
        if (_years.isNotEmpty) {
          for (final y in _years) {
            if (y['is_active'] == 1 || y['is_active'] == true) {
              _selectedYearId = int.tryParse('${y['fy_id']}');
              break;
            }
          }
        }
        _loading = false;
      });
      await _loadLedger();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLedger() async {
    if (_selectedAccountId == null) return;
    try {
      final data = await _fetch(
        'ledger?account_id=$_selectedAccountId$_dateQuery',
      );
      if (!mounted) return;
      setState(() {
        _ledgerAccount = (data['account'] as Map?)?.cast<String, dynamic>() ?? {};
        _ledger = (data['entries'] as List?) ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _range,
      helpText: 'Report date range',
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _loadAll();
    }
  }

  Future<bool> _mutate(String path, Map<String, dynamic> body,
      {String method = 'POST'}) async {
    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${ApiClient.apiHost}/api/finance/$path');
      final res = method == 'PUT'
          ? await ApiClient.put(uri, body: jsonEncode(body))
          : await ApiClient.post(uri, body: jsonEncode(body));
      final decoded = jsonDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300 && decoded['success'] == true) {
        await _loadAll();
        return true;
      }
      throw Exception(decoded['message'] ?? 'Request failed');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _money(dynamic value) {
    final n = double.tryParse('$value') ?? 0;
    final sign = n < 0 ? '-' : '';
    return '$sign\u20b9${n.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts & Finance'),
        actions: [
          IconButton(
            tooltip: 'Date range',
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: !isWide,
          tabs: const [
            Tab(text: 'Bank & Expenses', icon: Icon(Icons.account_balance_wallet_outlined)),
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Accounts', icon: Icon(Icons.account_tree_outlined)),
            Tab(text: 'Vouchers', icon: Icon(Icons.receipt_long_outlined)),
            Tab(text: 'Ledger', icon: Icon(Icons.book_outlined)),
            Tab(text: 'Trial Balance', icon: Icon(Icons.balance_outlined)),
            Tab(text: 'Reports', icon: Icon(Icons.bar_chart_outlined)),
            Tab(text: 'Parties', icon: Icon(Icons.people_outlined)),
            Tab(text: 'Bills', icon: Icon(Icons.local_shipping_outlined)),
            Tab(text: 'Invoices', icon: Icon(Icons.description_outlined)),
            Tab(text: 'Payments', icon: Icon(Icons.payments_outlined)),
            Tab(text: 'Activity', icon: Icon(Icons.history_outlined)),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (_loading && _dashboard.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _dashboard.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                    const SizedBox(height: 12),
                    Text('$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadAll,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            TabBarView(
              controller: _tabs,
              children: [
                QuickBankExpenseTab(
                  canAddExpense: _can('finance_create_voucher'),
                  onExpenseAdded: _loadAll,
                ),
                _overviewTab(),
                _accountsTab(),
                _vouchersTab(),
                _ledgerTab(),
                _trialBalanceTab(),
                _reportsTab(),
                _partiesTab(),
                _billsTab(),
                _invoicesTab(),
                _paymentsTab(),
                _activityTab(),
              ],
            ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Overview

  Widget _overviewTab() {
    final summary =
        (_dashboard['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final cash = (summary['Asset']) ?? 0;
    final recent = (_dashboard['recent_vouchers'] as List?) ?? [];
    final cashRows = (_dashboard['cash_and_bank'] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Financial Overview',
            trailing: Text(
              _selectedYearId == null
                  ? 'Active FY'
                  : 'FY: ${_years.where((y) => '${y['fy_id']}' == '$_selectedYearId').map((y) => y['fy_name']).join()}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cross = constraints.maxWidth >= 1000 ? 4 : (constraints.maxWidth >= 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.1,
                children: [
                  _statCard('Total assets', _money(cash), Icons.account_balance, Colors.teal),
                  _statCard('Liabilities', _money(summary['Liability']), Icons.credit_card, Colors.orange),
                  _statCard('Income', _money(summary['Income']), Icons.trending_up, Colors.green),
                  _statCard('Expenses', _money(summary['Expense']), Icons.trending_down, Colors.red),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Cash & Bank'),
          const SizedBox(height: 8),
          _card(
            child: cashRows.isEmpty
                ? const Text('No cash/bank accounts configured.')
                : Column(
                    children: cashRows.map((row) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.account_balance_wallet_outlined),
                        title: Text('${row['account_code']} - ${row['account_name']}'),
                        trailing: Text(_money(row['current_balance'])),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(
            'Recent Vouchers',
            trailing: TextButton(
              onPressed: () => _tabs.animateTo(2),
              child: const Text('View all'),
            ),
          ),
          const SizedBox(height: 8),
          _card(
            child: recent.isEmpty
                ? const Text('No vouchers posted yet.')
                : Column(
                    children: recent.map((row) {
                      final cancelled = '${row['status']}' == 'CANCELLED';
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: cancelled ? Colors.red.shade100 : Colors.teal.shade100,
                          child: Icon(
                            Icons.receipt_outlined,
                            size: 18,
                            color: cancelled ? Colors.red : Colors.teal,
                          ),
                        ),
                        title: Text('${row['voucher_no']}  -  ${row['voucher_type']}'),
                        subtitle: Text('${row['voucher_date']}'),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money(row['total_amount'])),
                            Text(
                              '${row['status']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cancelled ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Accounts

  Widget _accountsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Chart of Accounts (${_accounts.length})',
            trailing: _can('finance_manage_accounts')
                ? FilledButton.icon(
                    onPressed: _showAccountDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Account'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Group')),
                  DataColumn(label: Text('Balance'), numeric: true),
                ],
                rows: _accounts.map((row) {
                  return DataRow(cells: [
                    DataCell(Text('${row['account_code']}')),
                    DataCell(Text('${row['account_name']}')),
                    DataCell(Chip(
                      label: Text('${row['account_type']}'),
                      visualDensity: VisualDensity.compact,
                    )),
                    DataCell(Text('${row['sub_group'] ?? '-'}')),
                    DataCell(Text(_money(row['current_balance']))),
                  ]);
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Financial Years'),
          const SizedBox(height: 8),
          _card(
            child: _years.isEmpty
                ? const Text('No financial year configured.')
                : Column(
                    children: _years.map((year) {
                      final closed = year['is_closed'] == 1 || year['is_closed'] == true;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          closed ? Icons.lock_outline : Icons.calendar_month_outlined,
                          color: closed ? Colors.red : Colors.teal,
                        ),
                        title: Text('${year['fy_name']}'),
                        subtitle: Text('${year['start_date']} to ${year['end_date']}'),
                        trailing: _can('finance_close_fy')
                            ? TextButton(
                                onPressed: () async {
                                  final ok = await _mutate(
                                    'financial-years/${year['fy_id']}/status',
                                    {'is_closed': closed ? 0 : 1},
                                  );
                                  if (ok) _toast(closed ? 'Year reopened' : 'Year closed');
                                },
                                child: Text(closed ? 'Reopen' : 'Close'),
                              )
                            : Text(closed ? 'Closed' : 'Open'),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountDialog() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final group = TextEditingController(text: 'General');
    final opening = TextEditingController(text: '0');
    String type = 'Asset';
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Account'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Account code', hintText: 'e.g. 1500'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Account name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => type = v ?? 'Asset',
                ),
                TextFormField(
                  controller: group,
                  decoration: const InputDecoration(labelText: 'Sub group'),
                ),
                TextFormField(
                  controller: opening,
                  decoration: const InputDecoration(labelText: 'Opening balance'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final ok = await _mutate('accounts', {
      'account_code': code.text.trim(),
      'account_name': name.text.trim(),
      'account_type': type,
      'sub_group': group.text.trim(),
      'opening_balance': double.tryParse(opening.text) ?? 0,
    });
    if (ok) _toast('Account created');
  }

  // ---------------------------------------------------------------- Vouchers

  Widget _vouchersTab() {
    final filtered = _voucherStatus == 'ALL'
        ? _vouchers
        : _vouchers.where((v) => '${v['status']}' == _voucherStatus).toList();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Vouchers (${filtered.length})',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: _voucherStatus,
                  items: const ['ALL', 'POSTED', 'CANCELLED']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _voucherStatus = v ?? 'ALL'),
                ),
                const SizedBox(width: 8),
                if (_can('finance_create_voucher'))
                  FilledButton.icon(
                    onPressed: _showVoucherDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Voucher'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Voucher')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Narration')),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: filtered.map((row) {
                  final cancelled = '${row['status']}' == 'CANCELLED';
                  return DataRow(cells: [
                    DataCell(Text('${row['voucher_no']}')),
                    DataCell(Text('${row['voucher_date']}')),
                    DataCell(Text('${row['voucher_type']}')),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text('${row['narration'] ?? ''}', overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(_money(row['total_amount']))),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text('${row['status']}'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: cancelled ? Colors.red.shade100 : Colors.green.shade100,
                        ),
                        if (!cancelled && _can('finance_create_voucher'))
                          IconButton(
                            tooltip: 'Cancel voucher',
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            onPressed: () => _confirmCancel('${row['voucher_id']}', '${row['voucher_no']}'),
                          ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(String id, String number) async {
    final reason = TextEditingController(text: 'Cancelled by user');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel $number?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel voucher'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _mutate('vouchers/$id/cancel', {'reason': reason.text});
    if (ok) _toast('Voucher cancelled; balances reversed');
  }

  Future<void> _showVoucherDialog() async {
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final narration = TextEditingController();
    String type = 'Journal';
    final lines = <_VoucherLine>[_VoucherLine(), _VoucherLine()];
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Voucher'),
        content: SizedBox(
          width: 620,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: date,
                          decoration: const InputDecoration(labelText: 'Voucher date (YYYY-MM-DD)'),
                          validator: (v) => DateTime.tryParse(v ?? '') == null ? 'Invalid date' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: _voucherTypes
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => type = v ?? 'Journal',
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: narration,
                    decoration: const InputDecoration(labelText: 'Narration'),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(lines.length, (index) {
                    final line = lines[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              initialValue: line.accountId,
                              decoration: InputDecoration(labelText: 'Account ${index + 1}'),
                              items: _accounts.map((a) {
                                return DropdownMenuItem<int>(
                                  value: int.tryParse('${a['account_id']}'),
                                  child: Text('${a['account_code']} - ${a['account_name']}'),
                                );
                              }).toList(),
                              onChanged: (v) => line.accountId = v,
                              validator: (v) => v == null ? 'Choose account' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: line.debit,
                              decoration: const InputDecoration(labelText: 'Debit'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: line.credit,
                              decoration: const InputDecoration(labelText: 'Credit'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: lines.length > 2
                                ? () => setState(() => lines.removeAt(index))
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setState(() => lines.add(_VoucherLine())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final debit = lines.fold<double>(
                0, (sum, l) => sum + (double.tryParse(l.debit.text) ?? 0));
              final credit = lines.fold<double>(
                0, (sum, l) => sum + (double.tryParse(l.credit.text) ?? 0));
              if ((debit - credit).abs() > 0.01) {
                _toast('Debit and credit totals must match');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final items = lines
        .where((l) => l.accountId != null)
        .map((l) => <String, dynamic>{
              'account_id': l.accountId,
              'debit_amount': double.tryParse(l.debit.text) ?? 0,
              'credit_amount': double.tryParse(l.credit.text) ?? 0,
            })
        .toList();
    final ok = await _mutate('vouchers', {
      'voucher_type': type,
      'voucher_date': date.text.trim(),
      'narration': narration.text.trim(),
      'items': items,
    });
    if (ok) _toast('Voucher posted');
  }

  // ----------------------------------------------------------------- Ledger

  Widget _ledgerTab() {
    return RefreshIndicator(
      onRefresh: _loadLedger,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Account Ledger'),
          const SizedBox(height: 12),
          _card(
            child: DropdownButtonFormField<int>(
              initialValue: _selectedAccountId,
              decoration: const InputDecoration(
                labelText: 'Account',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: _accounts.map((a) {
                return DropdownMenuItem<int>(
                  value: int.tryParse('${a['account_id']}'),
                  child: Text('${a['account_code']} - ${a['account_name']}'),
                );
              }).toList(),
              onChanged: (v) {
                setState(() => _selectedAccountId = v);
                _loadLedger();
              },
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('Opening: ${_money(_ledgerAccount['opening_balance'] ?? 0)}'),
                Text('Closing: ${_money(_ledgerAccount['current_balance'] ?? 0)}'),
                Text(
                  'Type: ${_ledgerAccount['account_type'] ?? '-'}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Voucher')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                  DataColumn(label: Text('Running'), numeric: true),
                ],
                rows: _ledger.map((entry) {
                  return DataRow(cells: [
                    DataCell(Text('${entry['voucher_date']}')),
                    DataCell(Text('${entry['voucher_no']}')),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text('${entry['narration'] ?? entry['description'] ?? ''}',
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(_money(entry['debit_amount']))),
                    DataCell(Text(_money(entry['credit_amount']))),
                    DataCell(Text(
                      '${_money(entry['running_balance'])} ${entry['running_side'] ?? ''}',
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- Trial balance

  Widget _trialBalanceTab() {
    final totals = _trialTotals;
    final balanced = totals['is_balanced'] == true;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Trial Balance',
            trailing: Chip(
              label: Text(balanced ? 'Balanced' : 'Out of balance'),
              backgroundColor: balanced ? Colors.green.shade100 : Colors.red.shade100,
            ),
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                  DataColumn(label: Text('Closing'), numeric: true),
                ],
                rows: [
                  ..._trialBalance.map((row) {
                    return DataRow(cells: [
                      DataCell(Text('${row['account_code']}')),
                      DataCell(Text('${row['account_name']}')),
                      DataCell(Text('${row['account_type']}')),
                      DataCell(Text(_money(row['total_debit']))),
                      DataCell(Text(_money(row['total_credit']))),
                      DataCell(Text('${_money(row['closing_balance'])} ${row['closing_side'] ?? ''}')),
                    ]);
                  }),
                  DataRow(
                    color: WidgetStateProperty.all(Colors.teal.shade50),
                    cells: [
                      const DataCell(Text('')),
                      const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      DataCell(Text(_money(totals['debit']),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_money(totals['credit']),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Reports

  Widget _reportsTab() {
    final isPl = _reportType == 'profit_loss';
    final data = isPl
        ? (_profitLoss['data'] as List?) ?? []
        : (_balanceSheet['data'] as List?) ?? [];
    final totals = isPl ? _profitLoss : (_balanceSheet['totals'] as Map?) ?? {};
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Financial Reports',
            trailing: DropdownButton<String>(
              value: _reportType,
              items: const [
                DropdownMenuItem(value: 'profit_loss', child: Text('Profit & Loss')),
                DropdownMenuItem(value: 'balance_sheet', child: Text('Balance Sheet')),
              ],
              onChanged: (v) => setState(() => _reportType = v ?? 'profit_loss'),
            ),
          ),
          const SizedBox(height: 12),
          if (isPl) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final cross = constraints.maxWidth >= 700 ? 3 : 1;
                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.4,
                  children: [
                    _statCard('Income', _money(_profitLoss['income']), Icons.trending_up, Colors.green),
                    _statCard('Expense', _money(_profitLoss['expense']), Icons.trending_down, Colors.red),
                    _statCard('Net profit', _money(_profitLoss['net_profit']), Icons.savings, Colors.teal),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
          ] else ...[
            _card(
              child: Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text('Assets: ${_money(totals['assets'])}'),
                  Text('Liabilities: ${_money(totals['liabilities'])}'),
                  Text('Equity: ${_money(totals['equity'])}'),
                  Text('Net profit: ${_money(totals['net_profit'])}'),
                  Text('L + E: ${_money(totals['liabilities_and_equity'])}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Amount'), numeric: true),
                ],
                rows: data.map((row) {
                  return DataRow(cells: [
                    DataCell(Text('${row['account_code']}')),
                    DataCell(Text('${row['account_name']}')),
                    DataCell(Text('${row['account_type']}')),
                    DataCell(Text(_money(isPl ? row['amount'] : row['balance']))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ Parties & documents

  Widget _partyCard(String title, IconData icon, List<dynamic> rows, String kind,
      List<String> fields) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (_can('finance_manage_accounts'))
                IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onPressed: () => _showPartyDialog(kind),
                ),
            ],
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No records yet.'),
            )
          else
            ...rows.map((row) {
              final label = '${row[fields.first]}';
              final sub = fields.skip(1)
                  .where((f) => row[f] != null && '$row$f'.isNotEmpty)
                  .map((f) => '${row[f]}')
                  .join('  |  ');
              return ListTile(
                dense: true,
                title: Text(label),
                subtitle: sub.isEmpty ? null : Text(sub),
                trailing: _can('finance_manage_accounts')
                    ? IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showPartyDialog(
                          kind,
                          row: Map<String, dynamic>.from(row as Map),
                        ),
                      )
                    : null,
              );
            }),
        ],
      ),
    );
  }

  Widget _partiesTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Masters'),
          const SizedBox(height: 12),
          _partyCard('Vendors', Icons.store_outlined, _vendors, 'vendors', [
            'vendor_name', 'gstin', 'contact', 'payment_terms', 'credit_limit'
          ]),
          const SizedBox(height: 12),
          _partyCard('Customers', Icons.people_outline, _customers, 'customers', [
            'customer_name', 'gstin', 'contact', 'payment_terms', 'credit_limit'
          ]),
          const SizedBox(height: 12),
          _partyCard('Bank Accounts', Icons.account_balance, _banks, 'banks', [
            'bank_name', 'account_ref', 'ifsc', 'branch', 'account_type'
          ]),
        ],
      ),
    );
  }

  static const _partyFormFields = <String, List<Map<String, String>>>{
    'vendors': [
      {'key': 'gstin', 'label': 'GSTIN'},
      {'key': 'pan', 'label': 'PAN'},
      {'key': 'contact', 'label': 'Contact'},
      {'key': 'address', 'label': 'Address'},
      {'key': 'payment_terms', 'label': 'Payment terms (e.g. Net 30)'},
      {'key': 'bank_name', 'label': 'Bank name'},
      {'key': 'bank_account_no', 'label': 'Bank account no'},
      {'key': 'bank_ifsc', 'label': 'Bank IFSC'},
      {'key': 'credit_limit', 'label': 'Credit limit'},
    ],
    'customers': [
      {'key': 'gstin', 'label': 'GSTIN'},
      {'key': 'pan', 'label': 'PAN'},
      {'key': 'contact', 'label': 'Contact'},
      {'key': 'address', 'label': 'Address'},
      {'key': 'payment_terms', 'label': 'Payment terms (e.g. Net 30)'},
      {'key': 'credit_limit', 'label': 'Credit limit'},
    ],
    'banks': [
      {'key': 'ifsc', 'label': 'IFSC'},
      {'key': 'branch', 'label': 'Branch'},
      {'key': 'account_type', 'label': 'Account type'},
      {'key': 'contact', 'label': 'Contact'},
    ],
  };

  String _partyIdKey(String kind) {
    if (kind == 'vendors') return 'vendor_id';
    if (kind == 'customers') return 'customer_id';
    return 'bank_account_id';
  }

  String _partyNameKey(String kind) {
    if (kind == 'vendors') return 'vendor_name';
    if (kind == 'customers') return 'customer_name';
    return 'bank_name';
  }

  Future<void> _showPartyDialog(String kind, {Map<String, dynamic>? row}) async {
    final editing = row != null;
    final nameKey = _partyNameKey(kind);
    final name = TextEditingController(text: editing ? '${row[nameKey] ?? ''}' : '');
    final accountRef = TextEditingController(
      text: editing ? '${row['account_ref'] ?? ''}' : '',
    );
    final controllers = <String, TextEditingController>{
      for (final field in _partyFormFields[kind] ?? const <Map<String, String>>[])
        field['key']!: TextEditingController(
          text: editing
              ? (row[field['key']] == null ? '' : '${row[field['key']]}')
              : '',
        ),
    };
    final labels = {
      'vendors': 'Vendor name',
      'customers': 'Customer name',
      'banks': 'Bank name',
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${editing ? 'Edit' : 'Add'} ${labels[kind]}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: labels[kind]),
                ),
                if (kind == 'banks')
                  TextField(
                    controller: accountRef,
                    decoration: const InputDecoration(labelText: 'Account reference'),
                  ),
                ...controllers.entries.map((entry) {
                  final label = (_partyFormFields[kind] ?? [])
                      .firstWhere(
                        (field) => field['key'] == entry.key,
                        orElse: () => {'key': entry.key, 'label': entry.key},
                      )['label'];
                  return TextField(
                    controller: entry.value,
                    decoration: InputDecoration(labelText: label),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    final body = <String, dynamic>{'name': name.text.trim()};
    if (kind == 'banks' && accountRef.text.trim().isNotEmpty) {
      body['account_ref'] = accountRef.text.trim();
    }
    for (final entry in controllers.entries) {
      final value = entry.value.text.trim();
      if (value.isEmpty) continue;
      body[entry.key] = entry.key == 'credit_limit'
          ? double.tryParse(value) ?? 0
          : value;
    }
    final path = editing
        ? 'parties/$kind/${row[_partyIdKey(kind)]}'
        : 'parties/$kind';
    final ok = await _mutate(
      path,
      body,
      method: editing ? 'PUT' : 'POST',
    );
    if (ok) _toast(editing ? 'Updated' : 'Saved');
  }

  Widget _billsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Vendor Bills (${_bills.length})',
            trailing: _can('finance_manage_bills')
                ? FilledButton.icon(
                    onPressed: _showBillDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Bill'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          ..._bills.map((bill) {
            final status = '${bill['status']}';
            final match = '${bill['match_status']}';
            return _card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: status == 'FLAGGED'
                      ? Colors.red.shade100
                      : Colors.teal.shade100,
                  child: Icon(Icons.receipt_long, color: status == 'FLAGGED' ? Colors.red : Colors.teal),
                ),
                title: Text('${bill['bill_no']}  -  ${bill['vendor_name']}'),
                subtitle: Text(
                  '${bill['bill_date']}  |  Due: ${bill['due_date'] ?? '-'}  |  '
                  'PO: ${bill['po_no'] ?? '-'}  |  GRN: ${bill['grn_no'] ?? '-'}\n'
                  '$match  |  ${bill['hold_reason'] ?? 'No hold'}',
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(bill['total_amount'])),
                    if (status == 'DRAFT' && match == 'MATCHED' && _can('finance_manage_bills'))
                      TextButton(
                        onPressed: () async {
                          final ok = await _mutate('bills/${bill['bill_id']}/approve', {});
                          if (ok) _toast('Bill approved');
                        },
                        child: const Text('Approve'),
                      )
                    else
                      Text(status, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          }),
          if (_bills.isEmpty) const Text('No bills recorded.'),
        ],
      ),
    );
  }

  Future<void> _showBillDialog() async {
    final billNo = TextEditingController();
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final dueDate = TextEditingController();
    final poNo = TextEditingController();
    final grnNo = TextEditingController();
    final poAmount = TextEditingController(text: '0');
    final grnAmount = TextEditingController(text: '0');
    final description = TextEditingController();
    final qty = TextEditingController(text: '1');
    final rate = TextEditingController();
    final tax = TextEditingController(text: '0');
    int? vendorId = _vendors.isNotEmpty ? int.tryParse('${_vendors.first['vendor_id']}') : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Vendor Bill'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: vendorId,
                  decoration: const InputDecoration(labelText: 'Vendor'),
                  items: _vendors
                      .map((v) => DropdownMenuItem<int>(
                            value: int.tryParse('${v['vendor_id']}'),
                            child: Text('${v['vendor_name']}'),
                          ))
                      .toList(),
                  onChanged: (v) => vendorId = v,
                ),
                TextField(
                  controller: billNo,
                  decoration: const InputDecoration(
                    labelText: 'Bill number',
                    hintText: 'Auto-generated if left blank',
                  ),
                ),
                TextField(controller: date, decoration: const InputDecoration(labelText: 'Bill date')),
                TextField(
                  controller: dueDate,
                  decoration: const InputDecoration(
                    labelText: 'Due date',
                    hintText: 'Auto from vendor payment terms',
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: poNo, decoration: const InputDecoration(labelText: 'PO no'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: poAmount, decoration: const InputDecoration(labelText: 'PO amount'))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: grnNo, decoration: const InputDecoration(labelText: 'GRN no'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: grnAmount, decoration: const InputDecoration(labelText: 'GRN amount'))),
                  ],
                ),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
                Row(
                  children: [
                    Expanded(child: TextField(controller: qty, decoration: const InputDecoration(labelText: 'Qty'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: rate, decoration: const InputDecoration(labelText: 'Rate'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: tax, decoration: const InputDecoration(labelText: 'Tax'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || vendorId == null) return;
    final billNumber = billNo.text.trim();
    final billDueDate = dueDate.text.trim();
    final ok = await _mutate('bills', {
      'vendor_id': vendorId,
      if (billNumber.isNotEmpty) 'bill_no': billNumber,
      'bill_date': date.text.trim(),
      if (billDueDate.isNotEmpty) 'due_date': billDueDate,
      'po_no': poNo.text.trim().isEmpty ? null : poNo.text.trim(),
      'grn_no': grnNo.text.trim().isEmpty ? null : grnNo.text.trim(),
      'po_amount': double.tryParse(poAmount.text) ?? 0,
      'grn_amount': double.tryParse(grnAmount.text) ?? 0,
      'tax_amount': double.tryParse(tax.text) ?? 0,
      'items': [
        {
          'description': description.text.trim(),
          'qty': double.tryParse(qty.text) ?? 1,
          'rate': double.tryParse(rate.text) ?? 0,
        }
      ],
    });
    if (ok) _toast('Bill saved');
  }

  Widget _invoicesTab() {
    final buckets = (_receivables['buckets'] as Map?)?.cast<String, dynamic>() ?? {};
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Customer Invoices (${_invoices.length})',
            trailing: _can('finance_manage_invoices')
                ? FilledButton.icon(
                    onPressed: _showInvoiceDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Invoice'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _card(
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Current: ${_money(buckets['current'] ?? 0)}'),
                Text('30d: ${_money(buckets['days_30'] ?? 0)}'),
                Text('60d: ${_money(buckets['days_60'] ?? 0)}'),
                Text('90d: ${_money(buckets['days_90'] ?? 0)}'),
                Text('>90d: ${_money(buckets['over_90'] ?? 0)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._invoices.map((invoice) {
            final due = num.tryParse('${invoice['total_amount']}') ?? 0;
            final paid = num.tryParse('${invoice['paid_amount']}') ?? 0;
            return _card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined, color: Colors.teal),
                title: Text('${invoice['invoice_no']}  -  ${invoice['customer_name']}'),
                subtitle: Text(
                  '${invoice['invoice_date']}  |  Due: ${invoice['due_date'] ?? '-'}  |  ${invoice['status']}',
                ),
                trailing: Text('Due ${_money(due - paid)}'),
              ),
            );
          }),
          if (_invoices.isEmpty) const Text('No invoices issued.'),
        ],
      ),
    );
  }

  Future<void> _showInvoiceDialog() async {
    final invoiceNo = TextEditingController();
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final dueDate = TextEditingController();
    final description = TextEditingController();
    final qty = TextEditingController(text: '1');
    final rate = TextEditingController();
    final tax = TextEditingController(text: '0');
    int? customerId = _customers.isNotEmpty
        ? int.tryParse('${_customers.first['customer_id']}')
        : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Invoice'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: customerId,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: _customers
                    .map((c) => DropdownMenuItem<int>(
                          value: int.tryParse('${c['customer_id']}'),
                          child: Text('${c['customer_name']}'),
                        ))
                    .toList(),
                onChanged: (v) => customerId = v,
              ),
              TextField(
                controller: invoiceNo,
                decoration: const InputDecoration(
                  labelText: 'Invoice number',
                  hintText: 'Auto-generated if left blank',
                ),
              ),
              TextField(controller: date, decoration: const InputDecoration(labelText: 'Invoice date')),
              TextField(
                controller: dueDate,
                decoration: const InputDecoration(
                  labelText: 'Due date',
                  hintText: 'Auto from customer payment terms',
                ),
              ),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              Row(
                children: [
                  Expanded(child: TextField(controller: qty, decoration: const InputDecoration(labelText: 'Qty'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: rate, decoration: const InputDecoration(labelText: 'Rate'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: tax, decoration: const InputDecoration(labelText: 'Tax'))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Issue')),
        ],
      ),
    );
    if (saved != true || customerId == null) return;
    final number = invoiceNo.text.trim();
    final invoiceDueDate = dueDate.text.trim();
    final ok = await _mutate('invoices', {
      'customer_id': customerId,
      if (number.isNotEmpty) 'invoice_no': number,
      'invoice_date': date.text.trim(),
      if (invoiceDueDate.isNotEmpty) 'due_date': invoiceDueDate,
      'tax_amount': double.tryParse(tax.text) ?? 0,
      'items': [
        {
          'description': description.text.trim(),
          'qty': double.tryParse(qty.text) ?? 1,
          'rate': double.tryParse(rate.text) ?? 0,
        }
      ],
    });
    if (ok) _toast('Invoice issued');
  }

  Widget _paymentsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(
            'Payments & Receipts (${_payments.length})',
            trailing: _can('finance_record_payment')
                ? FilledButton.icon(
                    onPressed: _showPaymentDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Record'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Document')),
                  DataColumn(label: Text('Bank')),
                  DataColumn(label: Text('Mode')),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('Voucher')),
                ],
                rows: _payments.map((row) {
                  return DataRow(cells: [
                    DataCell(Text('${row['pay_date']}')),
                    DataCell(Text('${row['bill_no'] ?? row['invoice_no'] ?? '-'}')),
                    DataCell(Text('${row['bank_name']}')),
                    DataCell(Text('${row['mode']}')),
                    DataCell(Text(_money(row['amount']))),
                    DataCell(Text('${row['voucher_id'] ?? '-'}')),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Audit trail (last 50)'),
          const SizedBox(height: 12),
          _card(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('When')),
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Action')),
                  DataColumn(label: Text('Record')),
                  DataColumn(label: Text('Summary')),
                ],
                rows: _auditLog.map((row) {
                  return DataRow(cells: [
                    DataCell(Text('${row['created_at'] ?? ''}')),
                    DataCell(Text('${row['created_by_email'] ?? '-'}')),
                    DataCell(Text('${row['action'] ?? ''}')),
                    DataCell(Text('${row['entity'] ?? ''} #${row['entity_id'] ?? ''}')),
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: Text(
                          '${row['summary'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ),
          if (_auditLog.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No activity recorded yet.'),
            ),
          const SizedBox(height: 20),
          _sectionTitle('Document numbering'),
          const SizedBox(height: 12),
          ..._numberSeries.map((series) {
            final docType = '${series['doc_type']}';
            final prefix = _seriesPrefixControllers[docType] ?? TextEditingController();
            final last = _seriesLastControllers[docType] ?? TextEditingController();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                child: Row(
                  children: [
                    SizedBox(width: 140, child: Text(docType)),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: prefix,
                        decoration: const InputDecoration(labelText: 'Prefix'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: last,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Last no'),
                      ),
                    ),
                    const Spacer(),
                    if (_can('finance_manage_accounts'))
                      FilledButton.tonal(
                        onPressed: () async {
                          final ok = await _mutate(
                            'number-series/$docType',
                            {
                              'prefix': prefix.text.trim(),
                              'last_number': int.tryParse(last.text.trim()) ?? 0,
                            },
                            method: 'PUT',
                          );
                          if (ok) _toast('Number series saved');
                        },
                        child: const Text('Save'),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showPaymentDialog() async {
    bool isPayment = true;
    int? billId;
    int? invoiceId;
    int? bankId = _banks.isNotEmpty ? int.tryParse('${_banks.first['bank_account_id']}') : null;
    final amount = TextEditingController();
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    final reference = TextEditingController();
    String mode = 'NEFT';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Payment / Receipt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<bool>(
                  initialValue: isPayment,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Vendor payment')),
                    DropdownMenuItem(value: false, child: Text('Customer receipt')),
                  ],
                  onChanged: (v) => setDialogState(() {
                    isPayment = v ?? true;
                    billId = null;
                    invoiceId = null;
                  }),
                ),
                if (isPayment)
                  DropdownButtonFormField<int>(
                    initialValue: billId,
                    decoration: const InputDecoration(labelText: 'Approved bill'),
                    items: _bills
                        .where((b) => '${b['status']}' == 'APPROVED')
                        .map((b) => DropdownMenuItem<int>(
                              value: int.tryParse('${b['bill_id']}'),
                              child: Text('${b['bill_no']} - ${_money(b['total_amount'])}'),
                            ))
                        .toList(),
                    onChanged: (v) => billId = v,
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: invoiceId,
                    decoration: const InputDecoration(labelText: 'Issued invoice'),
                    items: _invoices
                        .where((i) => '${i['status']}' == 'ISSUED')
                        .map((i) => DropdownMenuItem<int>(
                              value: int.tryParse('${i['invoice_id']}'),
                              child: Text('${i['invoice_no']} - ${_money(i['total_amount'])}'),
                            ))
                        .toList(),
                    onChanged: (v) => invoiceId = v,
                  ),
                DropdownButtonFormField<int>(
                  initialValue: bankId,
                  decoration: const InputDecoration(labelText: 'Bank account'),
                  items: _banks
                      .map((b) => DropdownMenuItem<int>(
                            value: int.tryParse('${b['bank_account_id']}'),
                            child: Text('${b['bank_name']} - ${b['account_ref']}'),
                          ))
                      .toList(),
                  onChanged: (v) => bankId = v,
                ),
                TextField(controller: amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number),
                TextField(controller: date, decoration: const InputDecoration(labelText: 'Date')),
                TextField(controller: reference, decoration: const InputDecoration(labelText: 'Reference no')),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const ['NEFT', 'RTGS', 'Cheque', 'Cash', 'UPI']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => mode = v ?? 'NEFT',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (saved != true || bankId == null || (isPayment ? billId == null : invoiceId == null)) return;
    final ok = await _mutate('payments', {
      if (isPayment) 'bill_id': billId else 'invoice_id': invoiceId,
      'bank_account_id': bankId,
      'pay_date': date.text.trim(),
      'amount': double.tryParse(amount.text) ?? 0,
      'mode': mode,
      'reference_no': reference.text.trim().isEmpty ? null : reference.text.trim(),
    });
    if (ok) _toast('Payment posted to ledger');
  }
}

class _VoucherLine {
  int? accountId;
  final debit = TextEditingController();
  final credit = TextEditingController();
}
