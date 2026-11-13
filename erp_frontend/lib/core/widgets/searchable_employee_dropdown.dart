import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

class SearchableEmployeeDropdown extends StatelessWidget {
  final List<dynamic> employees;
  final int? selectedEmployeeId;
  final ValueChanged<dynamic> onChanged;
  final String hintText;

  const SearchableEmployeeDropdown({
    super.key,
    required this.employees,
    required this.selectedEmployeeId,
    required this.onChanged,
    this.hintText = 'Click to search & select employee...',
  });

  dynamic get _selectedEmployee {
    try {
      return employees.firstWhere(
            (e) => e['employee_id'] == selectedEmployeeId,
        orElse: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  void _openSearchDialog(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white70 : const Color(0xFF64748B);
    final inputBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9);
    final borderCol = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        final searchController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchQuery.trim().toLowerCase();
            final filteredList = employees.where((emp) {
              if (query.isEmpty) return true;
              final name = (emp['full_name'] ?? '').toString().toLowerCase();
              final code = (emp['emp_code'] ?? '').toString().toLowerCase();
              final bio = (emp['biometric_emp_code'] ?? '').toString().toLowerCase();
              final dept = (emp['department_name'] ?? '').toString().toLowerCase();
              final desig = (emp['designation'] ?? '').toString().toLowerCase();
              return name.contains(query) ||
                  code.contains(query) ||
                  bio.contains(query) ||
                  dept.contains(query) ||
                  desig.contains(query);
            }).toList();

            return Dialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 560),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.person_search_rounded, color: Color(0xFF10B981), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Employee',
                                  style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${filteredList.length} of ${employees.length} employees',
                                  style: TextStyle(color: textSub, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: textSub, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Search TextField (Auto-Focused)
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        style: TextStyle(color: textTitle, fontSize: 13),
                        onChanged: (val) => setModalState(() => searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search by name, code (e.g. 103), department...',
                          hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 20),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                            icon: Icon(Icons.clear_rounded, color: textSub, size: 18),
                            onPressed: () {
                              searchController.clear();
                              setModalState(() => searchQuery = '');
                            },
                          )
                              : null,
                          filled: true,
                          fillColor: inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Results List
                      Expanded(
                        child: filteredList.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, color: textSub.withValues(alpha: 0.4), size: 44),
                              const SizedBox(height: 8),
                              Text('No employee found', style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Try typing another name or employee code', style: TextStyle(color: textSub, fontSize: 11.5)),
                            ],
                          ),
                        )
                            : ListView.separated(
                          itemCount: filteredList.length,
                          separatorBuilder: (_, __) => Divider(color: borderCol, height: 1),
                          itemBuilder: (context, idx) {
                            final emp = filteredList[idx];
                            final empId = emp['employee_id'];
                            final isSelected = empId == selectedEmployeeId;
                            final name = emp['full_name'] ?? 'Staff Member';
                            final code = emp['emp_code'] ?? 'EMP';
                            final dept = emp['department_name'] ?? emp['designation'] ?? 'Operations';

                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.pop(ctx);
                                onChanged(emp);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.12) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 17,
                                      backgroundColor: isSelected
                                          ? const Color(0xFF10B981)
                                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'E',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
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
                                                  name,
                                                  style: TextStyle(
                                                    color: textTitle,
                                                    fontSize: 13.5,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  code,
                                                  style: const TextStyle(
                                                    color: Color(0xFF0284C7),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dept,
                                            style: TextStyle(color: textSub, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20)
                                    else
                                      Icon(Icons.arrow_forward_ios_rounded, color: textSub.withValues(alpha: 0.3), size: 12),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white70 : const Color(0xFF64748B);
    final inputBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC);
    final inputBorder = isDark ? Colors.white24 : const Color(0xFFCBD5E1);

    final emp = _selectedEmployee;

    return InkWell(
      onTap: () => _openSearchDialog(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: inputBorder),
        ),
        child: Row(
          children: [
            if (emp != null) ...[
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.18),
                child: Text(
                  (emp['full_name'] != null && emp['full_name'].toString().isNotEmpty)
                      ? emp['full_name'][0].toUpperCase()
                      : 'E',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${emp['full_name']} (${emp['emp_code'] ?? 'EMP'})',
                  style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              Icon(Icons.person_search_outlined, size: 18, color: textSub.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hintText,
                  style: TextStyle(color: textSub.withValues(alpha: 0.7), fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            Icon(Icons.search_rounded, size: 16, color: textSub),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: textSub),
          ],
        ),
      ),
    );
  }
}