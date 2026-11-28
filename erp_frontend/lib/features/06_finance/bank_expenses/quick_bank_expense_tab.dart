import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import '../../../core/utils/web_open_helper.dart';
import 'quick_finance_reports_page.dart';

class QuickBankExpenseTab extends StatefulWidget {
  final bool canAddExpense;
  final VoidCallback onExpenseAdded;

  const QuickBankExpenseTab({
    super.key,
    required this.canAddExpense,
    required this.onExpenseAdded,
  });

  @override
  State<QuickBankExpenseTab> createState() => _QuickBankExpenseTabState();
}

class _QuickBankExpenseTabState extends State<QuickBankExpenseTab> {
  bool _loading = true;
  String? _error;
  List<dynamic> _banks = [];
  List<dynamic> _categories = [];
  List<dynamic> _depositSources = [];
  List<dynamic> _transactions = [];

  String _searchQuery = '';
  String _typeFilter = 'ALL'; // ALL, Payment, Receipt, Contra, CANCELLED

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiClient.apiHost}/api/finance/quick-expenses'),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (!mounted) return;
        setState(() {
          _banks = body['bankAccounts'] ?? [];
          _categories = body['expenseCategories'] ?? [];
          _depositSources = body['depositSources'] ?? [];
          _transactions = body['expenses'] ?? [];
          _loading = false;
        });
      } else {
        throw Exception(body['message'] ?? 'Failed to load Bank & Expenses');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double _toDouble(dynamic val) => double.tryParse('${val ?? 0}') ?? 0.0;

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 19) : null,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.6,
        ),
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Widget _buildStyledDialog(
    BuildContext context, {
    required IconData icon,
    required Color accentColor,
    required String title,
    required String subtitle,
    required Widget content,
    required String primaryLabel,
    required bool saving,
    required VoidCallback onSubmit,
    bool showPrimary = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 600;

    final header = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, isMobile ? 12 : 18, 12, 16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.18 : 0.08),
        border: Border(
          bottom: BorderSide(color: accentColor.withValues(alpha: 0.16)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMobile)
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ],
      ),
    );

    final footer = Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, isMobile ? 16 : 18),
      decoration: BoxDecoration(
        color: isMobile && !isDark ? Colors.white : null,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
      ),
      child: isMobile
          ? SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(showPrimary ? 'Cancel' : 'Close'),
                    ),
                  ),
                  if (showPrimary) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: saving ? null : onSubmit,
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                primaryLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: Text(showPrimary ? 'Cancel' : 'Close'),
                ),
                if (showPrimary) ...[
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: saving ? null : onSubmit,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            primaryLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ],
            ),
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: content,
                  ),
                ),
                footer,
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: content,
              ),
            ),
            footer,
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _postAndRefresh(
    BuildContext dialogCtx,
    String endpoint,
    Map<String, dynamic> payload, {
    bool closeOnSuccess = true,
  }) async {
    final res = await ApiClient.post(
      Uri.parse('${ApiClient.apiHost}/api/finance/$endpoint'),
      body: jsonEncode(payload),
    );
    final body = jsonDecode(res.body);
    if ((res.statusCode == 200 || res.statusCode == 201) && body['success'] == true) {
      if (closeOnSuccess && dialogCtx.mounted) Navigator.pop(dialogCtx);
      await _loadData();
      widget.onExpenseAdded();
      if (body['message'] != null) _showMsg(body['message'].toString());
      return Map<String, dynamic>.from(body);
    } else {
      throw Exception(body['message'] ?? 'Request failed');
    }
  }

  Future<void> _uploadAttachment(int voucherId, PlatformFile file) async {
    if (file.bytes == null) return;
    final uri = Uri.parse('${ApiClient.apiHost}/api/finance/vouchers/$voucherId/attachment');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(await ApiClient.getMultipartHeaders());
    req.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
    final res = await req.send();
    if (res.statusCode != 201) {
      _showMsg('Expense saved, but bill upload failed.');
    }
  }

  Future<void> _viewAttachment(dynamic item) async {
    final voucherId = item['voucher_id'];
    final name = '${item['attachment_name'] ?? 'bill'}';
    final mime = '${item['attachment_mime'] ?? ''}';
    final url = '${ApiClient.apiHost}/api/finance/vouchers/$voucherId/attachment';

    try {
      final res = await ApiClient.get(Uri.parse(url));
      if (res.statusCode != 200) {
        _showMsg('Could not load attached bill.');
        return;
      }
      if (mime.startsWith('image/') && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(name, style: const TextStyle(fontSize: 15)),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: Image.memory(res.bodyBytes, fit: BoxFit.contain),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      if (kIsWeb) {
        openBytesInNewTab(
          res.bodyBytes,
          mime.isEmpty ? 'application/pdf' : mime,
        );
      }
    } catch (e) {
      _showMsg(e.toString());
    }
  }

  Future<void> _showAddExpenseDialog() async {
    if (_banks.isEmpty || _categories.isEmpty) {
      _showMsg('Bank accounts or expense categories are not loaded yet.');
      return;
    }

    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    int selectedCategoryId = _categories.first['account_id'];
    int selectedBankId = _banks.first['account_id'];
    PlatformFile? pickedBill;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.receipt_long_outlined,
          accentColor: Colors.teal.shade700,
          title: 'Add New Expense',
          subtitle: 'Record a business expense and attach a bill (optional)',
          primaryLabel: 'Save Expense',
          saving: saving,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Expense Title',
                  hint: 'e.g. Office Rent, Electricity Bill',
                  icon: Icons.edit_note_outlined,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: selectedCategoryId,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Expense Category',
                  icon: Icons.category_outlined,
                ),
                items: _categories
                    .map<DropdownMenuItem<int>>(
                      (c) => DropdownMenuItem(
                        value: c['account_id'],
                        child: Text('${c['account_name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedCategoryId = v);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: selectedBankId,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Paid From (Cash / Bank)',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                items: _banks
                    .map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem(
                        value: b['account_id'],
                        child: Text(
                          '${b['account_name']} (₹${_toDouble(b['current_balance']).toStringAsFixed(0)})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedBankId = v);
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Amount (₹)',
                        hint: '0.00',
                        icon: Icons.currency_rupee,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(ctx, dateCtrl),
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: saving
                    ? null
                    : () async {
                        final res = await FilePicker.platform.pickFiles(
                          withData: true,
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
                        );
                        if (res != null && res.files.isNotEmpty) {
                          setDialogState(() => pickedBill = res.files.first);
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, size: 20, color: Colors.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pickedBill == null
                              ? 'Attach Bill (Photo or PDF, max 10MB)'
                              : pickedBill!.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: pickedBill == null ? Colors.grey[700] : Colors.teal.shade800,
                            fontWeight: pickedBill == null ? FontWeight.normal : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (pickedBill != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setDialogState(() => pickedBill = null),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          onSubmit: () async {
            final title = titleCtrl.text.trim();
            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
            if (title.isEmpty || amount <= 0) {
              _showMsg('Please enter a title and a valid amount.');
              return;
            }
            setDialogState(() => saving = true);
            try {
              final resBody = await _postAndRefresh(
                ctx,
                'quick-expenses',
                {
                  'title': title,
                  'expense_account_id': selectedCategoryId,
                  'paid_from_account_id': selectedBankId,
                  'amount': amount,
                  'expense_date': dateCtrl.text.trim(),
                },
                closeOnSuccess: pickedBill == null,
              );
              if (pickedBill != null && resBody['voucher_id'] != null) {
                await _uploadAttachment(resBody['voucher_id'] as int, pickedBill!);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
              }
            } catch (e) {
              setDialogState(() => saving = false);
              _showMsg(e.toString());
            }
          },
        ),
      ),
    );
  }

  Future<void> _showManageCategoriesDialog() async {
    final addCtrl = TextEditingController();
    bool busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.category_outlined,
          accentColor: Colors.deepPurple.shade600,
          title: 'Expense Categories',
          subtitle: 'Add or rename categories like Electricity, Rent, Travel',
          primaryLabel: 'Done',
          saving: busy,
          showPrimary: false,
          onSubmit: () {},
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: addCtrl,
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'New Category Name',
                        hint: 'e.g. Electricity, Travel',
                        icon: Icons.add,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: busy
                        ? null
                        : () async {
                            final name = addCtrl.text.trim();
                            if (name.isEmpty) return;
                            setDialogState(() => busy = true);
                            try {
                              await _postAndRefresh(
                                ctx,
                                'quick-expense-categories',
                                {'account_name': name},
                                closeOnSuccess: false,
                              );
                              addCtrl.clear();
                              setDialogState(() => busy = false);
                            } catch (e) {
                              setDialogState(() => busy = false);
                              _showMsg(e.toString());
                            }
                          },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ..._categories.map(
                (cat) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text('${cat['account_name']}'),
                    subtitle: Text('Code: ${cat['account_code']}'),
                    trailing: IconButton(
                      tooltip: 'Edit Category',
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () async {
                        final editCtrl = TextEditingController(text: '${cat['account_name']}');
                        final updated = await showDialog<String>(
                          context: ctx,
                          builder: (editCtx) => AlertDialog(
                            title: const Text('Rename Category'),
                            content: TextField(
                              controller: editCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Category Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(editCtx),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(editCtx, editCtrl.text.trim()),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (updated != null && updated.isNotEmpty) {
                          final res = await ApiClient.put(
                            Uri.parse('${ApiClient.apiHost}/api/finance/quick-expense-categories/${cat['account_id']}'),
                            body: jsonEncode({'account_name': updated}),
                          );
                          if (res.statusCode == 200) {
                            await _loadData();
                            setDialogState(() {});
                          }
                        }
                      },
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

  Future<void> _showAddMoneyDialog() async {
    if (_banks.isEmpty) {
      _showMsg('Bank accounts are not loaded yet.');
      return;
    }

    final titleCtrl = TextEditingController(text: 'Opening Balance / Deposit');
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    int selectedBankId = _banks.first['account_id'];
    int? selectedSourceId =
        _depositSources.isNotEmpty ? _depositSources.first['account_id'] : null;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.add_circle_outline,
          accentColor: Colors.green.shade700,
          title: 'Add Money / Deposit',
          subtitle: 'Add opening balance, owner capital, or incoming funds',
          primaryLabel: 'Add Money',
          saving: saving,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Description',
                  hint: 'e.g. Owner Capital, Cash Deposit',
                  icon: Icons.edit_note_outlined,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: selectedBankId,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Deposit Into (Cash / Bank)',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                items: _banks
                    .map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem(
                        value: b['account_id'],
                        child: Text('${b['account_name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedBankId = v);
                },
              ),
              if (_depositSources.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: selectedSourceId,
                  decoration: _fieldDecoration(
                    ctx,
                    label: 'Source Account',
                    icon: Icons.savings_outlined,
                  ),
                  items: _depositSources
                      .map<DropdownMenuItem<int>>(
                        (s) => DropdownMenuItem(
                          value: s['account_id'],
                          child: Text('${s['account_name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedSourceId = v);
                  },
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Amount (₹)',
                        hint: '0.00',
                        icon: Icons.currency_rupee,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(ctx, dateCtrl),
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          onSubmit: () async {
            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
            if (amount <= 0) {
              _showMsg('Please enter a valid amount.');
              return;
            }
            setDialogState(() => saving = true);
            try {
              await _postAndRefresh(ctx, 'quick-deposit', {
                'title': titleCtrl.text.trim(),
                'to_account_id': selectedBankId,
                'source_account_id': selectedSourceId,
                'amount': amount,
                'deposit_date': dateCtrl.text.trim(),
              });
            } catch (e) {
              setDialogState(() => saving = false);
              _showMsg(e.toString());
            }
          },
        ),
      ),
    );
  }

  Future<void> _showTransferDialog() async {
    if (_banks.length < 2) {
      _showMsg('At least 2 Cash/Bank accounts are needed for a transfer.');
      return;
    }

    final titleCtrl = TextEditingController(text: 'Cash / Bank Transfer');
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    int fromId = _banks[0]['account_id'];
    int toId = _banks[1]['account_id'];
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.swap_horiz,
          accentColor: Colors.blue.shade700,
          title: 'Transfer Between Accounts',
          subtitle: 'Move funds between Cash in Hand and Bank Accounts',
          primaryLabel: 'Transfer Funds',
          saving: saving,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: fromId,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'From Account',
                  icon: Icons.outbox_outlined,
                ),
                items: _banks
                    .map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem(
                        value: b['account_id'],
                        child: Text(
                          '${b['account_name']} (₹${_toDouble(b['current_balance']).toStringAsFixed(0)})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => fromId = v);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: toId,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'To Account',
                  icon: Icons.move_to_inbox_outlined,
                ),
                items: _banks
                    .map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem(
                        value: b['account_id'],
                        child: Text(
                          '${b['account_name']} (₹${_toDouble(b['current_balance']).toStringAsFixed(0)})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => toId = v);
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Amount (₹)',
                        hint: '0.00',
                        icon: Icons.currency_rupee,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(ctx, dateCtrl),
                      decoration: _fieldDecoration(
                        ctx,
                        label: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Transfer Note',
                  icon: Icons.notes_outlined,
                ),
              ),
            ],
          ),
          onSubmit: () async {
            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
            if (fromId == toId) {
              _showMsg('From and To accounts must be different.');
              return;
            }
            if (amount <= 0) {
              _showMsg('Please enter a valid amount.');
              return;
            }
            setDialogState(() => saving = true);
            try {
              await _postAndRefresh(ctx, 'quick-transfer', {
                'from_account_id': fromId,
                'to_account_id': toId,
                'amount': amount,
                'title': titleCtrl.text.trim(),
                'transfer_date': dateCtrl.text.trim(),
              });
            } catch (e) {
              setDialogState(() => saving = false);
              _showMsg(e.toString());
            }
          },
        ),
      ),
    );
  }

  Future<void> _showAddBankDialog() async {
    final nameCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.account_balance_outlined,
          accentColor: Colors.indigo.shade700,
          title: 'Add Bank Account',
          subtitle: 'Create a new company bank account to track balances',
          primaryLabel: 'Add Bank Account',
          saving: saving,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Bank Name',
                  hint: 'e.g. HDFC Bank Current A/c',
                  icon: Icons.account_balance_outlined,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: openingCtrl,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Opening Balance (₹)',
                  hint: '0.00',
                  icon: Icons.currency_rupee,
                ),
              ),
            ],
          ),
          onSubmit: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              _showMsg('Please enter a bank account name.');
              return;
            }
            setDialogState(() => saving = true);
            try {
              await _postAndRefresh(ctx, 'quick-bank-account', {
                'account_name': name,
                'opening_balance': double.tryParse(openingCtrl.text.trim()) ?? 0,
              });
            } catch (e) {
              setDialogState(() => saving = false);
              _showMsg(e.toString());
            }
          },
        ),
      ),
    );
  }

  Future<void> _cancelTransaction(dynamic item) async {
    final reasonCtrl = TextEditingController();
    bool cancelling = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildStyledDialog(
          ctx,
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.red.shade700,
          title: 'Cancel Entry?',
          subtitle: 'This will reverse the Cash/Bank balance and log your name',
          primaryLabel: 'Confirm Cancel',
          saving: cancelling,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['title'] ?? 'Transaction'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Amount: ₹${_toDouble(item['amount']).toStringAsFixed(2)} • ${item['voucher_no'] ?? ''}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: _fieldDecoration(
                  ctx,
                  label: 'Cancellation Reason *',
                  hint: 'e.g. Entered wrong amount / Duplicate entry',
                  icon: Icons.notes_outlined,
                ),
              ),
            ],
          ),
          onSubmit: () async {
            final reason = reasonCtrl.text.trim();
            if (reason.isEmpty) {
              _showMsg('Cancellation reason is required.');
              return;
            }
            setDialogState(() => cancelling = true);
            try {
              final res = await ApiClient.post(
                Uri.parse('${ApiClient.apiHost}/api/finance/vouchers/${item['voucher_id']}/cancel'),
                body: jsonEncode({'reason': reason}),
              );
              final body = jsonDecode(res.body);
              if (res.statusCode == 200 && body['success'] == true) {
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
                widget.onExpenseAdded();
                _showMsg('Entry cancelled and balance reversed.');
              } else {
                throw Exception(body['message'] ?? 'Could not cancel entry');
              }
            } catch (e) {
              setDialogState(() => cancelling = false);
              _showMsg(e.toString());
            }
          },
        ),
      ),
    );
  }

  List<dynamic> get _filteredTransactions {
    final q = _searchQuery.trim().toLowerCase();
    return _transactions.where((t) {
      final vType = '${t['voucher_type'] ?? 'Payment'}';
      final status = '${t['status'] ?? 'POSTED'}';
      if (_typeFilter == 'CANCELLED') {
        if (status != 'CANCELLED') return false;
      } else if (_typeFilter != 'ALL') {
        if (status == 'CANCELLED' || vType != _typeFilter) return false;
      }
      if (q.isEmpty) return true;
      final hay =
          '${t['title']} ${t['debit_account_name']} ${t['credit_account_name']} ${t['voucher_no']} ${t['cancel_reason'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final totalLiquid = _banks.fold<double>(
      0,
      (sum, b) => sum + _toDouble(b['current_balance']),
    );
    final filtered = _filteredTransactions;
    final isMobile = MediaQuery.of(context).size.width < 600;



    if (isMobile) {
      return Container(
        color: Colors.white,
        child: RefreshIndicator(
          onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            // 1. Hero Total Balance Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Cash + Bank',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_banks.length} Accounts',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '₹${totalLiquid.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (widget.canAddExpense) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFB91C1C),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _showAddExpenseDialog,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            label: const Text(
                              'Add Expense',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _showAddMoneyDialog,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text(
                              'Add Money',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Quick Tools Horizontal Strip
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.canAddExpense) ...[
                    _mobileQuickAction(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Transfer',
                      onTap: _showTransferDialog,
                    ),
                    const SizedBox(width: 8),
                    _mobileQuickAction(
                      icon: Icons.account_balance_outlined,
                      label: 'Add Bank',
                      onTap: _showAddBankDialog,
                    ),
                    const SizedBox(width: 8),
                    _mobileQuickAction(
                      icon: Icons.category_outlined,
                      label: 'Categories',
                      onTap: _showManageCategoriesDialog,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _mobileQuickAction(
                    icon: Icons.bar_chart_rounded,
                    label: 'Reports',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            QuickFinanceReportsPage(bankAccounts: _banks),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Bank Accounts Horizontal Carousel
            if (_banks.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Cash & Bank Accounts',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _banks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final b = _banks[i];
                    final bal = _toDouble(b['current_balance']);
                    return Container(
                      width: 165,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 14,
                                  color: Colors.teal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${b['account_name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '₹${bal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 4. Recent Transactions Header + Search + 1-Line Chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${filtered.length} entries',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search title, account, voucher...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All', 'ALL'),
                  const SizedBox(width: 6),
                  _filterChip('Expenses', 'Payment'),
                  const SizedBox(width: 6),
                  _filterChip('Deposits', 'Receipt'),
                  const SizedBox(width: 6),
                  _filterChip('Transfers', 'Contra'),
                  const SizedBox(width: 6),
                  _filterChip('Cancelled', 'CANCELLED'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No transactions found.')),
                ),
              )
            else
              ...filtered.map(_transactionCard),
          ],
        ),
        ),
      );
    }
    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, isMobile ? 32 : 16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Text(
                'Cash & Bank Balances',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              if (isMobile)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (widget.canAddExpense) ...[
                        SizedBox(

                          child: ElevatedButton.icon(
                            onPressed: _showAddExpenseDialog,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            label: const Text('Add Expense'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(

                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _showAddMoneyDialog,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Add Money'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(

                          child: OutlinedButton.icon(
                            onPressed: _showTransferDialog,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Transfer'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(

                          child: OutlinedButton.icon(
                            onPressed: _showAddBankDialog,
                            icon: const Icon(Icons.account_balance_outlined, size: 18),
                            label: const Text('Add Bank'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(

                          child: OutlinedButton.icon(
                            onPressed: _showManageCategoriesDialog,
                            icon: const Icon(Icons.category_outlined, size: 18),
                            label: const Text('Categories'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      SizedBox(

                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuickFinanceReportsPage(bankAccounts: _banks),
                            ),
                          ),
                          icon: const Icon(Icons.bar_chart_outlined, size: 18),
                          label: const Text('Reports'),
                        ),
                      ),
                    ],
                  ),
                )
              else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.canAddExpense) ...[
                    ElevatedButton.icon(
                      onPressed: _showAddExpenseDialog,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Add Expense'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _showAddMoneyDialog,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Money'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showTransferDialog,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showAddBankDialog,
                      icon: const Icon(Icons.account_balance_outlined),
                      label: const Text('Add Bank'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showManageCategoriesDialog,
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('Categories'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuickFinanceReportsPage(bankAccounts: _banks),
                      ),
                    ),
                    icon: const Icon(Icons.bar_chart_outlined),
                    label: const Text('Reports'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isMobile)
            LayoutBuilder(
              builder: (context, constraints) {
                final halfWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _balanceCard(
                      'Total Cash + Bank',
                      totalLiquid,
                      Colors.indigo,
                      width: constraints.maxWidth,
                    ),
                    ..._banks.map(
                      (b) => _balanceCard(
                        '${b['account_name']}',
                        _toDouble(b['current_balance']),
                        Colors.teal,
                        width: halfWidth,
                      ),
                    ),
                  ],
                );
              },
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _balanceCard('Total Cash + Bank', totalLiquid, Colors.indigo),
                ..._banks.map(
                  (b) => _balanceCard(
                    '${b['account_name']}',
                    _toDouble(b['current_balance']),
                    Colors.teal,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (isMobile) ...[
            const Text(
              'Recent Transactions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: TextField(
                style: const TextStyle(fontSize: 13),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: 'Search title, account, voucher...',
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
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('All', 'ALL'),
                _filterChip('Expenses', 'Payment'),
                _filterChip('Deposits', 'Receipt'),
                _filterChip('Transfers', 'Contra'),
                _filterChip('Cancelled', 'CANCELLED'),
              ],
            ),
          ] else
            Row(
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _filterChip('All', 'ALL'),
                        _filterChip('Expenses', 'Payment'),
                        _filterChip('Deposits', 'Receipt'),
                        _filterChip('Transfers', 'Contra'),
                        _filterChip('Cancelled', 'CANCELLED'),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  height: 36,
                  child: TextField(
                    style: const TextStyle(fontSize: 13),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Search title, account, voucher...',
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
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 23),
          if (filtered.isEmpty)
            Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
                ),
              child: const Center(child: Text('No transactions found.')),
            )
          else
            _buildDesktopTransactionsTable(filtered),
        ],
      ),
      ),
    );
  }

  Widget _mobileQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: Colors.teal.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _typeFilter = value),
    );
  }


  Widget _buildDesktopTransactionsTable(List<dynamic> items) {
    final borderColor = Colors.grey.withValues(alpha: 0.18);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'DATE / VOUCHER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'DESCRIPTION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'ACCOUNT FLOW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'AMOUNT',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: Text(
                    'ACTIONS',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final e = entry.value;
            final vType = '${e['voucher_type'] ?? 'Payment'}';
            final isCancelled = '${e['status']}' == 'CANCELLED';
            final amount = _toDouble(e['amount']).toStringAsFixed(2);
            final isDeposit = vType == 'Receipt';
            final isTransfer = vType == 'Contra';

            final Color color = isCancelled
                ? Colors.grey
                : (isDeposit
                ? Colors.green.shade700
                : (isTransfer
                ? Colors.blue.shade700
                : Colors.red.shade700));
            final IconData icon = isCancelled
                ? Icons.block
                : (isDeposit
                ? Icons.arrow_downward_rounded
                : (isTransfer ? Icons.swap_horiz : Icons.receipt_long));
            final String prefix =
            isCancelled ? '' : (isDeposit ? '+ ' : (isTransfer ? '' : '- '));
            final hasBill = e['attachment_name'] != null;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: idx.isOdd
                    ? Colors.grey.withValues(alpha: 0.025)
                    : Colors.transparent,
                border: idx < items.length - 1
                    ? Border(bottom: BorderSide(color: borderColor))
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Date + Voucher
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e['expense_date'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e['voucher_no'] ?? '-'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Description + Cancelled info
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${e['title'] ?? 'Transaction'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        decoration: isCancelled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (isCancelled) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'CANCELLED',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (isCancelled)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'By ${e['cancelled_by_name'] ?? 'User'} • ${e['cancel_reason'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Account Flow
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${e['debit_account_name'] ?? ''} ← ${e['credit_account_name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),

                  // Amount
                  Expanded(
                    flex: 2,
                    child: Text(
                      '$prefix₹$amount',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        decoration:
                        isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Actions
                  SizedBox(
                    width: 120,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasBill)
                          IconButton(
                            tooltip: 'View Bill (${e['attachment_name']})',
                            icon: const Icon(
                              Icons.attach_file,
                              size: 18,
                              color: Colors.teal,
                            ),
                            onPressed: () => _viewAttachment(e),
                          ),
                        if (widget.canAddExpense && !isCancelled)
                          IconButton(
                            tooltip: 'Cancel Entry',
                            icon: Icon(
                              Icons.cancel_outlined,
                              size: 18,
                              color: Colors.red.shade400,
                            ),
                            onPressed: () => _cancelTransaction(e),
                          ),
                        if (!hasBill && (!widget.canAddExpense || isCancelled))
                          Text(
                            '-',
                            style: TextStyle(color: Colors.grey[400]),
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
    );
  }


  Widget _transactionCard(dynamic e) {
    final vType = '${e['voucher_type'] ?? 'Payment'}';
    final isCancelled = '${e['status']}' == 'CANCELLED';
    final amount = _toDouble(e['amount']).toStringAsFixed(2);
    final isDeposit = vType == 'Receipt';
    final isTransfer = vType == 'Contra';

    final Color color = isCancelled
        ? Colors.grey
        : (isDeposit
            ? Colors.green.shade700
            : (isTransfer ? Colors.blue.shade700 : Colors.red.shade700));
    final IconData icon = isCancelled
        ? Icons.block
        : (isDeposit
            ? Icons.arrow_downward
            : (isTransfer ? Icons.swap_horiz : Icons.receipt_long));
    final String prefix = isCancelled ? '' : (isDeposit ? '+ ' : (isTransfer ? '' : '- '));
    final hasBill = e['attachment_name'] != null;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCancelled
                ? Colors.red.withValues(alpha: 0.25)
                : Colors.grey.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Icon Badge
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),

                // Title & Account Flow
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e['title'] ?? 'Transaction'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${e['debit_account_name'] ?? ''} ← ${e['credit_account_name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right Amount & Date
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$prefix₹$amount',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${e['expense_date'] ?? ''}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Cancelled Reason (if cancelled)
            if (isCancelled) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Cancelled by ${e['cancelled_by_name'] ?? 'User'} • ${e['cancel_reason'] ?? ''}',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 11.5),
                ),
              ),
            ],

            // Bottom Footer: Voucher No + Status + Compact Actions
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.14)),
            const SizedBox(height: 8),
            Row(
              children: [
                if ('${e['voucher_no'] ?? ''}'.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e['voucher_no']}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                if (isCancelled) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'CANCELLED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (hasBill)
                  InkWell(
                    onTap: () => _viewAttachment(e),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file, size: 14, color: Colors.teal),
                          SizedBox(width: 4),
                          Text(
                            'View Bill',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasBill && widget.canAddExpense && !isCancelled)
                  const SizedBox(width: 8),
                if (widget.canAddExpense && !isCancelled)
                  InkWell(
                    onTap: () => _cancelTransaction(e),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
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

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${e['title'] ?? 'Transaction'}',
                style: TextStyle(
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isCancelled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'CANCELLED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${e['expense_date']} • ${e['voucher_no'] ?? ''} • ${e['debit_account_name'] ?? ''} ← ${e['credit_account_name'] ?? ''}',
            ),
            if (isCancelled)
              Text(
                'Cancelled by ${e['cancelled_by_name'] ?? 'User'} on ${e['cancelled_at'] ?? ''} • Reason: ${e['cancel_reason'] ?? ''}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasBill)
              IconButton(
                tooltip: 'View Bill (${e['attachment_name']})',
                icon: const Icon(Icons.attach_file, color: Colors.teal),
                onPressed: () => _viewAttachment(e),
              ),
            Text(
              '$prefix₹$amount',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (widget.canAddExpense && !isCancelled)
              IconButton(
                tooltip: 'Cancel Entry',
                icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
                onPressed: () => _cancelTransaction(e),
              ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(String title, double amount, Color color, {double width = 240}) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
