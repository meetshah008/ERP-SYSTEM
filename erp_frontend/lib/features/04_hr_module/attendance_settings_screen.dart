import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/enterprise_theme.dart';
import '../../core/theme/theme_controller.dart';

class AttendanceSettingsScreen extends StatefulWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  State<AttendanceSettingsScreen> createState() => _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen> {
  static String get _apiHost => ApiClient.apiHost;

  bool _isLoading = true;
  bool _isSaving = false;

  // 1. Shift & Auto Absent/Present
  final _shiftStartCtrl = TextEditingController(text: '09:00');
  final _shiftEndCtrl = TextEditingController(text: '18:00');
  final _graceMinsCtrl = TextEditingController(text: '30');
  String _noPunchDefaultStatus = 'Absent';

  // 2. Late Mark Rule
  bool _enableWarningQuota = true;
  final _warningLimitCtrl = TextEditingController(text: '3');
  String _latePenaltyAction = 'Half-Day';

  // 3. Half Day / Full Day & Missing Out-Punch
  final _fullDayHoursCtrl = TextEditingController(text: '8');
  final _halfDayHoursCtrl = TextEditingController(text: '4');
  String _missingOutStatus = 'Missing';

  // 4. Early Going Rule
  bool _enableEarlyGoing = true;
  final _earlyGraceCtrl = TextEditingController(text: '15');
  String _earlyGoingAction = 'Half-Day';

  // 5. Overtime (OT) Rule
  bool _enableAutoOvertime = true;
  final _otBufferCtrl = TextEditingController(text: '30');
  final _otMultiplierCtrl = TextEditingController(text: '1.5');
  final _otFixedRateCtrl = TextEditingController(text: '0');

  // 6. Leave & Payroll Integration
  bool _enableLeaveIntegration = true;
  bool _autoSyncPayrollDeduction = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _shiftStartCtrl.dispose();
    _shiftEndCtrl.dispose();
    _graceMinsCtrl.dispose();
    _warningLimitCtrl.dispose();
    _fullDayHoursCtrl.dispose();
    _halfDayHoursCtrl.dispose();
    _earlyGraceCtrl.dispose();
    _otBufferCtrl.dispose();
    _otMultiplierCtrl.dispose();
    _otFixedRateCtrl.dispose();
    super.dispose();
  }

  String _formatHours(dynamic minutesVal, String fallback) {
    final mins = int.tryParse((minutesVal ?? '').toString());
    if (mins == null || mins <= 0) return fallback;
    return (mins / 60).toStringAsFixed(mins % 60 == 0 ? 0 : 1);
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.get(Uri.parse('$_apiHost/api/hr/attendance-settings'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          final s = data['data'];
          _shiftStartCtrl.text = (s['shift_start'] ?? '09:00').toString();
          _shiftEndCtrl.text = (s['shift_end'] ?? '18:00').toString();
          _graceMinsCtrl.text = (s['grace_minutes'] ?? 30).toString();
          _noPunchDefaultStatus = (s['no_punch_default_status'] ?? 'Absent').toString();

          _enableWarningQuota = (s['enable_late_warning_quota'] ?? 1) == 1;
          _warningLimitCtrl.text = (s['late_warning_limit'] ?? 3).toString();
          _latePenaltyAction = (s['late_penalty_action'] ?? 'Half-Day').toString();

          _fullDayHoursCtrl.text = _formatHours(s['full_day_minutes'], '8');
          _halfDayHoursCtrl.text = _formatHours(s['half_day_minutes'], '4');
          _missingOutStatus = (s['missing_out_punch_status'] ?? 'Missing').toString();

          _enableEarlyGoing = (s['enable_early_going_rule'] ?? 1) == 1;
          _earlyGraceCtrl.text = (s['early_going_grace_minutes'] ?? 15).toString();
          _earlyGoingAction = (s['early_going_action'] ?? 'Half-Day').toString();

          _enableAutoOvertime = (s['enable_auto_overtime'] ?? 1) == 1;
          _otBufferCtrl.text = (s['overtime_buffer_minutes'] ?? 30).toString();
          _otMultiplierCtrl.text = (s['overtime_rate_multiplier'] ?? 1.5).toString();
          _otFixedRateCtrl.text = (s['overtime_fixed_hourly_rate'] ?? 0).toString();

          _enableLeaveIntegration = (s['enable_leave_integration'] ?? 1) == 1;
          _autoSyncPayrollDeduction = (s['auto_sync_payroll_deduction'] ?? 1) == 1;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final fullHours = double.tryParse(_fullDayHoursCtrl.text.trim()) ?? 8.0;
      final halfHours = double.tryParse(_halfDayHoursCtrl.text.trim()) ?? 4.0;
      final res = await ApiClient.post(
        Uri.parse('$_apiHost/api/hr/attendance-settings'),
        body: jsonEncode({
          'shift_start': _shiftStartCtrl.text.trim(),
          'shift_end': _shiftEndCtrl.text.trim(),
          'grace_minutes': int.tryParse(_graceMinsCtrl.text.trim()) ?? 30,
          'no_punch_default_status': _noPunchDefaultStatus,
          'enable_late_warning_quota': _enableWarningQuota ? 1 : 0,
          'late_warning_limit': int.tryParse(_warningLimitCtrl.text.trim()) ?? 3,
          'late_penalty_action': _latePenaltyAction,
          'full_day_minutes': (fullHours * 60).round(),
          'half_day_minutes': (halfHours * 60).round(),
          'missing_out_punch_status': _missingOutStatus,
          'enable_early_going_rule': _enableEarlyGoing ? 1 : 0,
          'early_going_grace_minutes': int.tryParse(_earlyGraceCtrl.text.trim()) ?? 15,
          'early_going_action': _earlyGoingAction,
          'enable_auto_overtime': _enableAutoOvertime ? 1 : 0,
          'overtime_buffer_minutes': int.tryParse(_otBufferCtrl.text.trim()) ?? 30,
          'overtime_rate_multiplier': double.tryParse(_otMultiplierCtrl.text.trim()) ?? 1.5,
          'overtime_fixed_hourly_rate': double.tryParse(_otFixedRateCtrl.text.trim()) ?? 0.0,
          'enable_leave_integration': _enableLeaveIntegration ? 1 : 0,
          'auto_sync_payroll_deduction': _autoSyncPayrollDeduction ? 1 : 0,
          'recalculate': true,
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Settings saved!'),
            backgroundColor: res.statusCode == 200 ? EnterpriseColors.emerald : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        final bg = isDark ? const Color(0xFF0B1120) : EnterpriseColors.canvas;
        final cardBg = isDark ? const Color(0xFF111827) : EnterpriseColors.surface;
        final borderColor = isDark ? Colors.white12 : EnterpriseColors.border;
        final textTitle = isDark ? Colors.white : EnterpriseColors.textPrimary;
        final textSub = isDark ? Colors.white60 : EnterpriseColors.textSecondary;

        final isMobile = MediaQuery.sizeOf(context).width < 650;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: Text(
              'Attendance Setting & Rules',
              style: TextStyle(color: textTitle, fontWeight: FontWeight.w700, fontSize: isMobile ? 15.5 : 17),
            ),
            backgroundColor: cardBg,
            foregroundColor: textTitle,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: borderColor),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: EnterpriseColors.emerald))
              : SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 14 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. SHIFT & AUTO ABSENT / PRESENT
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '1. Shift Timings & Auto Absent / Present',
                            subtitle: 'Configure office shift timings and default status when no punch is recorded.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: _responsiveFields(
                              isMobile: isMobile,
                              children: [
                                _field('Shift Start (HH:mm)', _shiftStartCtrl, textTitle, borderColor),
                                _field('Shift End (HH:mm)', _shiftEndCtrl, textTitle, borderColor),
                                _field('Grace Minutes', _graceMinsCtrl, textTitle, borderColor, isNumber: true),
                                _dropdown(
                                  label: 'No Punch Rule',
                                  value: _noPunchDefaultStatus,
                                  items: const ['Absent', 'Present'],
                                  cardBg: cardBg,
                                  textTitle: textTitle,
                                  textSub: textSub,
                                  borderColor: borderColor,
                                  onChanged: (v) => setState(() => _noPunchDefaultStatus = v ?? 'Absent'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. LATE MARK RULE
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '2. Late Mark Rule & Warning Quota',
                            subtitle: 'Set monthly late warning allowances after grace time and the penalty once exhausted.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: EnterpriseColors.emerald,
                                  title: Text(
                                    'Enable Late Warning Quota -> Half-Day / Short Leave',
                                    style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'After exhausting allowed warnings (e.g. 3 lates), further lates will count as Half-Day or Short Leave.',
                                    style: TextStyle(color: textSub, fontSize: 12),
                                  ),
                                  value: _enableWarningQuota,
                                  onChanged: (v) => setState(() => _enableWarningQuota = v ?? true),
                                ),
                                if (_enableWarningQuota) ...[
                                  const SizedBox(height: 10),
                                  _responsiveFields(
                                    isMobile: isMobile,
                                    children: [
                                      _field('Allowed Warnings / Month (e.g. 3 or 4)', _warningLimitCtrl, textTitle, borderColor, isNumber: true),
                                      _dropdown(
                                        label: 'Action After Quota Ends',
                                        value: _latePenaltyAction,
                                        items: const ['Half-Day', 'Short Leave'],
                                        cardBg: cardBg,
                                        textTitle: textTitle,
                                        textSub: textSub,
                                        borderColor: borderColor,
                                        onChanged: (v) => setState(() => _latePenaltyAction = v ?? 'Half-Day'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3. HALF DAY / FULL DAY & MISSING OUT-PUNCH
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '3. Half-Day / Full-Day & Missing Punch Rules',
                            subtitle: 'Configure minimum working hours for Full-Day/Half-Day and missing out-punch behavior.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: _responsiveFields(
                              isMobile: isMobile,
                              children: [
                                _field('Full Day Min Hours (e.g. 8)', _fullDayHoursCtrl, textTitle, borderColor, isNumber: true),
                                _field('Half Day Min Hours (e.g. 4)', _halfDayHoursCtrl, textTitle, borderColor, isNumber: true),
                                _dropdown(
                                  label: 'Missing Out-Punch Rule',
                                  value: _missingOutStatus,
                                  items: const ['Missing', 'Half-Day', 'Absent', 'Present'],
                                  cardBg: cardBg,
                                  textTitle: textTitle,
                                  textSub: textSub,
                                  borderColor: borderColor,
                                  onChanged: (v) => setState(() => _missingOutStatus = v ?? 'Missing'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4. EARLY GOING RULE
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '4. Early Going Rule',
                            subtitle: 'Configure action when an employee leaves before the shift end time.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: EnterpriseColors.emerald,
                                  title: Text(
                                    'Enable Early Going Check',
                                    style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  value: _enableEarlyGoing,
                                  onChanged: (v) => setState(() => _enableEarlyGoing = v ?? true),
                                ),
                                if (_enableEarlyGoing) ...[
                                  const SizedBox(height: 10),
                                  _responsiveFields(
                                    isMobile: isMobile,
                                    children: [
                                      _field('Early Grace Minutes (before Shift End)', _earlyGraceCtrl, textTitle, borderColor, isNumber: true),
                                      _dropdown(
                                        label: 'Early Going Action',
                                        value: _earlyGoingAction,
                                        items: const ['Half-Day', 'Late', 'Ignore'],
                                        cardBg: cardBg,
                                        textTitle: textTitle,
                                        textSub: textSub,
                                        borderColor: borderColor,
                                        onChanged: (v) => setState(() => _earlyGoingAction = v ?? 'Half-Day'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 5. OVERTIME (OT) RULE
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '5. Overtime (OT) Rule & Rate',
                            subtitle: 'Configure overtime start buffer and hourly pay rate multiplier after shift end.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: EnterpriseColors.emerald,
                                  title: Text(
                                    'Auto-Calculate Overtime (OT)',
                                    style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  value: _enableAutoOvertime,
                                  onChanged: (v) => setState(() => _enableAutoOvertime = v ?? true),
                                ),
                                if (_enableAutoOvertime) ...[
                                  const SizedBox(height: 10),
                                  _responsiveFields(
                                    isMobile: isMobile,
                                    children: [
                                      _field('OT Buffer Minutes', _otBufferCtrl, textTitle, borderColor, isNumber: true),
                                      _field('OT Multiplier (e.g. 1.5x)', _otMultiplierCtrl, textTitle, borderColor, isNumber: true),
                                      _field('Fixed OT Rate (₹/hr, 0 = Auto)', _otFixedRateCtrl, textTitle, borderColor, isNumber: true),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 6. LEAVE & PAYROLL INTEGRATION
                          _sectionCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            title: '6. Leave Balance & Payroll Integration',
                            subtitle: 'Connect approved leaves with attendance and sync absences/half-days with payroll deductions.',
                            textTitle: textTitle,
                            textSub: textSub,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: EnterpriseColors.emerald,
                                  title: Text(
                                    'Sync Approved Leaves with Biometric Logs ("On Leave")',
                                    style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'Approved leave days will automatically show as "On Leave" instead of Absent.',
                                    style: TextStyle(color: textSub, fontSize: 12),
                                  ),
                                  value: _enableLeaveIntegration,
                                  onChanged: (v) => setState(() => _enableLeaveIntegration = v ?? true),
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: EnterpriseColors.emerald,
                                  title: Text(
                                    'Auto-Sync Attendance Deductions to Employee Payroll',
                                    style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'Automatically update monthly salary deductions based on Absent and Half-Day counts.',
                                    style: TextStyle(color: textSub, fontSize: 12),
                                  ),
                                  value: _autoSyncPayrollDeduction,
                                  onChanged: (v) => setState(() => _autoSyncPayrollDeduction = v ?? true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveSettings,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: EnterpriseColors.emerald,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(EnterpriseRadius.md),
                                ),
                              ),
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 18),
                              label: const Text(
                                'Save All Rules & Recalculate Biometric Logs',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
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
    );
  }

  Widget _sectionCard({
    required Color cardBg,
    required Color borderColor,
    required String title,
    required String subtitle,
    required Color textTitle,
    required Color textSub,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: EnterpriseTheme.card(
        color: cardBg,
        borderColor: borderColor,
        radius: EnterpriseRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: textSub, fontSize: 12)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required Color cardBg,
    required Color textTitle,
    required Color textSub,
    required Color borderColor,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      dropdownColor: cardBg,
      style: TextStyle(color: textTitle, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textSub),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(EnterpriseRadius.md)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadius.md),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    Color textColor,
    Color borderColor, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(EnterpriseRadius.md)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadius.md),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadius.md),
          borderSide: const BorderSide(color: EnterpriseColors.emerald, width: 1.5),
        ),
      ),
    );
  }

  Widget _responsiveFields({required bool isMobile, required List<Widget> children}) {
    if (isMobile) {
      return Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
