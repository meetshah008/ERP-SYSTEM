import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/web_open_helper.dart';

class QuickFinanceReportsPage extends StatefulWidget {
  final List<dynamic> bankAccounts;

  const QuickFinanceReportsPage({
    super.key,
    required this.bankAccounts,
  });

  @override
  State<QuickFinanceReportsPage> createState() =>
      _QuickFinanceReportsPageState();
}

class _QuickFinanceReportsPageState extends State<QuickFinanceReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late DateTime _fromDate;
  late DateTime _toDate;
  int? _selectedAccountId;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _totals = {};
  List<dynamic> _book = [];
  List<dynamic> _categories = [];
  List<dynamic> _months = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);
  double _toDouble(dynamic val) => double.tryParse('${val ?? 0}') ?? 0.0;

  String get _queryParams {
    final acc = _selectedAccountId != null ? '&account_id=$_selectedAccountId' : '';
    return 'from=${_fmt(_fromDate)}&to=${_fmt(_toDate)}$acc';
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiClient.apiHost}/api/finance/quick-reports?$_queryParams'),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (!mounted) return;
        setState(() {
          _totals = Map<String, dynamic>.from(body['totals'] ?? {});
          _book = body['cashBankBook'] ?? [];
          _categories = body['categorySummary'] ?? [];
          _months = body['monthSummary'] ?? [];
          _loading = false;
        });
      } else {
        throw Exception(body['message'] ?? 'Failed to load reports');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _loadReport();
    }
  }

  void _printPdf() {
    if (!kIsWeb) return;
    final bookRows = _book.map((r) => '''
      <tr>
        <td>${r['entry_date']}</td>
        <td>${r['voucher_no']}</td>
        <td>${r['voucher_type']}</td>
        <td>${r['title'] ?? ''}</td>
        <td>${r['account_name'] ?? ''}</td>
        <td style="text-align:right;color:green;">${_toDouble(r['money_in']) > 0 ? '&#8377;${_toDouble(r['money_in']).toStringAsFixed(2)}' : '-'}</td>
        <td style="text-align:right;color:red;">${_toDouble(r['money_out']) > 0 ? '&#8377;${_toDouble(r['money_out']).toStringAsFixed(2)}' : '-'}</td>
      </tr>
    ''').join();

    final catRows = _categories.map((c) => '''
      <tr>
        <td>${c['category_name']}</td>
        <td style="text-align:center;">${c['entries_count']}</td>
        <td style="text-align:right;">&#8377;${_toDouble(c['total_amount']).toStringAsFixed(2)}</td>
      </tr>
    ''').join();

    final monthRows = _months.map((m) => '''
      <tr>
        <td>${m['month_key']}</td>
        <td style="text-align:center;">${m['entries_count']}</td>
        <td style="text-align:right;">&#8377;${_toDouble(m['total_amount']).toStringAsFixed(2)}</td>
      </tr>
    ''').join();

    final html = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>Finance Report (${_fmt(_fromDate)} to ${_fmt(_toDate)})</title>
        <style>
          @page { margin: 16mm; }
          body { font-family: Arial, sans-serif; padding: 24px; color: #222; }
          h1 { margin: 0 0 4px; font-size: 22px; color: #0f766e; }
          p.sub { margin: 0 0 18px; color: #555; font-size: 13px; }
          .kpis { display: flex; gap: 14px; margin-bottom: 22px; flex-wrap: wrap; }
          .kpi { border: 1px solid #d1d5db; border-radius: 8px; padding: 12px 16px; min-width: 150px; background: #fafafa; }
          .kpi small { color: #666; display: block; margin-bottom: 4px; font-size: 12px; }
          .kpi strong { font-size: 16px; }
          h2 { font-size: 15px; margin: 22px 0 8px; color: #111827; border-bottom: 2px solid #e5e7eb; padding-bottom: 4px; }
          table { width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 12px; }
          th, td { border: 1px solid #d1d5db; padding: 7px 9px; text-align: left; }
          th { background: #f3f4f6; font-weight: 600; }
        </style>
      </head>
      <body onload="window.print()">
        <h1>Bank &amp; Expenses Report</h1>
        <p class="sub">Period: ${_fmt(_fromDate)} to ${_fmt(_toDate)}</p>
        <div class="kpis">
          <div class="kpi"><small>Money In</small><strong style="color:#15803d;">&#8377;${_toDouble(_totals['totalIn']).toStringAsFixed(2)}</strong></div>
          <div class="kpi"><small>Money Out</small><strong style="color:#b91c1c;">&#8377;${_toDouble(_totals['totalOut']).toStringAsFixed(2)}</strong></div>
          <div class="kpi"><small>Net Flow</small><strong style="color:#4338ca;">&#8377;${_toDouble(_totals['netChange']).toStringAsFixed(2)}</strong></div>
          <div class="kpi"><small>Total Expenses</small><strong style="color:#c2410c;">&#8377;${_toDouble(_totals['totalExpense']).toStringAsFixed(2)}</strong></div>
        </div>
        <h2>Cash &amp; Bank Book</h2>
        <table>
          <thead><tr><th>Date</th><th>Voucher</th><th>Type</th><th>Title</th><th>Account</th><th>Money In</th><th>Money Out</th></tr></thead>
          <tbody>${bookRows.isEmpty ? '<tr><td colspan="7">No entries in selected period</td></tr>' : bookRows}</tbody>
        </table>
        <h2>Category-wise Expenses</h2>
        <table>
          <thead><tr><th>Category</th><th>Entries</th><th>Total</th></tr></thead>
          <tbody>${catRows.isEmpty ? '<tr><td colspan="3">No expenses in selected period</td></tr>' : catRows}</tbody>
        </table>
        <h2>Month-wise Expenses</h2>
        <table>
          <thead><tr><th>Month</th><th>Entries</th><th>Total</th></tr></thead>
          <tbody>${monthRows.isEmpty ? '<tr><td colspan="3">No expenses in selected period</td></tr>' : monthRows}</tbody>
        </table>
      </body>
      </html>
    ''';

    openHtmlInNewTab(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank & Expense Reports'),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _printPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Print / PDF'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Cash / Bank Book'),
            Tab(text: 'Category-wise'),
            Tab(text: 'Month-wise'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text('${_fmt(_fromDate)}  →  ${_fmt(_toDate)}'),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Filter Account',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Cash & Bank'),
                      ),
                      ...widget.bankAccounts.map<DropdownMenuItem<int?>>(
                        (b) => DropdownMenuItem<int?>(
                          value: b['account_id'] as int,
                          child: Text('${b['account_name']}'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedAccountId = v);
                      _loadReport();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _kpi('Money In', _toDouble(_totals['totalIn']), Colors.green),
                _kpi('Money Out', _toDouble(_totals['totalOut']), Colors.red),
                _kpi('Net Flow', _toDouble(_totals['netChange']), Colors.indigo),
                _kpi('Total Expense', _toDouble(_totals['totalExpense']), Colors.orange),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBookTab(),
                          _buildSummaryTab(_categories, 'category_name', 'No category expenses in this range.'),
                          _buildSummaryTab(_months, 'month_key', 'No monthly expenses in this range.'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String title, double value, Color color) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(
                '₹${value.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookTab() {
    if (_book.isEmpty) {
      return const Center(child: Text('No Cash/Bank entries in this date range.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _book.length,
      itemBuilder: (_, i) {
        final r = _book[i];
        final moneyIn = _toDouble(r['money_in']);
        final moneyOut = _toDouble(r['money_out']);
        final isIn = moneyIn > 0;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.12),
              child: Icon(
                isIn ? Icons.arrow_downward : Icons.arrow_upward,
                color: isIn ? Colors.green : Colors.red,
              ),
            ),
            title: Text('${r['title'] ?? r['voucher_type']}'),
            subtitle: Text('${r['entry_date']} • ${r['voucher_no']} • ${r['account_name']}'),
            trailing: Text(
              isIn ? '+ ₹${moneyIn.toStringAsFixed(2)}' : '- ₹${moneyOut.toStringAsFixed(2)}',
              style: TextStyle(
                color: isIn ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryTab(List<dynamic> rows, String labelKey, String emptyText) {
    if (rows.isEmpty) return Center(child: Text(emptyText));
    final total = rows.fold<double>(0, (s, r) => s + _toDouble(r['total_amount']));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final amt = _toDouble(r['total_amount']);
        final pct = total > 0 ? (amt / total) : 0.0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${r[labelKey]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '₹${amt.toStringAsFixed(2)} (${(pct * 100).toStringAsFixed(1)}%)',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: pct, minHeight: 6),
                const SizedBox(height: 4),
                Text('${r['entries_count']} entries', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        );
      },
    );
  }
}
