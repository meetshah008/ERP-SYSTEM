import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/botanical_background.dart';

class BiometricImportScreen extends StatefulWidget {
  const BiometricImportScreen({super.key});

  @override
  State<BiometricImportScreen> createState() => _BiometricImportScreenState();
}

class _BiometricImportScreenState extends State<BiometricImportScreen> {
  bool _isUploading = false;

  String? _pickedFileName;
  Uint8List? _pickedFileBytes;
  List<String> _consoleLogs = [];

  // Excel Sheet Live Preview Variables
  bool _isPreviewLoading = false;
  List<String> _previewHeaders = [];
  List<List<String>> _previewRows = [];
  int _previewTotalRows = 0;
  String _previewSheetName = '';

  // Terminal Filter & Search
  String _selectedLogFilter = 'ALL';
  String _logSearchQuery = '';
  final TextEditingController _logSearchController = TextEditingController();
  final ScrollController _terminalScrollController = ScrollController();
  bool _autoScroll = true;

  // Execution Summary Metrics
  int _totalRows = 0;
  int _successCount = 0;
  int _failedCount = 0;
  int _executionMs = 0;

  @override
  void dispose() {
    _terminalScrollController.dispose();
    _logSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPreview(Uint8List bytes, String fileName) async {
    setState(() {
      _isPreviewLoading = true;
      _previewHeaders.clear();
      _previewRows.clear();
      _previewTotalRows = 0;
    });

    try {
      final uri = Uri.parse('http://localhost:5000/api/hr/preview-attendance');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

      final streamedRes = await request.send();
      final res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _previewHeaders = List<String>.from(data['headers'] ?? []);
            _previewRows = List<List<String>>.from(
              (data['previewRows'] ?? []).map((r) => List<String>.from((r as List).map((c) => c.toString()))),
            );
            _previewTotalRows = data['totalRows'] ?? 0;
            _previewSheetName = data['sheetName'] ?? 'Sheet1';
          });
          return;
        }
      }

      // Agar backend se error aaye:
      String errorMsg = 'Server responded with code ${res.statusCode}';
      try {
        final data = jsonDecode(res.body);
        if (data['message'] != null) errorMsg = data['message'];
      } catch (_) {
        if (res.statusCode == 404) {
          errorMsg = 'Backend route not found. Please restart backend server (npm start).';
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ $errorMsg'), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection Error: $e. Is backend running?'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _pickedFileName = file.name;
          _pickedFileBytes = file.bytes;
          _selectedLogFilter = 'ALL';
          _logSearchQuery = '';
          _logSearchController.clear();
          _consoleLogs = [
            '================================================================================',
            '  BIOMETRIC ATTENDANCE INGESTION CONSOLE  |  STANDBY',
            '================================================================================',
            '[SYSTEM] Staged File: "$_pickedFileName" (${(file.size / 1024).toStringAsFixed(1)} KB)',
            '[READY] Click "Process & Sync Attendance" to run parser engine and view live terminal logs.',
          ];
        });
        if (file.bytes != null) {
          _fetchPreview(file.bytes!, file.name);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File pick error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _processUpload() async {
    if (_pickedFileBytes == null || _pickedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an Excel or CSV file first!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _consoleLogs.add('[EXEC] Establishing multipart connection to backend (port 5000)...');
    });

    try {
      final uri = Uri.parse('http://localhost:5000/api/hr/upload-attendance');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes('file', _pickedFileBytes!, filename: _pickedFileName),
      );

      final streamedRes = await request.send();
      final res = await http.Response.fromStream(streamedRes);
      final data = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 && data['success'] == true) {
        final List<dynamic> backendLogs = data['logs'] ?? [];
        final summary = data['summary'] ?? {};

        setState(() {
          _consoleLogs = backendLogs.map((e) => e.toString()).toList();
          _totalRows = summary['totalRows'] ?? 0;
          _successCount = summary['successCount'] ?? 0;
          _failedCount = summary['failedCount'] ?? 0;
          _executionMs = summary['executionMs'] ?? 0;
          _pickedFileName = null;
          _pickedFileBytes = null;
        });

        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_terminalScrollController.hasClients) {
              _terminalScrollController.animateTo(
                _terminalScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            }
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced $_successCount punches, $_failedCount unmatched rows.'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      } else {
        setState(() {
          _consoleLogs.add('[FATAL] Upload failed: ${data['message']}');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Upload failed!'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _consoleLogs.add('[ERROR] Network pipeline failure: $e');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) setState(() => _isUploading = false);
  }

  void _copyLogsToClipboard() {
    Clipboard.setData(ClipboardData(text: _consoleLogs.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All terminal logs copied to clipboard!'), duration: Duration(seconds: 2)),
    );
  }

  List<String> get _filteredLogs {
    return _consoleLogs.where((line) {
      // 1. Tab Filter
      if (_selectedLogFilter == 'OK' && !line.contains('[OK]')) return false;
      if (_selectedLogFilter == 'WARN' && !line.contains('[WARN]')) return false;
      if (_selectedLogFilter == 'SKIP' && !line.contains('[SKIP]')) return false;

      // 2. Search Filter
      if (_logSearchQuery.isNotEmpty) {
        return line.toLowerCase().contains(_logSearchQuery.toLowerCase());
      }
      return true;
    }).toList();
  }

  Color _getLogColor(String line) {
    if (line.contains('[OK]')) return const Color(0xFF4ADE80); // Neon Green
    if (line.contains('[COMPLETE]')) return const Color(0xFF2DD4BF); // Teal
    if (line.contains('[WARN]')) return const Color(0xFFFBBF24); // Amber
    if (line.contains('[SKIP]')) return const Color(0xFF94A3B8); // Muted grey
    if (line.contains('[ERROR]') || line.contains('[FATAL]')) return const Color(0xFFF87171); // Red
    if (line.contains('[INIT]') || line.contains('[PARSE]') || line.contains('[HEADER]') || line.contains('[CACHE]')) {
      return const Color(0xFF38BDF8); // Cyan
    }
    if (line.startsWith('=')) return const Color(0xFF818CF8); // Indigo divider
    return const Color(0xFFE2E8F0); // Off-white
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white60 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF0F172A).withValues(alpha: 0.85) : Colors.white;
    final cardBorder = isDark ? Colors.white12 : const Color(0xFFCBD5E1);

    final okCount = _consoleLogs.where((l) => l.contains('[OK]')).length;
    final warnCount = _consoleLogs.where((l) => l.contains('[WARN]')).length;
    final skipCount = _consoleLogs.where((l) => l.contains('[SKIP]')).length;

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardBg.withValues(alpha: 0.95),
                  border: Border(bottom: BorderSide(color: cardBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: textTitle),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.terminal_rounded, color: Color(0xFF059669), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Biometric Attendance Dump Ingestion Console',
                            style: TextStyle(color: textTitle, fontSize: 16.5, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Enterprise biometric engine: punch sync, verification checks & live terminal logs',
                            style: TextStyle(color: textSub, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Upload Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Agar file select NAHI hai, toh Browse Button dikhega
                            if (_pickedFileName == null)
                              InkWell(
                                onTap: _isUploading ? null : _pickFile,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.file_upload_outlined, size: 28, color: Color(0xFF059669)),
                                      SizedBox(width: 12),
                                      Text(
                                        'Click to Browse Machine Dump File (.xlsx, .csv, .xls)',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                            // File select hone par LIVE EXCEL SPREADSHEET dikhegi:
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top File Info Bar
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withValues(alpha: 0.12),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.table_chart_rounded, size: 20, color: Color(0xFF059669)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$_pickedFileName (${_previewSheetName.isNotEmpty ? _previewSheetName : "Sheet1"})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF059669)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$_previewTotalRows Rows Detected',
                                            style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                          icon: const Icon(Icons.sync_rounded, size: 14),
                                          label: const Text('Change File', style: TextStyle(fontSize: 11.5)),
                                          onPressed: _isUploading ? null : _pickFile,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Scrollable Spreadsheet View
                                  Container(
                                    height: 280,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                      border: Border(
                                        left: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                        right: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                        bottom: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                      ),
                                    ),
                                    child: _isPreviewLoading
                                        ? const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(color: Color(0xFF059669)),
                                          SizedBox(height: 10),
                                          Text('Reading & loading Excel data...', style: TextStyle(color: Color(0xFF059669), fontSize: 12.5)),
                                        ],
                                      ),
                                    )
                                        : LayoutBuilder(
                                      builder: (context, constraints) {
                                        // 1. Columns Width Proportionally Divide
                                        final Map<int, TableColumnWidth> colWidths = {
                                          0: const FixedColumnWidth(44), // '#' Column
                                        };

                                        for (int i = 0; i < _previewHeaders.length; i++) {
                                          final h = _previewHeaders[i].toLowerCase();
                                          if (h.contains('name')) {
                                            colWidths[i + 1] = const FlexColumnWidth(2.2);
                                          } else if (h.contains('date') || h.contains('punch') || h.contains('time')) {
                                            colWidths[i + 1] = const FlexColumnWidth(2.0);
                                          } else if (h.contains('id') || h.contains('code') || h.contains('shift') || h.contains('late') || h.contains('early') || h.contains('overtime')) {
                                            colWidths[i + 1] = const FlexColumnWidth(1.0);
                                          } else {
                                            colWidths[i + 1] = const FlexColumnWidth(1.4);
                                          }
                                        }

                                        // 100% Full Width Stretch
                                        final double minTableWidth = (_previewHeaders.length + 1) * 85.0;
                                        final double targetWidth = constraints.maxWidth > minTableWidth
                                            ? constraints.maxWidth
                                            : minTableWidth;

                                        return Scrollbar(
                                          thumbVisibility: true,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.vertical,
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: SizedBox(
                                                width: targetWidth,
                                                child: Table(
                                                  columnWidths: colWidths,
                                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                                  children: [
                                                    // 🟢 Header Row (100% Full Width Green)
                                                    TableRow(
                                                      decoration: const BoxDecoration(
                                                        color: Color(0xFF059669),
                                                      ),
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                                          alignment: Alignment.center,
                                                          child: const Text('#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                                        ),
                                                        ..._previewHeaders.map(
                                                              (h) => Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                            child: Text(
                                                              h,
                                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),

                                                    // ⚪ Data Rows
                                                    ...List.generate(_previewRows.length, (idx) {
                                                      final row = _previewRows[idx];
                                                      final isEven = idx % 2 == 0;
                                                      final rowBg = isEven
                                                          ? (isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC))
                                                          : (isDark ? Colors.transparent : Colors.white);

                                                      return TableRow(
                                                        decoration: BoxDecoration(
                                                          color: rowBg,
                                                          border: Border(
                                                            bottom: BorderSide(
                                                              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                        ),
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                                                            alignment: Alignment.center,
                                                            child: Text('${idx + 1}', style: TextStyle(color: textSub, fontSize: 11)),
                                                          ),
                                                          ...List.generate(_previewHeaders.length, (colIdx) {
                                                            final cellVal = colIdx < row.length ? row[colIdx] : '';
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                                              child: Text(
                                                                cellVal,
                                                                style: TextStyle(
                                                                  color: textTitle,
                                                                  fontSize: 12,
                                                                  fontFamily: 'monospace',
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            );
                                                          }),
                                                        ],
                                                      );
                                                    }),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_pickedFileName != null)
                                  TextButton.icon(
                                    icon: const Icon(Icons.close, size: 15),
                                    label: const Text('Clear File'),
                                    onPressed: _isUploading
                                        ? null
                                        : () => setState(() {
                                              _pickedFileName = null;
                                              _pickedFileBytes = null;
                                              _consoleLogs.clear();
                                            }),
                                  ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: (_pickedFileBytes == null || _isUploading) ? null : _processUpload,
                                  icon: _isUploading
                                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: Text(_isUploading ? 'Executing Ingestion Engine...' : 'Process & Sync Attendance'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Metrics Cards Strip (if processed)
                      if (_totalRows > 0) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildMetricBox('Total Records', '$_totalRows', const Color(0xFF0284C7), isDark)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricBox('Punches Synced', '$_successCount', const Color(0xFF10B981), isDark)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricBox('Unmatched / Skipped', '$_failedCount', const Color(0xFFF59E0B), isDark)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricBox('Execution Time', '${_executionMs}ms', const Color(0xFF8B5CF6), isDark)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ================= TERMINAL CONSOLE =================
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF070B14), // Deep Space Black Console
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1E293B)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Window Titlebar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              color: const Color(0xFF0F172A),
                              child: Row(
                                children: [
                                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'biometric-ingestion-engine.log',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Consolas', fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_filteredLogs.length} / ${_consoleLogs.length} lines',
                                    style: const TextStyle(color: Color(0xFF64748B), fontFamily: 'Consolas', fontSize: 11),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: () => setState(() => _autoScroll = !_autoScroll),
                                    child: Row(
                                      children: [
                                        Icon(_autoScroll ? Icons.lock_clock : Icons.lock_open, color: const Color(0xFF94A3B8), size: 13),
                                        const SizedBox(width: 4),
                                        Text(_autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'Consolas')),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: _consoleLogs.isEmpty ? null : _copyLogsToClipboard,
                                    child: Row(
                                      children: const [
                                        Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 13),
                                        SizedBox(width: 4),
                                        Text('Copy', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Consolas')),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 2. Terminal Control Toolbar (Tabs & Search Bar)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              color: const Color(0xFF090D1A),
                              child: Row(
                                children: [
                                  _buildLogTab('ALL', 'All (${_consoleLogs.length})'),
                                  const SizedBox(width: 6),
                                  _buildLogTab('OK', 'Synced ($okCount)', color: const Color(0xFF4ADE80)),
                                  const SizedBox(width: 6),
                                  _buildLogTab('WARN', 'Unregistered ($warnCount)', color: const Color(0xFFFBBF24)),
                                  const SizedBox(width: 6),
                                  _buildLogTab('SKIP', 'Skipped ($skipCount)', color: const Color(0xFF94A3B8)),
                                  const Spacer(),
                                  SizedBox(
                                    width: 180,
                                    height: 28,
                                    child: TextField(
                                      controller: _logSearchController,
                                      onChanged: (val) => setState(() => _logSearchQuery = val),
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Consolas'),
                                      decoration: InputDecoration(
                                        hintText: 'Search logs...',
                                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                        prefixIcon: const Icon(Icons.search, size: 14, color: Color(0xFF64748B)),
                                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 3. Monospace Terminal Stream
                            Container(
                              height: 480,
                              padding: const EdgeInsets.all(14),
                              child: _filteredLogs.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Ready. Stage a file and click "Process & Sync Attendance" to run the parser engine.',
                                        style: TextStyle(color: Color(0xFF475569), fontFamily: 'Consolas', fontSize: 12),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _terminalScrollController,
                                      itemCount: _filteredLogs.length,
                                      itemBuilder: (ctx, i) {
                                        final line = _filteredLogs[i];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2.2),
                                          child: Text(
                                            line,
                                            style: TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 11.5,
                                              color: _getLogColor(line),
                                              height: 1.35,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLogTab(String key, String label, {Color? color}) {
    final isSelected = _selectedLogFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedLogFilter = key),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isSelected ? (color ?? Colors.white54) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? (color ?? Colors.white) : const Color(0xFF64748B),
            fontSize: 11,
            fontFamily: 'Consolas',
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
