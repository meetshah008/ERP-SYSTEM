import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';
import '../../core/network/session_manager.dart';
import 'biometric_import_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _canImportExcel = false;
  bool _canOverride = false;
  bool _isLoading = true;
  List<dynamic> _attendanceRecords = [];
  List<dynamic> _filteredRecords = [];

  // Filter States
  String _searchQuery = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  DateTimeRange? _customDateRange;

  final List<String> _monthNames = const [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchAttendance();
  }

  Future<void> _checkPermissions() async {
    final allowedImport = await SessionManager.hasPermission('attendance_import_excel');
    final allowedOverride = await SessionManager.hasPermission('attendance_override');
    if (mounted) {
      setState(() {
        _canImportExcel = allowedImport;
        _canOverride = allowedOverride;
      });
    }
  }

  // 1. Backend se Attendance fetch karna (With Filters)
  Future<void> _fetchAttendance() async {
    setState(() => _isLoading = true);
    try {
      String url = 'http://localhost:5000/api/hr/attendance?';
      if (_customDateRange != null) {
        final start = _customDateRange!.start.toIso8601String().split('T')[0];
        final end = _customDateRange!.end.toIso8601String().split('T')[0];
        url += 'start_date=$start&end_date=$end';
      } else {
        url += 'month=$_selectedMonth&year=$_selectedYear';
      }

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true) {
          _attendanceRecords = json['data'] ?? [];
          _applySearchFilter();
        }
      }
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applySearchFilter() {
    setState(() {
      if (_searchQuery.trim().isEmpty) {
        _filteredRecords = _attendanceRecords;
      } else {
        final q = _searchQuery.toLowerCase();
        _filteredRecords = _attendanceRecords.where((r) {
          final name = (r['full_name'] ?? '').toString().toLowerCase();
          final code = (r['emp_code'] ?? '').toString().toLowerCase();
          final bio = (r['biometric_emp_code'] ?? '').toString().toLowerCase();
          return name.contains(q) || code.contains(q) || bio.contains(q);
        }).toList();
      }
    });
  }

// NAYA SMART AUTO-CALCULATOR CODE:
  String _formatWorkDuration(dynamic minutes, [String? inTime, String? outTime]) {
    final m = int.tryParse(minutes?.toString() ?? '0') ?? 0;
    if (m > 0) {
      final hours = m ~/ 60;
      final mins = m % 60;
      return '${hours}h ${mins}m';
    }

    // Agar database se minutes 0 ya negative aaye, toh In Time aur Out Time se khud calculate karega
    if (inTime != null && outTime != null && inTime != '--:--' && outTime != '--:--') {
      try {
        final inParts = inTime.split(':');
        final outParts = outTime.split(':');
        if (inParts.length >= 2 && outParts.length >= 2) {
          int inH = int.parse(inParts[0]);
          int inM = int.parse(inParts[1]);
          int outH = int.parse(outParts[0]);
          int outM = int.parse(outParts[1]);

          // Agar out time in time se chota hai (jaise 06:00 vs 09:00), toh out time shaam ka 6 PM (18:00) hai
          if (outH < inH && outH < 12) {
            outH += 12; // 6 + 12 = 18 (6:00 PM)
          }

          int diff = (outH * 60 + outM) - (inH * 60 + inM);
          if (diff > 0) {
            final hours = diff ~/ 60;
            final mins = diff % 60;
            return '${hours}h ${mins}m';
          }
        }
      } catch (_) {}
    }

    return '0h 0m';
  }

  // Helper to extract duration minutes from punch record
  int _getRecordWorkMinutes(dynamic r) {
    final m = int.tryParse(r['work_minutes']?.toString() ?? '0') ?? 0;
    if (m > 0) return m;

    final inTime = r['check_in_time']?.toString();
    final outTime = r['check_out_time']?.toString();
    if (inTime != null && outTime != null && inTime != '--:--' && outTime != '--:--') {
      try {
        final inParts = inTime.split(':');
        final outParts = outTime.split(':');
        if (inParts.length >= 2 && outParts.length >= 2) {
          int inH = int.parse(inParts[0]);
          int inM = int.parse(inParts[1]);
          int outH = int.parse(outParts[0]);
          int outM = int.parse(outParts[1]);

          if (outH < inH && outH < 12) {
            outH += 12;
          }

          int diff = (outH * 60 + outM) - (inH * 60 + inM);
          if (diff > 0) return diff;
        }
      } catch (_) {}
    }
    return 0;
  }

  // Monthly Grouped Summary per Employee (1 Row per Staff for Selected Period)
  List<Map<String, dynamic>> get _monthlyEmployeeSummaries {
    final Map<int, Map<String, dynamic>> grouped = {};

    for (final r in _filteredRecords) {
      final empId = r['employee_id'] as int? ?? 0;
      if (!grouped.containsKey(empId)) {
        grouped[empId] = {
          'employee_id': empId,
          'full_name': r['full_name'],
          'emp_code': r['emp_code'],
          'biometric_emp_code': r['biometric_emp_code'],
          'department_name': r['department_name'],
          'total_punches': 0,
          'present_count': 0,
          'late_count': 0,
          'half_day_count': 0,
          'absent_count': 0,
          'total_minutes': 0,
        };
      }

      final emp = grouped[empId]!;
      emp['total_punches'] = (emp['total_punches'] as int) + 1;

      final status = (r['status'] ?? 'Present').toString();
      if (status == 'Present') {
        emp['present_count'] = (emp['present_count'] as int) + 1;
      } else if (status == 'Late') {
        emp['late_count'] = (emp['late_count'] as int) + 1;
      } else if (status == 'Half-Day') {
        emp['half_day_count'] = (emp['half_day_count'] as int) + 1;
      } else if (status == 'Absent') {
        emp['absent_count'] = (emp['absent_count'] as int) + 1;
      }

      emp['total_minutes'] = (emp['total_minutes'] as int) + _getRecordWorkMinutes(r);
    }

    return grouped.values.toList();
  }

  // 2. 📤 UPLOAD BIOMETRIC EXCEL DUMP MODAL
  void _openUploadDialog() {
    String? pickedFileName;
    Uint8List? pickedFileBytes;
    bool isUploading = false;
    String? statusMsg;
    bool isError = false;

    showDialog(
      context: context,
      barrierDismissible: !isUploading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
          final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.upload_file_rounded, color: Color(0xFF10B981), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Import Biometric Attendance', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('Upload .xlsx or .csv face/fingerprint machine dump', style: TextStyle(color: textSub, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: isUploading ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // File Picker Container
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: isUploading ? null : () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['xlsx', 'xls', 'csv'],
                        withData: true,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        setDialogState(() {
                          pickedFileName = result.files.first.name;
                          pickedFileBytes = result.files.first.bytes;
                          statusMsg = null;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            pickedFileName != null ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                            color: pickedFileName != null ? const Color(0xFF10B981) : const Color(0xFF059669),
                            size: 42,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            pickedFileName ?? 'Click to browse Excel / CSV file',
                            style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text('Supports UserID, ProcessDate, Punch1, Punch2', style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),

                  if (statusMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isError ? Colors.redAccent.withValues(alpha: 0.12) : const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusMsg!,
                        style: TextStyle(fontSize: 12, color: isError ? Colors.redAccent : const Color(0xFF10B981)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: (pickedFileBytes == null || isUploading)
                        ? null
                        : () async {
                            setDialogState(() {
                              isUploading = true;
                              statusMsg = null;
                            });
                            try {
                              final uri = Uri.parse('http://localhost:5000/api/hr/upload-attendance');
                              final request = http.MultipartRequest('POST', uri);
                              request.fields['company_id'] = '1';
                              request.fields['user_id'] = '1';

                              request.files.add(
                                http.MultipartFile.fromBytes(
                                  'file',
                                  pickedFileBytes!,
                                  filename: pickedFileName,
                                ),
                              );

                              final streamRes = await request.send();
                              final res = await http.Response.fromStream(streamRes);
                              final json = jsonDecode(res.body);

                              if (res.statusCode == 200 && json['success'] == true) {
                                Navigator.pop(ctx);
                                final impMonth = json['importedMonth'];
                                final impYear = json['importedYear'];
                                if (impMonth != null && impYear != null) {
                                  setState(() {
                                    _selectedMonth = impMonth;
                                    _selectedYear = impYear;
                                    _customDateRange = null;
                                  });
                                }
                                _fetchAttendance(); // Refresh table!
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(json['message'] ?? 'Attendance synced successfully!'),
                                    backgroundColor: const Color(0xFF059669),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                setDialogState(() {
                                  isUploading = false;
                                  isError = true;
                                  statusMsg = json['message'] ?? 'Upload failed.';
                                });
                              }
                            } catch (e) {
                              setDialogState(() {
                                isUploading = false;
                                isError = true;
                                statusMsg = 'Network error: $e';
                              });
                            }
                          },
                    icon: isUploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(isUploading ? 'Processing Machine Dump...' : 'Process & Sync Attendance'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 3. ✏️ MANUAL ATTENDANCE OVERRIDE DIALOG
  void _openEditAttendanceDialog(dynamic row) {
    final attendanceId = row['attendance_id'];
    String selectedStatus = row['status'] ?? 'Present';
    final inCtrl = TextEditingController(text: row['check_in_time'] ?? '');
    final outCtrl = TextEditingController(text: row['check_out_time'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
          final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_calendar_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Manual Attendance Override', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('${row['full_name']} • Date: ${row['work_date']}', style: TextStyle(color: textSub, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 24),

                  // Status Dropdown
                  Text('Attendance Status', style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedStatus,
                        isExpanded: true,
                        dropdownColor: dialogBg,
                        style: TextStyle(color: textTitle, fontSize: 13),
                        items: ['Present', 'Late', 'Half-Day', 'Absent'].map((s) {
                          return DropdownMenuItem(value: s, child: Text(s));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedStatus = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // In-Time & Out-Time Inputs
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Check-In Time', style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: inCtrl,
                              style: TextStyle(color: textTitle, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '09:00:00',
                                hintStyle: TextStyle(color: textSub, fontSize: 11),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Check-Out Time', style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: outCtrl,
                              style: TextStyle(color: textTitle, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '18:00:00',
                                hintStyle: TextStyle(color: textSub, fontSize: 11),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Save Override Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: isSaving ? null : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final res = await http.put(
                          Uri.parse('http://localhost:5000/api/hr/attendance/$attendanceId'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'status': selectedStatus,
                            'check_in': inCtrl.text.trim(),
                            'check_out': outCtrl.text.trim(),
                          }),
                        );
                        final json = jsonDecode(res.body);
                        if (res.statusCode == 200 && json['success'] == true) {
                          Navigator.pop(ctx);
                          _fetchAttendance();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(json['message'] ?? 'Record updated!'), backgroundColor: const Color(0xFF059669), behavior: SnackBarBehavior.floating),
                          );
                        } else {
                          setDialogState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(json['message'] ?? 'Update failed'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
                        );
                      }
                    },
                    child: Text(isSaving ? 'Saving Changes...' : 'Save Override Changes'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 4. 👤 SINGLE EMPLOYEE ATTENDANCE HISTORY MODAL
  void _openEmployeeHistoryModal(dynamic emp) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
        final gridBorderColor = isDark ? Colors.white24 : const Color(0xFFCBD5E1);

        final empLogs = _attendanceRecords.where((r) => r['employee_id'] == emp['employee_id']).toList();

        final memberPresent = empLogs.where((r) => r['status'] == 'Present').length;
        final memberLate = empLogs.where((r) => r['status'] == 'Late').length;
        final memberHalfDay = empLogs.where((r) => r['status'] == 'Half-Day').length;
        final memberAbsent = empLogs.where((r) => r['status'] == 'Absent').length;

        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

        Widget cellText(String text, {Color? color, bool isBold = false, bool isHeader = false, TextAlign align = TextAlign.left}) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Text(
              text,
              textAlign: align,
              style: TextStyle(
                color: color ?? textTitle,
                fontWeight: (isBold || isHeader) ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: dialogBg,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 560),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header: Member Details & Close
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            emp['full_name'] ?? 'Staff Member',
                            style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Code: ${emp['emp_code'] ?? '-'}  |  Machine ID: ${emp['biometric_emp_code'] ?? '-'}  |  Dept: ${emp['department_name'] ?? '-'}',
                            style: TextStyle(color: textSub, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 18),

                // 2. Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attendance Records: ${empLogs.length}',
                      style: TextStyle(color: textTitle, fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Present: $memberPresent  |  Late: $memberLate  |  Half-Day: $memberHalfDay  |  Absent: $memberAbsent',
                      style: TextStyle(color: textSub, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. 100% Full Width Table (Zero Side Gaps)
                Flexible(
                  child: empLogs.isEmpty
                      ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No attendance records found for this period.', style: TextStyle(color: textSub)),
                    ),
                  )
                      : SingleChildScrollView(
                    child: Table(
                      border: TableBorder.all(color: gridBorderColor, width: 1),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FlexColumnWidth(0.5),  // #
                        1: FlexColumnWidth(1.6),  // Date
                        2: FlexColumnWidth(0.9),  // Day
                        3: FlexColumnWidth(1.3),  // In Time
                        4: FlexColumnWidth(1.3),  // Out Time
                        5: FlexColumnWidth(1.2),  // Duration
                        6: FlexColumnWidth(1.3),  // Status
                        7: FlexColumnWidth(0.8),  // Action
                      },
                      children: [
                        // Header Row
                        TableRow(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          ),
                          children: [
                            cellText('#', isHeader: true, align: TextAlign.center),
                            cellText('Date', isHeader: true),
                            cellText('Day', isHeader: true),
                            cellText('In Time', isHeader: true),
                            cellText('Out Time', isHeader: true),
                            cellText('Duration', isHeader: true),
                            cellText('Status', isHeader: true),
                            cellText('Action', isHeader: true, align: TextAlign.center),
                          ],
                        ),
                        // Data Rows
                        ...List.generate(empLogs.length, (i) {
                          final log = empLogs[i];
                          final status = log['status'] ?? 'Present';
                          final parsedDate = DateTime.tryParse(log['work_date'] ?? '');
                          final dayLabel = parsedDate != null ? dayNames[parsedDate.weekday - 1] : '-';

                          Color statusColor;
                          if (status == 'Present') {
                            statusColor = const Color(0xFF059669);
                          } else if (status == 'Late') {
                            statusColor = const Color(0xFFD97706);
                          } else if (status == 'Half-Day') {
                            statusColor = const Color(0xFF7C3AED);
                          } else {
                            statusColor = Colors.red;
                          }

                          return TableRow(
                            children: [
                              cellText('${i + 1}', color: textSub, align: TextAlign.center),
                              cellText('${log['work_date']}'),
                              cellText(dayLabel, color: dayLabel == 'Sun' ? Colors.red : textTitle),
                              cellText('${log['check_in_time'] ?? '--:--'}'),
                              cellText('${log['check_out_time'] ?? '--:--'}'),
                              cellText(_formatWorkDuration(log['work_minutes'], log['check_in_time'], log['check_out_time']), color: textSub),
                              cellText(status, color: statusColor, isBold: true),
                              Center(
                                child: _canOverride
                                    ? IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 15),
                                  color: const Color(0xFF059669),
                                  tooltip: 'Edit',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openEditAttendanceDialog(log);
                                  },
                                )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Mini helper badge for modal top bar
  Widget _buildMiniStatBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF475569);
    final cardBg = isDark ? const Color(0xFF030D08).withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.65);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.8);
    // Phones get a card list instead of the wide 10-column DataTable.
    final isMobileView = MediaQuery.of(context).size.width < 650;

    // KPI Counts
    final totalPresent = _filteredRecords.where((r) => r['status'] == 'Present').length;
    final totalLate = _filteredRecords.where((r) => r['status'] == 'Late').length;
    final totalAbsent = _filteredRecords.where((r) => r['status'] == 'Absent').length;
    final totalHalfDay = _filteredRecords.where((r) => r['status'] == 'Half-Day').length;

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            children: [
              // 1. TOP HEADER + UPLOAD BUTTON (Responsive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 650;

                    final uploadButton = _canImportExcel
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: const Text('Upload Machine Dump', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BiometricImportScreen()),
                        );
                        _fetchAttendance();
                      },
                          )
                        : null;

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back_rounded, color: textTitle),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Biometric Attendance & Logs',
                                  style: TextStyle(color: textTitle, fontSize: 16.5, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 48, bottom: 8),
                            child: Text(
                              'Offline face scanner dumps, punctuality & manual overrides',
                              style: TextStyle(color: textSub, fontSize: 11),
                            ),
                          ),
                          if (uploadButton != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: uploadButton,
                            ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: textTitle),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Biometric Attendance & Logs', style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('Offline face scanner dumps, punctuality & manual overrides', style: TextStyle(color: textSub, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        if (uploadButton != null) uploadButton,
                      ],
                    );
                  },
                ),
              ),

              // 2. FILTER & SEARCH BAR (Mobile-Friendly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 650;

                    final searchField = TextField(
                      onChanged: (val) {
                        _searchQuery = val;
                        _applySearchFilter();
                      },
                      style: TextStyle(color: textTitle, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by employee or machine code...',
                        hintStyle: TextStyle(color: textSub, fontSize: 12),
                        prefixIcon: Icon(Icons.search, size: 18, color: textSub),
                        filled: true,
                        fillColor: cardBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                      ),
                    );

                    final dropdownRow = SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Month Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedMonth,
                                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                style: TextStyle(color: textTitle, fontSize: 12),
                                items: [
                                  const DropdownMenuItem(value: 0, child: Text('All Months')),
                                  ...List.generate(12, (i) => i + 1).map((m) {
                                    return DropdownMenuItem(value: m, child: Text(_monthNames[m - 1]));
                                  }),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedMonth = val;
                                      _customDateRange = null;
                                    });
                                    _fetchAttendance();
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Year Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedYear,
                                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                style: TextStyle(color: textTitle, fontSize: 12),
                                items: [2024, 2025, 2026, 2027].map((y) {
                                  return DropdownMenuItem(value: y, child: Text('$y'));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedYear = val;
                                      _customDateRange = null;
                                    });
                                    _fetchAttendance();
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Custom Date Range Button
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textTitle,
                              side: BorderSide(color: cardBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            ),
                            icon: const Icon(Icons.date_range_rounded, size: 15),
                            label: Text(_customDateRange == null ? 'Custom Range' : 'Active Range', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() => _customDateRange = picked);
                                _fetchAttendance();
                              }
                            },
                          ),

                          if (_customDateRange != null) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Reset Custom Range',
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                setState(() => _customDateRange = null);
                                _fetchAttendance();
                              },
                            ),
                          ],
                        ],
                      ),
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          searchField,
                          const SizedBox(height: 8),
                          dropdownRow,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(flex: 2, child: searchField),
                        const SizedBox(width: 10),
                        dropdownRow,
                      ],
                    );
                  },
                ),
              ),

              // 3. STATS KPI STRIP (Horizontally Scrollable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatPill('Total Staff Active', _monthlyEmployeeSummaries.length, const Color(0xFF0284C7)),
                      const SizedBox(width: 8),
                      _buildStatPill('Total Punches', _filteredRecords.length, const Color(0xFF6366F1)),
                      const SizedBox(width: 8),
                      _buildStatPill('Present', totalPresent, const Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      _buildStatPill('Late', totalLate, const Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      _buildStatPill('Half-Day', totalHalfDay, const Color(0xFF8B5CF6)),
                      const SizedBox(width: 8),
                      _buildStatPill('Absent', totalAbsent, Colors.redAccent),
                    ],
                  ),
                ),
              ),

              // 4. MONTHLY EMPLOYEE ATTENDANCE SUMMARY TABLE (1 Row Per Staff Member)
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                    : _monthlyEmployeeSummaries.isEmpty
                    ? Center(child: Text('No attendance records found for this period.', style: TextStyle(color: textSub)))
                    : isMobileView
                    ? _buildMobileAttendanceList(cardBg, cardBorder, textTitle, textSub, isDark)
                    : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          ),
                          headingTextStyle: TextStyle(
                            color: textTitle,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            letterSpacing: 0.2,
                          ),
                          dataRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                            if (states.contains(WidgetState.hovered)) {
                              return const Color(0xFF059669).withValues(alpha: 0.08);
                            }
                            return null;
                          }),
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 54,
                          horizontalMargin: 16,
                          columnSpacing: 22,
                          dividerThickness: 0.7,
                          columns: const [
                            DataColumn(label: Text('#')),
                            DataColumn(label: Text('EMPLOYEE')),
                            DataColumn(label: Text('EMP CODE')),
                            DataColumn(label: Text('BIOMETRIC ID')),
                            DataColumn(label: Text('MONTH DAYS')),
                            DataColumn(label: Text('PRESENT')),
                            DataColumn(label: Text('LATE')),
                            DataColumn(label: Text('HALF-DAY')),
                            DataColumn(label: Text('TOTAL WORKED')),
                            DataColumn(label: Text('ACTION')),
                          ],
                          rows: List<DataRow>.generate(_monthlyEmployeeSummaries.length, (index) {
                            final emp = _monthlyEmployeeSummaries[index];
                            final name = emp['full_name'] ?? 'Staff Member';
                            final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
                            final totalPunches = emp['total_punches'] ?? 0;
                            final present = emp['present_count'] ?? 0;
                            final lateCount = emp['late_count'] ?? 0;
                            final halfDay = emp['half_day_count'] ?? 0;
                            final totalMins = emp['total_minutes'] ?? 0;
                            final durationStr = '${totalMins ~/ 60}h ${totalMins % 60}m';

                            return DataRow(
                              onSelectChanged: (_) => _openEmployeeHistoryModal(emp),
                              cells: [
                                // 1. Index
                                DataCell(Text('${index + 1}', style: TextStyle(color: textSub, fontSize: 12))),

                                // 2. Employee (Avatar + Full Name)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                                        child: Text(
                                          initial,
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        name,
                                        style: TextStyle(color: textTitle, fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),

                                // 3. Emp Code
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${emp['emp_code'] ?? 'N/A'}',
                                      style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),

                                // 4. Biometric ID
                                DataCell(
                                  Text(
                                    emp['biometric_emp_code'] != null ? '${emp['biometric_emp_code']}' : '-',
                                    style: TextStyle(color: textSub, fontSize: 12),
                                  ),
                                ),

                                // 5. Total Punches / Days in Selected Period
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 12, color: textSub),
                                      const SizedBox(width: 5),
                                      Text('$totalPunches Days', style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),

                                // 6. Present Count Badge
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                    ),
                                    child: Text(
                                      '$present Present',
                                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),

                                // 7. Late Count
                                DataCell(
                                  lateCount > 0
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                                          ),
                                          child: Text(
                                            '$lateCount Late',
                                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : Text('0', style: TextStyle(color: textSub, fontSize: 12)),
                                ),

                                // 8. Half-Day Count
                                DataCell(
                                  halfDay > 0
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                                          ),
                                          child: Text(
                                            '$halfDay Half-Day',
                                            style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      : Text('0', style: TextStyle(color: textSub, fontSize: 12)),
                                ),

                                // 9. Total Hours Worked
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF0284C7)),
                                      const SizedBox(width: 5),
                                      Text(
                                        durationStr,
                                        style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),

                                // 10. Action Button (Calendar Breakdown View)
                                DataCell(
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669).withValues(alpha: 0.12),
                                      foregroundColor: const Color(0xFF059669),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(Icons.calendar_month_rounded, size: 14),
                                    label: const Text('View Logs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: () => _openEmployeeHistoryModal(emp),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
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

  // ================= 📱 MOBILE ATTENDANCE CARDS =================
  // The desktop table has 10 columns. On a phone that means constant
  // horizontal scrolling, so we surface the same data as readable cards.
  Widget _buildMobileAttendanceList(
    Color cardBg,
    Color cardBorder,
    Color textTitle,
    Color textSub,
    bool isDark,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _monthlyEmployeeSummaries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final emp = _monthlyEmployeeSummaries[index];
        final name = (emp['full_name'] ?? 'Staff Member').toString();
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
        final totalPunches = int.tryParse('${emp['total_punches'] ?? 0}') ?? 0;
        final present = int.tryParse('${emp['present_count'] ?? 0}') ?? 0;
        final lateCount = int.tryParse('${emp['late_count'] ?? 0}') ?? 0;
        final halfDay = int.tryParse('${emp['half_day_count'] ?? 0}') ?? 0;
        final totalMins = int.tryParse('${emp['total_minutes'] ?? 0}') ?? 0;
        final durationStr = '${totalMins ~/ 60}h ${totalMins % 60}m';

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => _openEmployeeHistoryModal(emp),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(color: textTitle, fontSize: 14.5, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${emp['emp_code'] ?? 'N/A'} • Machine ID: ${emp['biometric_emp_code'] ?? '-'}',
                                style: TextStyle(color: textSub, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            '$totalPunches Days',
                            style: const TextStyle(color: Color(0xFF6366F1), fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMobileAttendanceMetric('Present', '$present', const Color(0xFF10B981), textSub, isDark),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMobileAttendanceMetric('Late', '$lateCount', const Color(0xFFF59E0B), textSub, isDark),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMobileAttendanceMetric('Half-Day', '$halfDay', const Color(0xFF8B5CF6), textSub, isDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF0284C7)),
                        const SizedBox(width: 5),
                        Text(
                          'Worked: $durationStr',
                          style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _openEmployeeHistoryModal(emp),
                          icon: const Icon(Icons.calendar_month_rounded, size: 15),
                          label: const Text('View Logs', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
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

  Widget _buildMobileAttendanceMetric(String label, String value, Color color, Color textSub, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(color: textSub, fontSize: 9.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$title: ', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
          Text('$count', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
