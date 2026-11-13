import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../../core/widgets/searchable_employee_dropdown.dart';

class SalaryIncrementScreen extends StatefulWidget {
  const SalaryIncrementScreen({super.key});

  @override
  State<SalaryIncrementScreen> createState() => _SalaryIncrementScreenState();
}

class _SalaryIncrementScreenState extends State<SalaryIncrementScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;

  List<dynamic> _employees = [];
  List<dynamic> _history = [];

  // Selected Employee
  dynamic _selectedEmployee;

  // Increment Details
  String _incrementType = 'PERCENTAGE'; // 'PERCENTAGE' or 'FIXED'
  final _percentageController = TextEditingController(text: '20');
  final _fixedAmountController = TextEditingController(text: '5000');
  final _reasonController = TextEditingController(text: 'Annual Performance Review');
  final _newDesignationController = TextEditingController();
  final _newGradeController = TextEditingController();
  DateTime _effectiveDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchEmployeesAndHistory();

    // Auto calculate amount when percentage changes
    _percentageController.addListener(_onPercentageChanged);
    // Auto calculate percentage when fixed amount changes
    _fixedAmountController.addListener(_onFixedAmountChanged);
  }

  @override
  void dispose() {
    _percentageController.dispose();
    _fixedAmountController.dispose();
    _reasonController.dispose();
    _newDesignationController.dispose();
    _newGradeController.dispose();
    super.dispose();
  }

  bool _isUpdatingInternally = false;

  void _onPercentageChanged() {
    if (_incrementType != 'PERCENTAGE' || _isUpdatingInternally) return;
    final currentSalary = _currentSalary;
    final pct = double.tryParse(_percentageController.text.trim()) ?? 0.0;
    if (currentSalary > 0) {
      _isUpdatingInternally = true;
      final amount = (currentSalary * (pct / 100.0)).roundToDouble();
      _fixedAmountController.text = amount.toStringAsFixed(0);
      _isUpdatingInternally = false;
      setState(() {});
    }
  }

  void _onFixedAmountChanged() {
    if (_incrementType != 'FIXED' || _isUpdatingInternally) return;
    final currentSalary = _currentSalary;
    final amount = double.tryParse(_fixedAmountController.text.trim()) ?? 0.0;
    if (currentSalary > 0) {
      _isUpdatingInternally = true;
      final pct = ((amount / currentSalary) * 100.0);
      _percentageController.text = pct.toStringAsFixed(1);
      _isUpdatingInternally = false;
      setState(() {});
    }
  }

  double get _currentSalary {
    if (_selectedEmployee == null) return 0.0;
    final val = _selectedEmployee['salary_base'];
    if (val == null) return 0.0;
    return double.tryParse(val.toString()) ?? 0.0;
  }

  double get _incrementAmount {
    if (_incrementType == 'PERCENTAGE') {
      final pct = double.tryParse(_percentageController.text.trim()) ?? 0.0;
      return (_currentSalary * (pct / 100.0));
    } else {
      return double.tryParse(_fixedAmountController.text.trim()) ?? 0.0;
    }
  }

  double get _revisedSalary => _currentSalary + _incrementAmount;

  double get _revisedDailyDeduction => _revisedSalary / 30.0;

  Future<void> _fetchEmployeesAndHistory() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Employees
      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final data = jsonDecode(empRes.body);
        _employees = data['data'] ?? [];
        if (_employees.isNotEmpty) {
          _selectedEmployee = _employees.first;
          _newDesignationController.text = _selectedEmployee['designation'] ?? '';
          _newGradeController.text = _selectedEmployee['salary_grade'] ?? 'Grade B';
          _recalcCalculations();
        }
      }

      // 2. Fetch Increments History
      final histRes = await http.get(Uri.parse('http://localhost:5000/api/hr/increments'));
      if (histRes.statusCode == 200) {
        final data = jsonDecode(histRes.body);
        _history = data['data'] ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _recalcCalculations() {
    _isUpdatingInternally = true;
    final current = _currentSalary;
    if (_incrementType == 'PERCENTAGE') {
      final pct = double.tryParse(_percentageController.text.trim()) ?? 20.0;
      _fixedAmountController.text = (current * (pct / 100.0)).toStringAsFixed(0);
    } else {
      final amt = double.tryParse(_fixedAmountController.text.trim()) ?? 5000.0;
      _percentageController.text = current > 0 ? ((amt / current) * 100.0).toStringAsFixed(1) : '0';
    }
    _isUpdatingInternally = false;
    setState(() {});
  }

  String _formatDateDb(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _formatDateDisplay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}";
  }

  Future<void> _saveIncrement() async {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an employee!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_incrementAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Increment amount must be greater than ₹0!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final payload = {
        'company_id': 1,
        'employee_id': _selectedEmployee['employee_id'],
        'increment_type': _incrementType,
        'increment_value': _incrementType == 'PERCENTAGE'
            ? double.tryParse(_percentageController.text.trim()) ?? 0.0
            : double.tryParse(_fixedAmountController.text.trim()) ?? 0.0,
        'increment_amount': _incrementAmount,
        'previous_salary': _currentSalary,
        'revised_salary': _revisedSalary,
        'new_designation': _newDesignationController.text.trim(),
        'new_salary_grade': _newGradeController.text.trim(),
        'effective_date': _formatDateDb(_effectiveDate),
        'reason': _reasonController.text.trim(),
        'approved_by': 1,
      };

      final res = await http.post(
        Uri.parse('http://localhost:5000/api/hr/increments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 201 || resData['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('Salary increment of ₹${_incrementAmount.toStringAsFixed(0)} successfully saved!'),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        _fetchEmployeesAndHistory();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resData['message'] ?? 'Failed to save increment.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final headerBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar Header
              _buildTopBar(headerBg, textColor, subtextColor, isDark),

              // Form & Details View
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                    : Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 800;
                      return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: isMobile ? 14 : 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1050),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isMobile) ...[
                              // Mobile: Single-Column Stack
                              _buildEmployeeInfoCard(isDark),
                              const SizedBox(height: 16),
                              _buildCurrentSalaryCard(isDark),
                              const SizedBox(height: 16),
                              _buildIncrementDetailsCard(isDark),
                              const SizedBox(height: 16),
                              _buildNewSalaryPreviewCard(isDark),
                            ] else ...[
                              // Desktop: 2-Column Side-by-Side Grid
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: _buildEmployeeInfoCard(isDark)),
                                  const SizedBox(width: 18),
                                  Expanded(flex: 2, child: _buildCurrentSalaryCard(isDark)),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: _buildIncrementDetailsCard(isDark)),
                                  const SizedBox(width: 18),
                                  Expanded(flex: 2, child: _buildNewSalaryPreviewCard(isDark)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),

                            // Bottom Save Action
                            _buildSaveActionButton(isDark),
                            const SizedBox(height: 32),

                            // Increment History List
                            _buildIncrementHistorySection(isDark),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= TOP BAR =================
  Widget _buildTopBar(Color bg, Color textColor, Color subtextColor, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 8 : 12),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Color(0xFF8B5CF6)),
                tooltip: 'Back to Dashboard',
                padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),
                constraints: isMobile ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
              ),
              const SizedBox(width: 6),
              if (!isMobile) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Color(0xFF8B5CF6), size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Salary Increment',
                      style: TextStyle(
                        color: textColor,
                        fontSize: isMobile ? 16 : 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isMobile)
                      Text(
                        'New Increment • Update employee compensation details & salary hike',
                        style: TextStyle(color: subtextColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveIncrement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 8 : 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                icon: _isSaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: Text(
                  _isSaving ? 'Saving...' : (isMobile ? 'Save' : 'Save Increment'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================= 1. EMPLOYEE INFORMATION CARD =================
  Widget _buildEmployeeInfoCard(bool isDark) {
    final emp = _selectedEmployee;
    return _buildCardWrapper(
      title: 'Employee Information',
      icon: Icons.person_outline_rounded,
      accentColor: const Color(0xFF3B82F6),
      isDark: isDark,
      children: [
        _buildLabel('Select Employee', isDark),
        const SizedBox(height: 6),
        SearchableEmployeeDropdown(
          employees: _employees,
          selectedEmployeeId: emp != null ? emp['employee_id'] : null,
          onChanged: (found) {
            setState(() {
              _selectedEmployee = found;
              _newDesignationController.text = found['designation'] ?? '';
              _newGradeController.text = found['salary_grade'] ?? 'Grade B';
              _recalcCalculations();
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildInfoItem('Employee ID', emp != null ? (emp['emp_code'] ?? 'N/A') : '-', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _buildInfoItem('Employee Name', emp != null ? (emp['full_name'] ?? 'N/A') : '-', isDark)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildInfoItem('Department', emp != null ? (emp['department_name'] ?? 'General') : 'Development', isDark)),
            const SizedBox(width: 12),
            Expanded(child: _buildInfoItem('Designation', emp != null ? (emp['designation'] ?? 'Staff') : 'Flutter Developer', isDark)),
          ],
        ),
      ],
    );
  }

  // ================= 2. CURRENT SALARY DETAILS CARD =================
  Widget _buildCurrentSalaryCard(bool isDark) {
    final curSal = _currentSalary;
    final curAnnual = curSal * 12;
    final curDaily = curSal / 30.0;

    return _buildCardWrapper(
      title: 'Current Salary Details',
      icon: Icons.account_balance_wallet_outlined,
      accentColor: const Color(0xFF059669),
      isDark: isDark,
      children: [
        _buildStatBox(
          title: 'Current Monthly Salary',
          value: '₹${curSal.toStringAsFixed(0)}',
          color: const Color(0xFF059669),
          icon: Icons.currency_rupee,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _buildStatBox(
          title: 'Annual CTC (12 Months)',
          value: '₹${curAnnual.toStringAsFixed(0)}',
          color: const Color(0xFF0284C7),
          icon: Icons.calendar_month_outlined,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _buildStatBox(
          title: 'Unpaid Leave Cut (Per Day)',
          value: '₹${curDaily.toStringAsFixed(2)} / day',
          color: const Color(0xFFEA580C),
          icon: Icons.event_busy_outlined,
          isDark: isDark,
        ),
      ],
    );
  }

  // ================= 3. INCREMENT DETAILS CARD =================
  Widget _buildIncrementDetailsCard(bool isDark) {
    return _buildCardWrapper(
      title: 'Increment Details',
      icon: Icons.tune_rounded,
      accentColor: const Color(0xFFD80553),
      isDark: isDark,
      children: [
        _buildLabel('Increment Type', isDark),
        Row(
          children: [
            Expanded(
              child: _buildTypeToggleOption(
                label: 'Percentage (%)',
                typeKey: 'PERCENTAGE',
                icon: Icons.percent,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeToggleOption(
                label: 'Fixed Amount (₹)',
                typeKey: 'FIXED',
                icon: Icons.currency_rupee,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, fieldConstraints) {
            final isTight = fieldConstraints.maxWidth < 480;
            final pctCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel(_incrementType == 'PERCENTAGE' ? 'Increment Percentage (%) *' : 'Increment Percentage (Auto)', isDark),
                TextFormField(
                  controller: _percentageController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  enabled: _incrementType == 'PERCENTAGE',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _inputDecoration('e.g. 20', Icons.percent, isDark),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            );

            final amtCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel(_incrementType == 'FIXED' ? 'Increment Amount (₹) *' : 'Increment Amount (Auto)', isDark),
                TextFormField(
                  controller: _fixedAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  enabled: _incrementType == 'FIXED',
                  style: const TextStyle(
                    color: Color(0xE8141025),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _inputDecoration('e.g. 5000', Icons.currency_rupee, isDark),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            );

            if (isTight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pctCol,
                  const SizedBox(height: 14),
                  amtCol,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: pctCol),
                const SizedBox(width: 14),
                Expanded(child: amtCol),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _buildLabel('Effective From (New Salary Start Date) *', isDark),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _effectiveDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) setState(() => _effectiveDate = picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: Color(0xFF8B5CF6), size: 18),
                const SizedBox(width: 10),
                Text(
                  _formatDateDisplay(_effectiveDate),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLabel('Reason for Increment', isDark),
        TextFormField(
          controller: _reasonController,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: _inputDecoration('e.g. Annual Performance Review', Icons.rate_review_outlined, isDark),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildReasonChip('Annual Performance Review', isDark),
            _buildReasonChip('Promotion Hike', isDark),
            _buildReasonChip('Market Correction', isDark),
            _buildReasonChip('Probation Clearance', isDark),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, fieldConstraints) {
            final isTight = fieldConstraints.maxWidth < 480;

            final desigCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Promote to Designation (Optional)', isDark),
                TextFormField(
                  controller: _newDesignationController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                  decoration: _inputDecoration('e.g. Senior Flutter Developer', Icons.military_tech_outlined, isDark),
                ),
              ],
            );

            final gradeCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Salary Grade (Optional)', isDark),
                TextFormField(
                  controller: _newGradeController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                  decoration: _inputDecoration('e.g. Grade A', Icons.grade_outlined, isDark),
                ),
              ],
            );

            if (isTight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  desigCol,
                  const SizedBox(height: 14),
                  gradeCol,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: desigCol),
                const SizedBox(width: 14),
                Expanded(child: gradeCol),
              ],
            );
          },
        ),
      ],
    );
  }

  // ================= 4. NEW SALARY PREVIEW CARD =================
  Widget _buildNewSalaryPreviewCard(bool isDark) {
    final curSal = _currentSalary;
    final incAmt = _incrementAmount;
    final revSal = _revisedSalary;
    final revAnnual = revSal * 12;
    final revDaily = _revisedDailyDeduction;
    final pctHike = curSal > 0 ? ((incAmt / curSal) * 100).toStringAsFixed(1) : '0';

    return _buildCardWrapper(
      title: 'New Salary Preview',
      icon: Icons.insights_rounded,
      accentColor: const Color(0xFF10B981),
      isDark: isDark,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Increment Amount', style: TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('Additional hike applied', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
              Text(
                '+₹${incAmt.toStringAsFixed(0)} (+$pctHike%)',
                style: const TextStyle(color: Color(0xFF059669), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF03C3BD).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF03C3BD).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revised Monthly Salary', style: TextStyle(color: Color(
                  0xFF09CDAB), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${revSal.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF09CDAB), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'was ₹${curSal.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.lineThrough),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildPreviewRow('Revised Annual CTC', '₹${revAnnual.toStringAsFixed(0)}', isDark),
        const SizedBox(height: 8),
        _buildPreviewRow('New Daily Leave Cut', '₹${revDaily.toStringAsFixed(2)} / day', isDark),
        const Divider(height: 20),
        Text(
          '• Daily unpaid leave deduction is auto-synced to ₹${revDaily.toStringAsFixed(2)} based on the new base salary.',
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11, height: 1.3),
        ),
      ],
    );
  }

  // ================= 5. SAVE ACTION BUTTON =================
  Widget _buildSaveActionButton(bool isDark) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveIncrement,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8B5CF6),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        icon: _isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_circle_rounded, size: 20),
        label: Text(
          _isSaving ? 'Processing Increment...' : 'Save & Apply Increment',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  // ================= 6. RECENT INCREMENTS HISTORY =================
  Widget _buildIncrementHistorySection(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, color: Color(0xFF8B5CF6), size: 20),
            const SizedBox(width: 8),
            Text(
              'Recent Salary Increments History',
              style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text('${_history.length} Records', style: TextStyle(color: textSub, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: const Center(
              child: Text('No salary increments recorded yet. Apply an increment above to start tracking history.'),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final item = _history[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      child: const Icon(Icons.trending_up, color: Color(0xFF8B5CF6), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(item['full_name'] ?? 'Staff', style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(item['emp_code'] ?? 'EMP', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Reason: "${item['reason'] ?? 'Annual Appraisal'}" • Effective: ${item['effective_date']?.toString().split('T')[0] ?? 'N/A'}',
                            style: TextStyle(color: textSub, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${item['revised_salary']}',
                          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          '+₹${item['increment_amount']} (+${item['increment_value']}%)',
                          style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ================= UI HELPERS =================
  Widget _buildTypeToggleOption({
    required String label,
    required String typeKey,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _incrementType == typeKey;
    final activeColor = const Color(0xC8AA0732);

    return InkWell(
      onTap: () {
        setState(() {
          _incrementType = typeKey;
          _recalcCalculations();
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? activeColor : (isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonChip(String text, bool isDark) {
    return InkWell(
      onTap: () => setState(() => _reasonController.text = text),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xC8AA0732).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xC8AA0732).withValues(alpha: 0.25)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xC8AA0732), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCardWrapper({
    required String title,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    required List<Widget> children,
  }) {
    final cardBg = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.95);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 11.5)),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Icon(icon, color: color, size: 22),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String title, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
        Text(
          value,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
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
          color: isDark ? Colors.white70 : const Color(0xFF334155),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF8B5CF6), size: 18),
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5)),
    );
  }
}