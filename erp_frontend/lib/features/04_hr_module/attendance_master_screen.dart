import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_client.dart';
import '../../core/theme/enterprise_theme.dart';
import '../../core/theme/theme_controller.dart';

class AttendanceMasterScreen extends StatefulWidget {
  const AttendanceMasterScreen({super.key});

  @override
  State<AttendanceMasterScreen> createState() => _AttendanceMasterScreenState();
}

class _AttendanceMasterScreenState extends State<AttendanceMasterScreen> {
  static String get _apiHost => ApiClient.apiHost;

  bool _isLoading = true;
  bool _isImporting = false;

  List<dynamic> _holidays = [];
  // Other masters kept commented for future activation:
  // List<dynamic> _statuses = [];
  // List<dynamic> _shifts = [];
  // List<dynamic> _weeklyOffs = [];
  // List<dynamic> _leaveTypes = [];
  // List<dynamic> _devices = [];

  String _selectedYear = DateTime.now().year.toString();
  String _selectedTypeFilter = 'All';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchHolidays();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchHolidays() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.get(Uri.parse('$_apiHost/api/hr/attendance-master'));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['data'] != null) {
          final d = json['data'];
          _holidays = d['holidays'] ?? [];
          // _statuses = d['statuses'] ?? [];
          // _shifts = d['shifts'] ?? [];
          // _weeklyOffs = d['weeklyOffs'] ?? [];
          // _leaveTypes = d['leaveTypes'] ?? [];
          // _devices = d['devices'] ?? [];
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _addHoliday(String name, String dateStr, String type) async {
    try {
      final res = await ApiClient.post(
        Uri.parse('$_apiHost/api/hr/attendance-master/holiday'),
        body: jsonEncode({
          'holiday_name': name,
          'holiday_date': dateStr,
          'holiday_type': type,
        }),
      );
      if (res.statusCode == 201) {
        _showToast('Holiday added successfully!');
        await _fetchHolidays();
      }
    } catch (e) {
      _showToast('Failed to add holiday: $e', isError: true);
    }
  }

  Future<void> _bulkAddHolidays(List<Map<String, String>> items) async {
    setState(() => _isImporting = true);
    try {
      final res = await ApiClient.post(
        Uri.parse('$_apiHost/api/hr/attendance-master/holiday/bulk'),
        body: jsonEncode({'holidays': items}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 201 || res.statusCode == 200) {
        _showToast(data['message'] ?? 'Holidays imported!');
        await _fetchHolidays();
      } else {
        _showToast(data['message'] ?? 'Import failed', isError: true);
      }
    } catch (e) {
      _showToast('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isImporting = false);
  }

  Future<void> _importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _isImporting = true);
    try {
      final uri = Uri.parse('$_apiHost/api/hr/attendance-master/holiday/import');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await ApiClient.getMultipartHeaders());
      request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body);

      if (streamed.statusCode == 201 || streamed.statusCode == 200) {
        _showToast(data['message'] ?? 'Excel imported successfully!');
        await _fetchHolidays();
      } else {
        _showToast(data['message'] ?? 'Excel import failed', isError: true);
      }
    } catch (e) {
      _showToast('Import error: $e', isError: true);
    }
    if (mounted) setState(() => _isImporting = false);
  }

  Future<void> _deleteHoliday(dynamic id) async {
    try {
      final res = await ApiClient.delete(Uri.parse('$_apiHost/api/hr/attendance-master/holiday/$id'));
      if (res.statusCode == 200) {
        _showToast('Holiday removed.');
        await _fetchHolidays();
      }
    } catch (_) {}
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : EnterpriseColors.emerald,
      ),
    );
  }

  List<dynamic> get _filteredHolidays {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _holidays.where((h) {
      final dateStr = (h['holiday_date'] ?? '').toString();
      final name = (h['holiday_name'] ?? '').toString().toLowerCase();
      final type = (h['holiday_type'] ?? 'Public Holiday').toString();

      if (_selectedYear != 'All' && !dateStr.startsWith(_selectedYear)) return false;
      if (_selectedTypeFilter != 'All' && type != _selectedTypeFilter) return false;
      if (q.isNotEmpty && !name.contains(q) && !dateStr.contains(q)) return false;
      return true;
    }).toList();
  }

  Map<String, dynamic>? get _nextUpcomingHoliday {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    for (final h in _holidays) {
      final d = (h['holiday_date'] ?? '').toString();
      if (d.compareTo(todayStr) >= 0) return Map<String, dynamic>.from(h);
    }
    return null;
  }

  List<Map<String, String>> _indiaPresetHolidays(String year) {
    final y = year == 'All' ? DateTime.now().year.toString() : year;
    return [
      {'holiday_name': 'New Year\'s Day', 'holiday_date': '$y-01-01', 'holiday_type': 'Optional Holiday'},
      {'holiday_name': 'Makar Sankranti / Pongal', 'holiday_date': '$y-01-14', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Republic Day', 'holiday_date': '$y-01-26', 'holiday_type': 'National Holiday'},
      {'holiday_name': 'Maha Shivratri', 'holiday_date': '$y-02-15', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Holi (Dhulandi)', 'holiday_date': '$y-03-04', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Eid-ul-Fitr', 'holiday_date': '$y-03-21', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Good Friday', 'holiday_date': '$y-04-03', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Dr. Ambedkar Jayanti', 'holiday_date': '$y-04-14', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Independence Day', 'holiday_date': '$y-08-15', 'holiday_type': 'National Holiday'},
      {'holiday_name': 'Raksha Bandhan', 'holiday_date': '$y-08-28', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Janmashtami', 'holiday_date': '$y-09-04', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Ganesh Chaturthi', 'holiday_date': '$y-09-14', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Gandhi Jayanti', 'holiday_date': '$y-10-02', 'holiday_type': 'National Holiday'},
      {'holiday_name': 'Dussehra (Vijayadashami)', 'holiday_date': '$y-10-20', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Diwali (Deepavali)', 'holiday_date': '$y-11-08', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Bhai Dooj', 'holiday_date': '$y-11-10', 'holiday_type': 'Optional Holiday'},
      {'holiday_name': 'Guru Nanak Jayanti', 'holiday_date': '$y-11-24', 'holiday_type': 'Public Holiday'},
      {'holiday_name': 'Christmas Day', 'holiday_date': '$y-12-25', 'holiday_type': 'Public Holiday'},
    ];
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

        final list = _filteredHolidays;
        final upcoming = _nextUpcomingHoliday;
        final publicCount = list.where((h) => h['holiday_type'] != 'Optional Holiday').length;
        final optionalCount = list.where((h) => h['holiday_type'] == 'Optional Holiday').length;

        final isMobile = MediaQuery.sizeOf(context).width < 650;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: Text(
              'Attendance Master • Holiday Calendar',
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
                      constraints: const BoxConstraints(maxWidth: 1020),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. TOP KPI STRIP (Responsive: stacked on mobile, side-by-side on desktop)
                          if (isMobile) ...[
                            _kpiCard(
                              title: 'Total Holidays ($_selectedYear)',
                              value: '${list.length}',
                              sub: '$publicCount Public/National • $optionalCount Optional',
                              icon: Icons.event_available_rounded,
                              color: EnterpriseColors.emerald,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              textTitle: textTitle,
                              textSub: textSub,
                            ),
                            const SizedBox(height: 10),
                            _kpiCard(
                              title: 'Next Upcoming Holiday',
                              value: upcoming != null ? '${upcoming['holiday_name']}' : 'None Scheduled',
                              sub: upcoming != null ? '${upcoming['holiday_date']} (${upcoming['holiday_type']})' : 'Add or load preset holidays below',
                              icon: Icons.celebration_rounded,
                              color: const Color(0xFF0EA5E9),
                              cardBg: cardBg,
                              borderColor: borderColor,
                              textTitle: textTitle,
                              textSub: textSub,
                            ),
                          ] else
                            Row(
                              children: [
                                Expanded(
                                  child: _kpiCard(
                                    title: 'Total Holidays ($_selectedYear)',
                                    value: '${list.length}',
                                    sub: '$publicCount Public/National • $optionalCount Optional',
                                    icon: Icons.event_available_rounded,
                                    color: EnterpriseColors.emerald,
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    textTitle: textTitle,
                                    textSub: textSub,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _kpiCard(
                                    title: 'Next Upcoming Holiday',
                                    value: upcoming != null ? '${upcoming['holiday_name']}' : 'None Scheduled',
                                    sub: upcoming != null ? '${upcoming['holiday_date']} (${upcoming['holiday_type']})' : 'Add or load preset holidays below',
                                    icon: Icons.celebration_rounded,
                                    color: const Color(0xFF0EA5E9),
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    textTitle: textTitle,
                                    textSub: textSub,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),

                          // 2. ACTION BAR (BULK IMPORT + PRESET LOADER + SINGLE ADD)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: EnterpriseTheme.card(color: cardBg, borderColor: borderColor, radius: EnterpriseRadius.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: isMobile ? double.infinity : 240,
                                      child: TextField(
                                        controller: _searchCtrl,
                                        onChanged: (_) => setState(() {}),
                                        style: TextStyle(color: textTitle, fontSize: 13.5),
                                        decoration: InputDecoration(
                                          hintText: 'Search holiday or date...',
                                          hintStyle: TextStyle(color: textSub, fontSize: 13),
                                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: textSub),
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(EnterpriseRadius.md)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(EnterpriseRadius.md),
                                            borderSide: BorderSide(color: borderColor),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedYear,
                                        dropdownColor: cardBg,
                                        style: TextStyle(color: textTitle, fontSize: 13),
                                        decoration: InputDecoration(
                                          labelText: 'Year',
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(EnterpriseRadius.md)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(EnterpriseRadius.md),
                                            borderSide: BorderSide(color: borderColor),
                                          ),
                                        ),
                                        items: ['2025', '2026', '2027', 'All']
                                            .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                                            .toList(),
                                        onChanged: (v) => setState(() => _selectedYear = v ?? '2026'),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 170,
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedTypeFilter,
                                        dropdownColor: cardBg,
                                        style: TextStyle(color: textTitle, fontSize: 13),
                                        decoration: InputDecoration(
                                          labelText: 'Type',
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(EnterpriseRadius.md)),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(EnterpriseRadius.md),
                                            borderSide: BorderSide(color: borderColor),
                                          ),
                                        ),
                                        items: ['All', 'National Holiday', 'Public Holiday', 'Optional Holiday']
                                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                            .toList(),
                                        onChanged: (v) => setState(() => _selectedTypeFilter = v ?? 'All'),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _isImporting ? null : () => _openPresetDialog(cardBg, borderColor, textTitle, textSub),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                                      label: const Text('Load India Holidays'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _isImporting ? null : () => _openExcelGuideDialog(cardBg, borderColor, textTitle, textSub),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: textTitle,
                                        side: BorderSide(color: borderColor),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                      icon: const Icon(Icons.upload_file_rounded, size: 17),
                                      label: const Text('Import Excel / CSV'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _isImporting ? null : () => _openAddHolidayDialog(cardBg, borderColor, textTitle, textSub),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: EnterpriseColors.emerald,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      label: const Text('Add Holiday'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Tip: Use "Load India Holidays" to import multiple holidays in one click, or upload an Excel/CSV sheet with columns: Holiday Name, Date (YYYY-MM-DD), Type.',
                                  style: TextStyle(color: textSub, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 3. HOLIDAY LIST
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: EnterpriseTheme.card(color: cardBg, borderColor: borderColor, radius: EnterpriseRadius.lg),
                            child: list.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 36),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(Icons.event_note_rounded, size: 42, color: textSub),
                                          const SizedBox(height: 10),
                                          Text('No holidays found for $_selectedYear.', style: TextStyle(color: textTitle, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text('Click "Load India Holidays" or "Import Excel / CSV" to populate instantly.', style: TextStyle(color: textSub, fontSize: 12.5)),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                                    itemBuilder: (_, i) {
                                      final item = list[i];
                                      final dateStr = (item['holiday_date'] ?? '').toString();
                                      final parsed = DateTime.tryParse(dateStr);
                                      const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
                                      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                      final dayNum = parsed != null ? parsed.day.toString().padLeft(2, '0') : '--';
                                      final monStr = parsed != null ? months[parsed.month - 1] : '';
                                      final weekdayStr = parsed != null ? days[parsed.weekday - 1] : '';
                                      final type = (item['holiday_type'] ?? 'Public Holiday').toString();

                                      Color badgeColor = EnterpriseColors.emerald;
                                      if (type == 'National Holiday') badgeColor = const Color(0xFF0EA5E9);
                                      if (type == 'Optional Holiday') badgeColor = const Color(0xFFF59E0B);

                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                        leading: Container(
                                          width: 52,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(dayNum, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 15, height: 1)),
                                              Text(monStr, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w700, fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                        title: Text('${item['holiday_name']}', style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 14.5)),
                                        subtitle: Text('$dateStr  •  $weekdayStr', style: TextStyle(color: textSub, fontSize: 12)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(EnterpriseRadius.pill),
                                              ),
                                              child: Text(type, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w700)),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                              tooltip: 'Remove Holiday',
                                              onPressed: () => _deleteHoliday(item['id']),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
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

  Widget _kpiCard({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color borderColor,
    required Color textTitle,
    required Color textSub,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: EnterpriseTheme.card(color: cardBg, borderColor: borderColor, radius: EnterpriseRadius.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSub, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openExcelGuideDialog(Color cardBg, Color borderColor, Color textTitle, Color textSub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Text('Import Holidays from Excel / CSV', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create an Excel (.xlsx / .xls) or CSV (.csv) file with these 3 columns:',
                style: TextStyle(color: textSub, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EnterpriseColors.emerald.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Table(
                  border: TableBorder.all(color: borderColor, width: 0.8),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: EnterpriseColors.emerald.withValues(alpha: 0.12)),
                      children: [
                        Padding(padding: const EdgeInsets.all(6), child: Text('Holiday Name', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: const EdgeInsets.all(6), child: Text('Date', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: const EdgeInsets.all(6), child: Text('Type', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(6), child: Text('Republic Day', style: TextStyle(color: textSub, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(6), child: Text('2026-01-26', style: TextStyle(color: textSub, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(6), child: Text('National Holiday', style: TextStyle(color: textSub, fontSize: 12))),
                    ]),
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.all(6), child: Text('Diwali', style: TextStyle(color: textSub, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(6), child: Text('08/11/2026', style: TextStyle(color: textSub, fontSize: 12))),
                      Padding(padding: const EdgeInsets.all(6), child: Text('Public Holiday', style: TextStyle(color: textSub, fontSize: 12))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '• Supported Date Formats: YYYY-MM-DD, DD/MM/YYYY, or standard Excel Date cells.\n• Duplicate dates for the same company are automatically skipped.',
                style: TextStyle(color: textSub, fontSize: 11.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: EnterpriseColors.emerald, foregroundColor: Colors.white),
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text('Choose Excel / CSV File'),
            onPressed: () {
              Navigator.pop(ctx);
              _importFromExcel();
            },
          ),
        ],
      ),
    );
  }

  void _openAddHolidayDialog(Color cardBg, Color borderColor, Color textTitle, Color textSub) {
    final nameCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now();
    String selectedType = 'Public Holiday';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final dateStr = pickedDate.toIso8601String().split('T')[0];
          return AlertDialog(
            backgroundColor: cardBg,
            title: Text('Add Holiday', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: textTitle),
                    decoration: const InputDecoration(labelText: 'Holiday Name (e.g. Diwali)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: pickedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setDlgState(() => pickedDate = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Holiday Date', border: OutlineInputBorder()),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dateStr, style: TextStyle(color: textTitle)),
                          Icon(Icons.calendar_today_rounded, size: 18, color: textSub),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: cardBg,
                    style: TextStyle(color: textTitle),
                    decoration: const InputDecoration(labelText: 'Holiday Type', border: OutlineInputBorder()),
                    items: ['Public Holiday', 'National Holiday', 'Optional Holiday']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => selectedType = v ?? 'Public Holiday'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: EnterpriseColors.emerald, foregroundColor: Colors.white),
                onPressed: () async {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  Navigator.pop(ctx);
                  await _addHoliday(n, dateStr, selectedType);
                },
                child: const Text('Save Holiday'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openPresetDialog(Color cardBg, Color borderColor, Color textTitle, Color textSub) {
    final targetYear = _selectedYear == 'All' ? DateTime.now().year.toString() : _selectedYear;
    final presets = _indiaPresetHolidays(targetYear);
    final selectedIndices = Set<int>.from(List.generate(presets.length, (i) => i));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: cardBg,
          title: Text('Load India Holidays ($targetYear)', style: TextStyle(color: textTitle, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${selectedIndices.length} of ${presets.length} selected', style: TextStyle(color: textSub, fontSize: 12.5)),
                    TextButton(
                      onPressed: () {
                        setDlgState(() {
                          if (selectedIndices.length == presets.length) {
                            selectedIndices.clear();
                          } else {
                            selectedIndices.addAll(List.generate(presets.length, (i) => i));
                          }
                        });
                      },
                      child: Text(selectedIndices.length == presets.length ? 'Unselect All' : 'Select All'),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: presets.length,
                    itemBuilder: (_, i) {
                      final h = presets[i];
                      final checked = selectedIndices.contains(i);
                      return CheckboxListTile(
                        dense: true,
                        activeColor: EnterpriseColors.emerald,
                        value: checked,
                        title: Text(h['holiday_name']!, style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: Text('${h['holiday_date']} • ${h['holiday_type']}', style: TextStyle(color: textSub, fontSize: 11.5)),
                        onChanged: (v) {
                          setDlgState(() {
                            if (v == true) {
                              selectedIndices.add(i);
                            } else {
                              selectedIndices.remove(i);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
              icon: const Icon(Icons.download_done_rounded, size: 17),
              label: Text('Import ${selectedIndices.length} Holidays'),
              onPressed: selectedIndices.isEmpty
                  ? null
                  : () async {
                      final chosen = selectedIndices.map((i) => presets[i]).toList();
                      Navigator.pop(ctx);
                      await _bulkAddHolidays(chosen);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/*
// ============================================================================
// OTHER MASTERS (COMMENTED OUT FOR NOW — UNCOMMENT WHEN NEEDED):
// 1. Attendance Type / Status Master (P, A, HD, L, WO, H, OD, SHL)
// 2. Shift Master (General Shift, Start/End Time, Break)
// 3. Weekly Off Master (Sunday / Alternate Saturday)
// 4. Leave Type Master (CL, SL, PL, SHL)
// 5. Device / Machine Master (Biometric & RFID devices)
// ============================================================================
*/
