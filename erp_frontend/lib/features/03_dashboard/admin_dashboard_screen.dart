import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../core/network/session_manager.dart';
import '../../core/widgets/botanical_background.dart';
import '../02_auth/login_screen.dart';
import '../04_hr_module/employee_management_screen.dart';
import '../04_hr_module/attendance_screen.dart';
import '../../core/theme/theme_controller.dart';
import '../04_hr_module/leave_management_screen.dart';
import '../../core/widgets/animated_donut_chart.dart';
import '../../core/widgets/mobile_ui.dart';
import '../05_tasks/project_tasks_screen.dart';
import '../04_hr_module/employee_details_screen.dart';
import '../04_hr_module/salary_increment_screen.dart';
import '../04_hr_module/departments_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String companyName;
  final String adminEmail;
  final String role;


  const AdminDashboardScreen({
    super.key,
    required this.companyName,
    required this.adminEmail,
    required this.role,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // Kaunsa tab abhi active hai
  String _selectedMenu = 'Dashboard';

  // Backend se aane wala live staff count
  int _totalEmployees = 0;
  int _pendingTasksCount = 0;
  int _totalTasksCount = 0;
  bool _isLoadingStats = true;
  List<dynamic> _employees = [];
  List<dynamic> _departments = [];
  bool _isLoadingDepts = true;
  int _totalProjects = 0;
  int _pendingProjects = 0;
  int _completedProjects = 0;
  int _unreadNotifCount = 0;
  List<dynamic> _notifications = [];
  Timer? _notifTimer;

  // 🔐 Permissions Map (Logged-in user ke allowed/denied features)
  Map<String, bool> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions(); // 👈 Pehle user ki permissions load karein
    _fetchLiveStats();
    _fetchNotifications();

    // 🔔 Auto-check notifications every 10 seconds
    _notifTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _fetchNotifications();
    });
  }

  // Session storage se permissions load karne ka function
  Future<void> _loadPermissions() async {
    if (widget.role == 'Super Admin') return; // Super admin ko sab allow hai
    final perms = await SessionManager.getPermissions();
    if (mounted) {
      setState(() {
        _permissions = perms;
      });
      _fetchNotifications(); // Reload scoped notifications with permissions
    }
  }

  // Permission check helper (Pure dashboard me use hoga)
  bool _hasPermission(String key) {
    if (widget.role == 'Super Admin') return true;
    return _permissions[key] ?? false;
  }
  // Check karega ki kya HR ke kisi bhi ek feature ki permission mili hai
  bool get _hasAnyHrAccess {
    if (widget.role == 'Super Admin') return true;
    return _hasPermission('hr_view_directory') ||
        _hasPermission('attendance_view_logs') ||
        _hasPermission('leaves_apply') ||
        _hasPermission('leaves_approve');
  }

  // 1. BACKEND SE LIVE DATA FETCH KARNA
  Future<void> _fetchLiveStats() async {
    try {
      // 1. Staff count
      final res = await http.get(Uri.parse('http://localhost:5000/api/hr/stats'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          _totalEmployees = data['total'] ?? 0;
        }
      }

      // 2. Tasks count (TODO ya IN_PROGRESS)
      final taskRes = await http.get(Uri.parse('http://localhost:5000/api/tasks'));
      if (taskRes.statusCode == 200) {
        final taskData = jsonDecode(taskRes.body);
        if (taskData['success'] == true && taskData['data'] is List) {
          final list = taskData['data'] as List;
          _totalTasksCount = list.length; // 👈 Yeh line add karein
          _pendingTasksCount = list.where((t) => t['status'] != 'DONE').length;
        }
      }

      // 3. 👈 YEH MISSING THA: Real Employees List Fetch Karna!
      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final empData = jsonDecode(empRes.body);
        if (empData['success'] == true && empData['data'] is List) {
          _employees = empData['data'];
        }
      }
      // 4. Departments List Fetch Karna
      try {
        final deptRes = await http.get(Uri.parse('http://localhost:5000/api/hr/departments'));
        if (deptRes.statusCode == 200) {
          final deptData = jsonDecode(deptRes.body);
          if (deptData['success'] == true && deptData['data'] is List) {
            _departments = deptData['data'];
          }
        }
      } catch (_) {}
      // 5. Projects Fetch Karna & Stats Calculate Karna
      try {
        final prjRes = await http.get(Uri.parse('http://localhost:5000/api/projects'));
        if (prjRes.statusCode == 200) {
          final prjData = jsonDecode(prjRes.body);
          if (prjData['success'] == true && prjData['data'] is List) {
            final List list = prjData['data'];
            _totalProjects = list.length;
            // Jo project 'Completed' nahi hain wo Pending / In-Progress hain
            _pendingProjects = list.where((p) => p['status'] != 'Completed').length;
            // Jo project 'Completed' hain
            _completedProjects = list.where((p) => p['status'] == 'Completed').length;
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  // 🔔 NOTIFICATIONS FETCH FUNCTION (User & Role targeted)
  Future<void> _fetchNotifications() async {
    try {
      final session = await SessionManager.getUserSession();
      final userId = session['userId'];
      final role = widget.role;
      final canApproveLeaves = _hasPermission('leaves_approve');

      final queryParts = <String>[];
      if (userId != null) queryParts.add('user_id=$userId');
      if (role.isNotEmpty) queryParts.add('role=${Uri.encodeComponent(role)}');
      queryParts.add('can_approve_leaves=$canApproveLeaves');

      String url = 'http://localhost:5000/api/hr/notifications';
      if (queryParts.isNotEmpty) {
        url += '?${queryParts.join('&')}';
      }

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && mounted) {
          setState(() {
            _unreadNotifCount = json['unreadCount'] ?? 0;
            _notifications = json['data'] ?? [];
          });
        }
      }
    } catch (_) {}
  }

  // 🔔 NOTIFICATIONS POPUP DIALOG
  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Notifications',
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      final session = await SessionManager.getUserSession();
                      final userId = session['userId'];
                      final role = widget.role;
                      final canApproveLeaves = _hasPermission('leaves_approve');

                      final queryParts = <String>[];
                      if (userId != null) queryParts.add('user_id=$userId');
                      if (role.isNotEmpty) queryParts.add('role=${Uri.encodeComponent(role)}');
                      queryParts.add('can_approve_leaves=$canApproveLeaves');

                      String url = 'http://localhost:5000/api/hr/notifications/mark-all-read';
                      if (queryParts.isNotEmpty) {
                        url += '?${queryParts.join('&')}';
                      }

                      await http.put(Uri.parse(url));
                      _fetchNotifications();
                    } catch (_) {}
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Mark all read', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              height: 380,
              child: _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_outlined, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                          const SizedBox(height: 10),
                          Text('No notifications yet', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                      itemBuilder: (ctx, i) {
                        final n = _notifications[i];
                        final isRead = n['is_read'] == 1 || n['is_read'] == true;
                        final type = n['type'] ?? 'GENERAL';
                        final dateStr = n['created_at'] != null ? n['created_at'].toString().split('T')[0] : '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: isRead
                                ? (isDark ? Colors.white10 : Colors.black12)
                                : const Color(0xFF059669).withValues(alpha: 0.2),
                            child: Icon(
                              type == 'LEAVE_REQUEST' ? Icons.event_note_rounded : Icons.notifications_rounded,
                              color: isRead ? (isDark ? Colors.white38 : Colors.black38) : const Color(0xFF10B981),
                              size: 18,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n['title'] ?? '',
                                  style: TextStyle(
                                    color: isDark ? (isRead ? Colors.white70 : Colors.white) : (isRead ? Colors.black54 : const Color(0xFF0F172A)),
                                    fontSize: 13,
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (dateStr.isNotEmpty)
                                Text(dateStr, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10.5)),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              n['message'] ?? '',
                              style: TextStyle(
                                color: isDark ? (isRead ? Colors.white38 : Colors.white70) : (isRead ? Colors.black38 : Colors.black87),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          onTap: () async {
                            try {
                              await http.put(Uri.parse('http://localhost:5000/api/hr/notifications/${n['notification_id']}/read'));
                              _fetchNotifications();
                            } catch (_) {}
                            if (mounted) {
                              Navigator.pop(ctx);
                              if (type == 'LEAVE_REQUEST') {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveManagementScreen()));
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
  }

  // 🔔 NOTIFICATION BELL BUTTON WITH RED BADGE WIDGET
  Widget _buildNotificationBell(bool isDark) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE2E8F0),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              size: 17,
              color: isDark ? Colors.white : const Color(0xFF475569),
            ),
            padding: EdgeInsets.zero,
            tooltip: 'Notifications',
            onPressed: () {
              _fetchNotifications();
              _showNotificationsDialog();
            },
          ),
        ),
        if (_unreadNotifCount > 0)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$_unreadNotifCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // 2. LOGOUT FUNCTION
  Future<void> _handleLogout() async {
    await SessionManager.clearSession();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  // 3. MOBILE BOTTOM BAR INDEX (4 CLEAN TABS)
  int _getBottomNavIndex() {
    switch (_selectedMenu) {
      case 'Dashboard':
        return 0;
      case 'HR & Employees':
        return 1;
      case 'Projects & Tasks':
        return 2;
      case 'Settings & Logs':
      default:
        return 3;
    }
  }

  void _onBottomNavTapped(int index) {
    setState(() {
      switch (index) {
        case 0:
          _selectedMenu = 'Dashboard';
          break;
        case 1:
          _selectedMenu = 'HR & Employees';
          _fetchLiveStats(); // 👈 Tab click karte hi turant database se fresh employees le aayega!
          break;
        case 2:
          _selectedMenu = 'Projects & Tasks';
          break;
        case 3:
          _selectedMenu = 'Settings & Logs';
          break;
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final isDashboard = _selectedMenu == 'Dashboard';

    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        return Scaffold(
          extendBody: !isDesktop,
          backgroundColor: Colors.transparent,
          body: BotanicalBackground(
            showThemeToggle: isDesktop,
            child: Column(
              children: [
                // Mobile top bar for every tab except the dashboard (which
                // carries its own greeting header).
                if (!isDesktop && !isDashboard) _buildMobileHeader(isDark),

                // Main body area
                Expanded(
                  child: Row(
                    children: [
                      // Desktop: frosted glass sidebar
                      if (isDesktop)
                        SizedBox(
                          width: 270,
                          child: _buildDesktopSidebar(),
                        ),

                      // Center workspace
                      Expanded(
                        child: Column(
                          children: [
                            if (isDesktop) _buildDesktopHeader(isDark),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(
                                  isDesktop ? 22.0 : (isDashboard ? 0.0 : 16.0),
                                  isDesktop ? 22.0 : (isDashboard ? 0.0 : 8.0),
                                  isDesktop ? 22.0 : (isDashboard ? 0.0 : 16.0),
                                  isDesktop ? 22.0 : 126.0,
                                ),
                                child: _buildSelectedTabContent(isDesktop),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 📱 Floating bottom navigation (mobile only)
          bottomNavigationBar:
              isDesktop ? null : _buildMobileBottomNav(isDark),
        );
      },
    );
  }

  // ================= 📱 FLOATING GLASS BOTTOM NAV =================
  Widget _buildMobileBottomNav(bool isDark) {
    const labels = ['Home', 'HR & Team', 'Projects', 'Profile'];
    const icons = [
      Icons.home_outlined,
      Icons.groups_outlined,
      Icons.assignment_outlined,
      Icons.person_outline_rounded,
    ];
    const activeIcons = [
      Icons.home_rounded,
      Icons.groups_rounded,
      Icons.assignment_rounded,
      Icons.person_rounded,
    ];

    final currentIndex = _getBottomNavIndex();

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111C2E) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: MobilePalette.border(isDark),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.07),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: List.generate(labels.length, (index) {
                final selected = currentIndex == index;
                final activeColor = isDark
                    ? MobilePalette.mint
                    : MobilePalette.emeraldDeep;
                final idleColor = MobilePalette.faint(isDark);

                return Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _onBottomNavTapped(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: selected
                              ? MobilePalette.emerald.withValues(
                                  alpha: isDark ? 0.16 : 0.10,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              selected ? activeIcons[index] : icons[index],
                              size: 20,
                              color: selected ? activeColor : idleColor,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected ? activeColor : idleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  // ================= 1. MOBILE TOP HEADER =================
  String _mobileTabTitle() {
    switch (_selectedMenu) {
      case 'HR & Employees':
        return 'HR & Team';
      case 'Projects & Tasks':
        return 'Projects & Tasks';
      case 'Settings & Logs':
        return 'Profile & Settings';
      default:
        return _selectedMenu;
    }
  }

  IconData _mobileTabIcon() {
    switch (_selectedMenu) {
      case 'HR & Employees':
        return Icons.groups_rounded;
      case 'Projects & Tasks':
        return Icons.assignment_rounded;
      case 'Settings & Logs':
        return Icons.person_rounded;
      case 'Inventory & Stock':
        return Icons.inventory_2_rounded;
      case 'Manufacturing & BOM':
        return Icons.precision_manufacturing_rounded;
      case 'Accounts & Finance':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }

  Widget _buildMobileHeader(bool isDark) {
    final textTitle = MobilePalette.title(isDark);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0B1220).withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.88),
        border: Border(
          bottom: BorderSide(
            color: MobilePalette.border(isDark),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
          child: Row(
            children: [
              MobileGradientIcon(
                icon: _mobileTabIcon(),
                color: MobilePalette.emerald,
                isDark: isDark,
                size: 36,
                iconSize: 17,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mobileTabTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.companyName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MobilePalette.faint(isDark),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _buildNotificationBell(isDark),
              const SizedBox(width: 6),
              _buildMobileDashboardMenu(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 2. DESKTOP FROSTED SIDEBAR =================
  Widget _buildDesktopSidebar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF030D08).withValues(alpha: 0.75),
            border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand Info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.precision_manufacturing_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.companyName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Plant Command Center',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Menu Items
              Expanded(
                child: ListView(
                  children: [
                    _buildNavItem(Icons.dashboard_outlined, 'Dashboard'),
                    if (_hasAnyHrAccess)
                      _buildNavItem(Icons.people_alt_outlined, 'HR & Employees'),
                    if (_hasPermission('tasks_view'))
                      _buildNavItem(Icons.assignment_outlined, 'Projects & Tasks'),
                    if (_hasPermission('inventory_view_stock'))
                      _buildNavItem(Icons.inventory_2_outlined, 'Inventory & Stock'),
                    if (_hasPermission('manufacturing_view_bom'))
                      _buildNavItem(Icons.factory_outlined, 'Manufacturing & BOM'),
                    if (_hasPermission('finance_view_reports'))
                      _buildNavItem(Icons.account_balance_wallet_outlined, 'Accounts & Finance'),
                    if (_hasPermission('system_audit_logs'))
                      _buildNavItem(Icons.settings_outlined, 'Settings & Logs'),
                  ],
                ),
              ),

              // Bottom Profile Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFF059669),
                      child: Text(
                        widget.adminEmail.isNotEmpty ? widget.adminEmail[0].toUpperCase() : 'A',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.adminEmail.split('@')[0],
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.role,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 19),
                      tooltip: 'Logout',
                      onPressed: _handleLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title) {
    final isSelected = _selectedMenu == title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selectedMenu = title),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF059669).withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 3. DESKTOP HEADER =================
  Widget _buildDesktopHeader(bool isDark) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF030D08).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Text(
            _selectedMenu,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const Spacer(),
          // 🔔 Live Notification Bell (with unread badge)
          _buildNotificationBell(isDark),
          const SizedBox(width: 145), // Space for floating theme toggle pill
        ],
      ),
    );
  }

  // ================= 4. DYNAMIC VIEW SWITCHER =================
  Widget _buildSelectedTabContent(bool isDesktop) {
    switch (_selectedMenu) {
      case 'Dashboard':
        return isDesktop ? _buildDashboardOverview() : _buildMobileDashboardView();
      case 'HR & Employees':
        if (!_hasAnyHrAccess) {
          return _buildAccessDeniedView('HR & Employees');
        }
        return MediaQuery.sizeOf(context).width < 700
            ? _buildMobileHrHub()
            : _buildHRHub();
      case 'Projects & Tasks':
        if (!_hasPermission('tasks_view')) {
          return _buildAccessDeniedView('Projects & Tasks');
        }
        return const ProjectTasksScreen();
      case 'Inventory & Stock':
        if (!_hasPermission('inventory_view_stock')) {
          return _buildAccessDeniedView('Inventory & Stock');
        }
        return _buildPlaceholderView('Raw Materials & Stock Levels', Icons.inventory_2_outlined);
      case 'Manufacturing & BOM':
        if (!_hasPermission('manufacturing_view_bom')) {
          return _buildAccessDeniedView('Manufacturing & BOM');
        }
        return _buildPlaceholderView('Production Floor & Bill of Materials', Icons.factory_outlined);
      case 'Accounts & Finance':
        if (!_hasPermission('finance_view_reports')) {
          return _buildAccessDeniedView('Accounts & Finance');
        }
        return _buildPlaceholderView('Accounts & Invoicing', Icons.account_balance_wallet_outlined);
      case 'Settings & Logs':
        // The mobile "Profile" tab is always reachable so users can switch
        // theme, inspect their workspace and log out.
        if (isDesktop && !_hasPermission('system_audit_logs')) {
          return _buildAccessDeniedView('Settings & Logs');
        }
        return _buildSettingsAndMoreView();
      default:
        return isDesktop ? _buildDashboardOverview() : _buildMobileDashboardView();
    }
  }

  Widget _buildAccessDeniedView(String moduleName) {
    final isDark = ThemeController.isDarkMode.value;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_person_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            Text(
              'Access Restricted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You do not have permission to access $moduleName.\nPlease contact your administrator if you need access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 📱 ULTRA-SLEEK MOBILE DASHBOARD (ADAPTIVE LIGHT / DARK) =================
  // ================= 📱 ULTRA-SLEEK MOBILE DASHBOARD (AURORA GLASS) =================
  String _mobileDateLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  Widget _buildMobileDashboardView() {
    final isDark = ThemeController.isDarkMode.value;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : (now.hour < 17 ? 'Good afternoon' : 'Good evening');
    final rawName = widget.adminEmail.isNotEmpty
        ? widget.adminEmail.split('@')[0]
        : 'Admin';
    final adminName = rawName.isNotEmpty
        ? (rawName[0].toUpperCase() + rawName.substring(1))
        : 'Admin';
    final adminInitial = adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A';
    final textTitle = MobilePalette.title(isDark);
    final textSub = MobilePalette.body(isDark);

    final totalTasks = _totalTasksCount;
    final doneTasks = (totalTasks - _pendingTasksCount).clamp(0, totalTasks);
    final taskProgress = totalTasks > 0 ? doneTasks / totalTasks : 0.0;
    final projectProgress =
        _totalProjects > 0 ? _completedProjects / _totalProjects : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. GREETING HEADER
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 12, 0),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: MobilePalette.emerald,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          adminInitial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: MobilePalette.emerald,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0B1220)
                                : Colors.white,
                            width: 2.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            greeting.toUpperCase(),
                            style: TextStyle(
                              color: isDark
                                  ? MobilePalette.mint
                                  : MobilePalette.emeraldDeep,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                          const Text(
                            '  👋',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        adminName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textTitle,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.role}  •  ${_mobileDateLabel(now)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSub,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _buildNotificationBell(isDark),
                const SizedBox(width: 8),
                _buildMobileDashboardMenu(isDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 2. HERO COMMAND CENTER CARD
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MobileGlassCard(
            isDark: isDark,
            gradient: MobilePalette.heroGradient(isDark),
            radius: 20,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            border: Border.all(
              color: MobilePalette.border(isDark),
            ),
            boxShadow: MobilePalette.softShadow(isDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MobileLivePill(label: 'LIVE', isDark: isDark),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: MobilePalette.border(isDark),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.factory_rounded,
                              size: 11,
                              color: isDark
                                  ? const Color(0xFFA7F3D0)
                                  : MobilePalette.emeraldDeep,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                widget.companyName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFFA7F3D0)
                                      : MobilePalette.emeraldDeep,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Command Center',
                            style: TextStyle(
                              color: textTitle,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Everything happening across your plant, in one glance.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSub,
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildMobileProgressRing(
                      value: taskProgress,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: MobilePalette.hairline(isDark),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: _buildMobileHeroStat(
                        icon: Icons.people_alt_rounded,
                        value: _isLoadingStats ? '—' : '$_totalEmployees',
                        label: 'Team',
                        color: MobilePalette.blue,
                        isDark: isDark,
                      ),
                    ),
                    _buildMobileHeroDivider(isDark),
                    Expanded(
                      child: _buildMobileHeroStat(
                        icon: Icons.task_alt_rounded,
                        value: _isLoadingStats ? '—' : '$_pendingTasksCount',
                        label: 'Pending',
                        color: MobilePalette.sky,
                        isDark: isDark,
                      ),
                    ),
                    _buildMobileHeroDivider(isDark),
                    Expanded(
                      child: _buildMobileHeroStat(
                        icon: Icons.assignment_turned_in_rounded,
                        value: _isLoadingStats ? '—' : '$_totalProjects',
                        label: 'Projects',
                        color: MobilePalette.violet,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 13,
                      color: isDark
                          ? MobilePalette.mint
                          : MobilePalette.emeraldDeep,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Task completion',
                      style: TextStyle(
                        color: textSub,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(taskProgress * 100).round()}%',
                      style: TextStyle(
                        color: isDark
                            ? MobilePalette.mint
                            : MobilePalette.emeraldDeep,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: taskProgress,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.09)
                        : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      MobilePalette.emerald,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),

        // 3. QUICK LAUNCH GRID
        MobileSectionHeader(
          title: 'Quick Launch',
          subtitle: 'One tap to every module',
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildMobileQuickLaunch(isDark),
        ),
        const SizedBox(height: 22),

        // 4. LIVE OVERVIEW
        MobileSectionHeader(
          title: 'Live Overview',
          subtitle: 'Synced with your plant right now',
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildMobileOverviewCard(
                  isDark: isDark,
                  title: 'Pending Tasks',
                  value: _isLoadingStats ? '—' : '$_pendingTasksCount',
                  subtitle: totalTasks > 0
                      ? '$doneTasks of $totalTasks completed'
                      : 'No tasks created yet',
                  icon: Icons.pending_actions_rounded,
                  color: MobilePalette.sky,
                  progress: taskProgress,
                  onTap: () =>
                      setState(() => _selectedMenu = 'Projects & Tasks'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMobileOverviewCard(
                  isDark: isDark,
                  title: 'Projects',
                  value: _isLoadingStats ? '—' : '$_totalProjects',
                  subtitle: _totalProjects > 0
                      ? '$_completedProjects delivered • $_pendingProjects active'
                      : 'No projects created yet',
                  icon: Icons.rocket_launch_rounded,
                  color: MobilePalette.violet,
                  progress: projectProgress,
                  onTap: () =>
                      setState(() => _selectedMenu = 'Projects & Tasks'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // 5. TEAM SPOTLIGHT
        if (_hasPermission('hr_view_directory')) ...[
          MobileSectionHeader(
            title: 'Team Spotlight',
            subtitle: _employees.isEmpty
                ? 'Build your workforce directory'
                : '${_employees.length} people across ${_departments.length} departments',
            actionLabel: 'See all',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EmployeeManagementScreen(),
              ),
            ).then((_) => _fetchLiveStats()),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildMobileTeamSpotlight(isDark),
          const SizedBox(height: 22),
        ],

        // 6. SECURITY / ROLE FOOTER
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MobileGlassCard(
            isDark: isDark,
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            onTap: () => setState(() => _selectedMenu = 'Settings & Logs'),
            child: Row(
              children: [
                MobileGradientIcon(
                  icon: Icons.verified_user_rounded,
                  color: MobilePalette.emerald,
                  isDark: isDark,
                  size: 36,
                  iconSize: 17,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Workspace secured',
                        style: TextStyle(
                          color: textTitle,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Role-based access is active for ${widget.role}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textSub, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: MobilePalette.faint(isDark),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMobileDashboardMenu(bool isDark) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.95),
        ),
      ),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'More',
        icon: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: isDark ? Colors.white : const Color(0xFF475569),
        ),
        onSelected: (value) {
          switch (value) {
            case 'theme':
              ThemeController.toggleTheme();
              break;
            case 'settings':
              setState(() => _selectedMenu = 'Settings & Logs');
              break;
            case 'logout':
              _handleLogout();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'theme',
            child: Row(
              children: [
                Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: 17,
                  color: isDark
                      ? MobilePalette.amber
                      : const Color(0xFF475569),
                ),
                const SizedBox(width: 10),
                Text(isDark ? 'Switch to light' : 'Switch to dark'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 17, color: Color(0xFF475569)),
                SizedBox(width: 10),
                Text('Settings & profile'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 17, color: Colors.redAccent),
                SizedBox(width: 10),
                Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileProgressRing({
    required double value,
    required bool isDark,
  }) {
    final pct = (value * 100).round().clamp(0, 100);
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value <= 0 ? 0.015 : value,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? MobilePalette.mint : MobilePalette.emeraldDeep,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$pct%',
                style: TextStyle(
                  color: MobilePalette.title(isDark),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              Text(
                'done',
                style: TextStyle(
                  color: MobilePalette.faint(isDark),
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeroStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: MobilePalette.title(isDark),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: MobilePalette.faint(isDark),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileHeroDivider(bool isDark) {
    return Container(
      width: 1,
      height: 30,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE2E8F0),
    );
  }

  Widget _buildMobileQuickLaunch(bool isDark) {
    final tiles = <Widget>[];

    if (_hasPermission('hr_view_directory')) {
      tiles.add(
        MobileActionTile(
          label: 'Team',
          icon: Icons.people_alt_rounded,
          color: MobilePalette.blue,
          isDark: isDark,
          onTap: () => setState(() => _selectedMenu = 'HR & Employees'),
        ),
      );
    }
    if (_hasPermission('attendance_view_logs') ||
        _hasPermission('attendance_import_excel')) {
      tiles.add(
        MobileActionTile(
          label: 'Attendance',
          icon: Icons.fingerprint_rounded,
          color: MobilePalette.rose,
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AttendanceScreen()),
          ),
        ),
      );
    }
    if (_hasPermission('leaves_apply') || _hasPermission('leaves_approve')) {
      tiles.add(
        MobileActionTile(
          label: 'Leaves',
          icon: Icons.event_available_rounded,
          color: MobilePalette.violet,
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LeaveManagementScreen()),
          ),
        ),
      );
    }
    if (_hasPermission('tasks_view')) {
      tiles.add(
        MobileActionTile(
          label: 'Projects',
          icon: Icons.assignment_rounded,
          color: MobilePalette.sky,
          isDark: isDark,
          onTap: () =>
              setState(() => _selectedMenu = 'Projects & Tasks'),
        ),
      );
    }
    if (_hasPermission('inventory_view_stock')) {
      tiles.add(
        MobileActionTile(
          label: 'Inventory',
          icon: Icons.inventory_2_rounded,
          color: const Color(0xFF0D9488),
          isDark: isDark,
          onTap: () => setState(() => _selectedMenu = 'Inventory & Stock'),
        ),
      );
    }
    if (_hasPermission('manufacturing_view_bom')) {
      tiles.add(
        MobileActionTile(
          label: 'Production',
          icon: Icons.precision_manufacturing_rounded,
          color: const Color(0xFFF97316),
          isDark: isDark,
          onTap: () =>
              setState(() => _selectedMenu = 'Manufacturing & BOM'),
        ),
      );
    }
    if (_hasPermission('finance_view_reports')) {
      tiles.add(
        MobileActionTile(
          label: 'Finance',
          icon: Icons.account_balance_wallet_rounded,
          color: MobilePalette.emerald,
          isDark: isDark,
          onTap: () => setState(() => _selectedMenu = 'Accounts & Finance'),
        ),
      );
    }
    tiles.add(
      MobileActionTile(
        label: 'More',
        icon: Icons.grid_view_rounded,
        color: const Color(0xFF64748B),
        isDark: isDark,
        onTap: () => setState(() => _selectedMenu = 'Settings & Logs'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        const gap = 10.0;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final tileWidth = (available - gap * (columns - 1)) / columns;
        // Keep room for the icon plus a two-line label even on 320px screens.
        const minTileHeight = 108.0;
        final naturalHeight = tileWidth / 0.80;
        final tileHeight =
            naturalHeight < minTileHeight ? minTileHeight : naturalHeight;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: tileWidth / tileHeight,
          children: tiles,
        );
      },
    );
  }

  Widget _buildMobileOverviewCard({
    required bool isDark,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required double progress,
    required VoidCallback onTap,
  }) {
    final textTitle = MobilePalette.title(isDark);
    final textSub = MobilePalette.body(isDark);

    return MobileGlassCard(
      isDark: isDark,
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MobileGradientIcon(
                icon: icon,
                color: color,
                isDark: isDark,
                size: 34,
                iconSize: 16,
              ),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                size: 14,
                color: MobilePalette.faint(isDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: textTitle,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: textTitle,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textSub,
              fontSize: 10,
              height: 1.35,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: MobilePalette.hairline(isDark),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTeamSpotlight(bool isDark) {
    if (_employees.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MobileGlassCard(
          isDark: isDark,
          radius: 20,
          padding: const EdgeInsets.all(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EmployeeManagementScreen(),
            ),
          ).then((_) => _fetchLiveStats()),
          child: Row(
            children: [
              MobileGradientIcon(
                icon: Icons.person_add_alt_1_rounded,
                color: MobilePalette.blue,
                isDark: isDark,
                size: 42,
                iconSize: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add your first team member',
                      style: TextStyle(
                        color: MobilePalette.title(isDark),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Onboard staff to unlock rosters, attendance and payroll insights.',
                      style: TextStyle(
                        color: MobilePalette.body(isDark),
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 17,
                color: MobilePalette.faint(isDark),
              ),
            ],
          ),
        ),
      );
    }

    const avatarColors = [
      MobilePalette.emerald,
      MobilePalette.blue,
      MobilePalette.violet,
      MobilePalette.amber,
      MobilePalette.cyan,
      MobilePalette.rose,
    ];

    final count = _employees.length > 8 ? 8 : _employees.length;

    return SizedBox(
      height: 146,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final raw = _employees[index];
          final emp = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};
          final name = (emp['full_name'] ?? 'Staff Member').toString();
          final code = (emp['emp_code'] ?? 'EMP').toString();
          final desig = (emp['designation'] ?? 'Team Member').toString();
          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
          final color = avatarColors[index % avatarColors.length];
          final isTopPerformer = index < 3;

          return SizedBox(
            width: 168,
            child: MobileGlassCard(
              isDark: isDark,
              radius: 20,
              padding: const EdgeInsets.all(13),
              onTap: () => _openEmployeeFromMobile(emp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.20 : 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: isDark
                                  ? Color.lerp(color, Colors.white, 0.35)
                                  : color,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isTopPerformer)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MobilePalette.amber.withValues(
                              alpha: isDark ? 0.20 : 0.14,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 9,
                                color: MobilePalette.amber,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'A+',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MobilePalette.title(isDark),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desig,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MobilePalette.body(isDark),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: MobilePalette.emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobilePalette.faint(isDark),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEmployeeFromMobile(Map<String, dynamic> emp) async {
    final session = await SessionManager.getUserSession();
    final isOwnProfile =
        session['userId'] != null && session['userId'] == emp['user_id'];
    final canViewLifecycle = _hasPermission('hr_view_lifecycle');

    if (!mounted) return;

    if (canViewLifecycle || isOwnProfile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmployeeDetailsScreen(employeeId: emp['employee_id']),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🔒 Access denied: you cannot view another staff member\'s profile.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ================= 📊 EXECUTIVE COMMAND DASHBOARD OVERVIEW (FROSTED GLASS) =================
  Widget _buildDashboardOverview() {
    final isDark = ThemeController.isDarkMode.value;

    // 🪟 ASLI FROSTED GLASS COLORS (Translucent so blur shines through!)
    final cardBg = isDark
        ? const Color(0xFF030D08).withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.42);
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF334155);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.7); // Crisp frosted border

    final adminName = widget.adminEmail.isNotEmpty ? widget.adminEmail.split('@')[0] : 'Admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. WELCOME HEADER BANNER (NO PLANT WORD!)
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.waving_hand_rounded, color: Color(0xFF059669), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back, $adminName 👋', style: TextStyle(color: textTitle, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text('Workspace Active • Everything is running smoothly today.', style: TextStyle(color: textSub, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 13),
                        SizedBox(width: 6),
                        Text('System Online', style: TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 2. 4 LUXURY FROSTED GLASS KPI CARDS
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 550 ? 2 : 1);
            return GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: crossAxisCount == 1 ? 2.6 : 1.7,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // 1. Total Employees Card
                _buildGlassKpiCard(
                  'Total Employees',
                  _isLoadingStats ? '...' : '$_totalEmployees Active',
                  Icons.people_outline,
                  const Color(0xFF2563EB),
                  'Active Staff Verified',
                  cardBg, cardBorder, textTitle, textSub, isDark,
                ),

                // 2. Assigned Tasks Card (Ab Clickable hai & "/" ke sath dikhega)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _selectedMenu = 'Projects & Tasks'),
                  child: _buildGlassKpiCard(
                    'Assigned Tasks',
                    _isLoadingStats ? '...' : '$_pendingTasksCount / $_totalTasksCount Pending',
                    Icons.assignment_turned_in_outlined,
                    const Color(0xFFD97706),
                    'Click to View Tasks • In-Progress',
                    cardBg, cardBorder, textTitle, textSub, isDark,
                  ),
                ),

                // 3. Departments Card (Clickable)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _openDepartmentManagementDialog,
                  child: _buildGlassKpiCard(
                    'Departments',
                    _isLoadingStats ? '...' : '${_departments.length} Units',
                    Icons.domain_rounded,
                    const Color(0xFF7C3AED),
                    'Click to Manage • Allocations',
                    cardBg, cardBorder, textTitle, textSub, isDark,
                  ),
                ),

                // 4. Pending Projects Card (Ab "/" ke sath: 2 / 2 In-Progress)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _selectedMenu = 'Projects & Tasks'),
                  child: _buildGlassKpiCard(
                    'Pending Projects',
                    _isLoadingStats ? '...' : '$_pendingProjects / $_totalProjects In-Progress',
                    Icons.pending_actions_rounded,
                    const Color(0xFF059669),
                    _completedProjects > 0 ? '$_completedProjects Completed' : 'Active & Planning',
                    cardBg, cardBorder, textTitle, textSub, isDark,
                  ),
                ),

                // Note: Agar aap "Completed Projects" ka 5th card alag se rakhna chahte hain toh rakh sakte hain,
                // warna upar ke 4 cards ek perfect single row banayenge!
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // 3. TWO RICH PANELS WITH FROSTED BLUR
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 900;
            return isNarrow
                ? Column(
              children: [
                _buildLiveAttendanceFeedPanel(cardBg, cardBorder, textTitle, textSub, isDark),
                const SizedBox(height: 18),
                _buildQuickOperationsPanel(cardBg, cardBorder, textTitle, textSub, isDark),
              ],
            )
                : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: _buildLiveAttendanceFeedPanel(cardBg, cardBorder, textTitle, textSub, isDark),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: _buildQuickOperationsPanel(cardBg, cardBorder, textTitle, textSub, isDark),
                ),
              ],
            );
          },
        ),
      ],
    );
  }


  // ================= 🏢 DEPARTMENT MANAGEMENT SCREEN (VIEW, ADD, EDIT, DELETE, MEMBERS) =================
  void _openDepartmentManagementDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DepartmentsScreen(),
      ),
    ).then((_) {
      _fetchLiveStats();
    });
  }

  // Add / Edit Department Sub-Dialog with Real-Time Staff Member Assignment
  void _openAddEditDeptDialog(Map<String, dynamic>? deptToEdit, StateSetter setParentModalState) async {
    if (!_hasPermission('hr_manage_departments')) return;
    // 1. Fetch latest employees from backend to ensure up-to-date staff list
    try {
      final empRes = await http.get(Uri.parse('http://localhost:5000/api/hr/employees'));
      if (empRes.statusCode == 200) {
        final empData = jsonDecode(empRes.body);
        if (empData['success'] == true && empData['data'] is List) {
          _employees = empData['data'];
        }
      }
    } catch (_) {}

    if (!mounted) return;

    final isEditing = deptToEdit != null;
    final nameCtrl = TextEditingController(text: isEditing ? (deptToEdit['name'] ?? '') : '');
    final searchCtrl = TextEditingController();

    final targetDeptId = isEditing ? int.tryParse(deptToEdit['department_id']?.toString() ?? '') : null;
    final targetDeptName = isEditing ? (deptToEdit['name'] ?? '').toString().trim().toLowerCase() : '';

    // Pre-populate selected members currently assigned to this department
    final Set<int> selectedMemberIds = {};
    if (isEditing) {
      for (var emp in _employees) {
        final empId = int.tryParse(emp['employee_id']?.toString() ?? '');
        final empDeptId = int.tryParse(emp['department_id']?.toString() ?? '');
        final empDeptName = (emp['department_name'] ?? '').toString().trim().toLowerCase();

        if (empId != null) {
          if (targetDeptId != null && empDeptId == targetDeptId) {
            selectedMemberIds.add(empId);
          } else if (targetDeptName.isNotEmpty && empDeptName == targetDeptName) {
            selectedMemberIds.add(empId);
          }
        }
      }
    }

    bool isSaving = false;
    String filterQuery = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = ThemeController.isDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0);
          final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
          final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
          final listBg = isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFF8FAFC);

          final filteredEmployees = _employees.where((emp) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            final name = (emp['full_name'] ?? '').toString().toLowerCase();
            final code = (emp['emp_code'] ?? '').toString().toLowerCase();
            final desig = (emp['designation'] ?? '').toString().toLowerCase();
            return name.contains(q) || code.contains(q) || desig.contains(q);
          }).toList();

          final allFilteredSelected = filteredEmployees.isNotEmpty &&
              filteredEmployees.every((e) => selectedMemberIds.contains(int.tryParse(e['employee_id']?.toString() ?? '')));

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 540,
              constraints: const BoxConstraints(maxHeight: 680),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: dialogBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.1),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEditing ? Icons.edit_note_rounded : Icons.domain_add_rounded,
                          color: const Color(0xFF059669),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing ? 'Edit Department & Staff' : 'Create New Department',
                              style: TextStyle(color: textTitle, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEditing
                                  ? 'Update department name and allocate team members'
                                  : 'Name the department and assign initial team members',
                              style: TextStyle(color: textSub, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: textSub, size: 20),
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Department Name Input
                  Text(
                    'Department Name',
                    style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      hintText: 'e.g. Quality Control, Finance, R&D',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.7), fontSize: 13),
                      prefixIcon: const Icon(Icons.apartment_rounded, color: Color(0xFF7C3AED), size: 19),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cardBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF059669), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Members Header & Quick Select
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, color: Color(0xFF2563EB), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Assigned Staff Members',
                        style: TextStyle(color: textTitle, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${selectedMemberIds.length} Selected',
                          style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      if (filteredEmployees.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: isSaving
                              ? null
                              : () {
                                  setDialogState(() {
                                    if (allFilteredSelected) {
                                      for (var e in filteredEmployees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null) selectedMemberIds.remove(eid);
                                      }
                                    } else {
                                      for (var e in filteredEmployees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null) selectedMemberIds.add(eid);
                                      }
                                    }
                                  });
                                },
                          child: Text(
                            allFilteredSelected ? 'Clear All' : 'Select All',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Mini Search Bar for Staff
                  TextField(
                    controller: searchCtrl,
                    enabled: !isSaving,
                    onChanged: (val) => setDialogState(() => filterQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search staff by name, code or designation...',
                      hintStyle: TextStyle(color: textSub.withValues(alpha: 0.6), fontSize: 12),
                      prefixIcon: Icon(Icons.search_rounded, color: textSub, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cardBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Scrollable Member Checklist
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 250, minHeight: 120),
                      decoration: BoxDecoration(
                        color: listBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: _employees.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text('No active employees found in system.\nAdd employees in HR Management first.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textSub, fontSize: 12)),
                              ),
                            )
                          : filteredEmployees.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text('No employees match "$filterQuery"',
                                        style: TextStyle(color: textSub, fontSize: 12)),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: filteredEmployees.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: cardBorder.withValues(alpha: 0.4)),
                                  itemBuilder: (context, idx) {
                                    final emp = filteredEmployees[idx];
                                    final empId = int.tryParse(emp['employee_id']?.toString() ?? '') ?? 0;
                                    final isSelected = selectedMemberIds.contains(empId);
                                    final empDeptName = (emp['department_name'] ?? '').toString().trim();
                                    final isCurrentlyInThisDept = isEditing &&
                                        ((targetDeptId != null && int.tryParse(emp['department_id']?.toString() ?? '') == targetDeptId) ||
                                            (targetDeptName.isNotEmpty && empDeptName.toLowerCase() == targetDeptName));

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: isSaving
                                          ? null
                                          : () {
                                              setDialogState(() {
                                                if (isSelected) {
                                                  selectedMemberIds.remove(empId);
                                                } else {
                                                  selectedMemberIds.add(empId);
                                                }
                                              });
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        child: Row(
                                          children: [
                                            // Avatar
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: isSelected
                                                  ? const Color(0xFF059669).withValues(alpha: 0.18)
                                                  : const Color(0xFF64748B).withValues(alpha: 0.12),
                                              child: Text(
                                                (emp['full_name'] != null && emp['full_name'].toString().isNotEmpty)
                                                    ? emp['full_name'].toString()[0].toUpperCase()
                                                    : 'E',
                                                style: TextStyle(
                                                  color: isSelected ? const Color(0xFF059669) : textSub,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            // Name & designation
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    emp['full_name'] ?? 'Staff',
                                                    style: TextStyle(
                                                      color: textTitle,
                                                      fontSize: 13,
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        '${emp['emp_code'] ?? 'EMP'} • ${emp['designation'] ?? 'Staff'}',
                                                        style: TextStyle(color: textSub, fontSize: 11),
                                                      ),
                                                      if (empDeptName.isNotEmpty) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: isCurrentlyInThisDept
                                                                ? const Color(0xFF059669).withValues(alpha: 0.12)
                                                                : Colors.amber.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            isCurrentlyInThisDept ? 'This Dept' : empDeptName,
                                                            style: TextStyle(
                                                              color: isCurrentlyInThisDept ? const Color(0xFF059669) : Colors.amber.shade800,
                                                              fontSize: 9.5,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Checkbox
                                            Checkbox(
                                              value: isSelected,
                                              activeColor: const Color(0xFF059669),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              onChanged: isSaving
                                                  ? null
                                                  : (val) {
                                                      setDialogState(() {
                                                        if (val == true) {
                                                          selectedMemberIds.add(empId);
                                                        } else {
                                                          selectedMemberIds.remove(empId);
                                                        }
                                                      });
                                                    },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Dialog Footer Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textSub,
                          side: BorderSide(color: cardBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter a department name'), backgroundColor: Colors.orangeAccent),
                                  );
                                  return;
                                }

                                setDialogState(() => isSaving = true);

                                if (isEditing) {
                                  final deptId = deptToEdit['department_id'];
                                  try {
                                    final res = await http.put(
                                      Uri.parse('http://localhost:5000/api/hr/departments/$deptId'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode({
                                        'name': name,
                                        'member_ids': selectedMemberIds.toList(),
                                      }),
                                    );

                                    if (res.statusCode == 200) {
                                      // Update in-memory employee list
                                      for (var e in _employees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null) {
                                          if (selectedMemberIds.contains(eid)) {
                                            e['department_id'] = deptId;
                                            e['department_name'] = name;
                                          } else if (e['department_id']?.toString() == deptId.toString() ||
                                              e['department_name'] == deptToEdit['name']) {
                                            e['department_id'] = null;
                                            e['department_name'] = null;
                                          }
                                        }
                                      }

                                      deptToEdit['name'] = name;
                                      deptToEdit['member_count'] = selectedMemberIds.length;
                                      setParentModalState(() {});
                                      if (mounted) setState(() {});

                                      Navigator.pop(dialogCtx);
                                      _fetchLiveStats(); // background re-sync

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Department "$name" and ${selectedMemberIds.length} members updated!'),
                                          backgroundColor: const Color(0xFF059669),
                                        ),
                                      );
                                    } else {
                                      setDialogState(() => isSaving = false);
                                      final err = jsonDecode(res.body)['message'] ?? 'Failed to update department';
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Database Error: $err'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  } catch (_) {
                                    setDialogState(() => isSaving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('⚠️ Backend Server ya MySQL band hai! Please check connection.'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                } else {
                                  // Create New Department
                                  try {
                                    final res = await http.post(
                                      Uri.parse('http://localhost:5000/api/hr/departments'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode({
                                        'name': name,
                                        'member_ids': selectedMemberIds.toList(),
                                      }),
                                    );

                                    if (res.statusCode == 201) {
                                      final data = jsonDecode(res.body)['data'];
                                      final newDeptId = data['department_id'];

                                      for (var e in _employees) {
                                        final eid = int.tryParse(e['employee_id']?.toString() ?? '');
                                        if (eid != null && selectedMemberIds.contains(eid)) {
                                          e['department_id'] = newDeptId;
                                          e['department_name'] = name;
                                        }
                                      }

                                      setParentModalState(() => _departments.add(data));
                                      if (mounted) setState(() {});

                                      Navigator.pop(dialogCtx);
                                      _fetchLiveStats(); // background re-sync

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Department "$name" created with ${selectedMemberIds.length} members!'),
                                          backgroundColor: const Color(0xFF059669),
                                        ),
                                      );
                                    } else {
                                      setDialogState(() => isSaving = false);
                                      final err = jsonDecode(res.body)['message'] ?? 'Failed to create department';
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Database Error: $err'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  } catch (_) {
                                    setDialogState(() => isSaving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('⚠️ Backend Server ya MySQL band hai! Please check connection.'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(isEditing ? 'Save Changes' : 'Create Department'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Delete Department Confirmation
  void _confirmDeleteDept(Map<String, dynamic> dept, StateSetter setParentModalState) {
    if (!_hasPermission('hr_manage_departments')) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Department?'),
        content: Text('Are you sure you want to delete "${dept['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                final res = await http.delete(Uri.parse('http://localhost:5000/api/hr/departments/${dept['department_id']}'));
                if (res.statusCode == 200) {
                  setParentModalState(() {
                    _departments.removeWhere((d) => d['department_id'] == dept['department_id']);
                  });
                  if (mounted) setState(() {});
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Department "${dept['name']}" deleted.'), backgroundColor: Colors.redAccent),
                  );
                } else {
                  final err = jsonDecode(res.body)['message'] ?? 'Failed to delete';
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: Colors.orangeAccent),
                  );
                }
              } catch (_) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // 🪟 REAL FROSTED GLASS KPI CARD (Blur + Translucent)
  Widget _buildGlassKpiCard(
      String label,
      String value,
      IconData icon,
      Color color,
      String subtext,
      Color bg,
      Color border,
      Color textTitle,
      Color textSub,
      bool isDark,
      ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                ],
              ),
              Text(value, style: TextStyle(color: textTitle, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(subtext, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // 📋 PANEL 1: LIVE BIOMETRIC ATTENDANCE FEED TABLE
  Widget _buildLiveAttendanceFeedPanel(Color bg, Color border, Color textTitle, Color textSub, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Biometric Check-in Roster', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Machine verification records for today', style: TextStyle(color: textSub, fontSize: 12)),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_forward, size: 14),
                    label: const Text('View All Logs'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                    onPressed: () {
                      if (_hasPermission('attendance_view_logs')) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessDeniedScreen(moduleTitle: 'Biometric Punch Logs')));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Single Row for Ramesh Patel (Live data)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF059669).withValues(alpha: 0.2),
                      child: const Text('RP', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ramesh Patel', style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('EMP-101 • Biometric Machine #1001', style: TextStyle(color: textSub, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('09:15 AM • Present', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 3),
                        Text('Shift: On-Time', style: TextStyle(color: textSub, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Audit Summary Tag
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF0284C7), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '100% of staff registered on offline biometric machine. No late penalties today.',
                        style: TextStyle(color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1), fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⚡ PANEL 2: FAST SHORTCUT OPERATIONS & WORK ORDERS
  Widget _buildQuickOperationsPanel(Color bg, Color border, Color textTitle, Color textSub, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick Management Shortcuts', style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('One-click access to active business modules', style: TextStyle(color: textSub, fontSize: 12)),
              const SizedBox(height: 16),

              // 1. Employee Directory Shortcut
              _buildShortcutTile(
                title: 'Employee Directory',
                subtitle: 'Add new workers, update salaries & codes',
                icon: Icons.person_add_alt_1,
                color: const Color(0xFF2563EB),
                isDark: isDark,
                textTitle: textTitle,
                textSub: textSub,
                onTap: () {
                  if (_hasPermission('hr_view_directory')) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessDeniedScreen(moduleTitle: 'Employee Directory')));
                  }
                },
              ),
              const SizedBox(height: 10),

              // 2. Biometric Upload Shortcut
              _buildShortcutTile(
                title: 'Upload Biometric Excel',
                subtitle: 'Process offline face machine log dump',
                icon: Icons.upload_file_outlined,
                color: const Color(0xFF059669),
                isDark: isDark,
                textTitle: textTitle,
                textSub: textSub,
                onTap: () {
                  if (_hasPermission('attendance_import_excel')) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessDeniedScreen(moduleTitle: 'Biometric Attendance Upload')));
                  }
                },
              ),
              const SizedBox(height: 10),

              // 3. Leave Approvals Shortcut
              _buildShortcutTile(
                title: 'Staff Leave Approvals',
                subtitle: 'Manage casual, sick & unpaid leaves',
                icon: Icons.event_available_outlined,
                color: const Color(0xFFD97706),
                isDark: isDark,
                textTitle: textTitle,
                textSub: textSub,
                onTap: () {
                  if (_hasPermission('leaves_approve')) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveManagementScreen()));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessDeniedScreen(moduleTitle: 'Staff Leave Approvals')));
                  }
                },
              ),
              const SizedBox(height: 10),

              // 4. Department Hierarchy Shortcut
              _buildShortcutTile(
                title: 'Department Hierarchy & Units',
                subtitle: 'Manage corporate divisions & staff rosters',
                icon: Icons.apartment_rounded,
                color: const Color(0xFF7C3AED),
                isDark: isDark,
                textTitle: textTitle,
                textSub: textSub,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DepartmentsScreen()),
                  ).then((_) => _fetchLiveStats());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Color textTitle,
    required Color textSub,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(color: textSub, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: textSub, size: 18),
          ],
        ),
      ),
    );
  }

  // ================= 5. LUXURY HR & TEAM PERFORMANCE (IMAGE 2 STYLE) =================
  // ================= 📱 MOBILE HR HUB (AURORA GLASS) =================
  Widget _buildMobileHrHub() {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = MobilePalette.title(isDark);
    final textSub = MobilePalette.body(isDark);

    final tiles = <Widget>[];
    if (_hasPermission('hr_view_directory')) {
      tiles.add(
        _buildMobileHrTile(
          isDark: isDark,
          title: 'Employee Directory',
          subtitle: '${_employees.length} staff enrolled',
          icon: Icons.badge_outlined,
          color: MobilePalette.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EmployeeManagementScreen(),
            ),
          ).then((_) => _fetchLiveStats()),
        ),
      );
    }
    if (_hasPermission('attendance_view_logs') ||
        _hasPermission('attendance_import_excel')) {
      tiles.add(
        _buildMobileHrTile(
          isDark: isDark,
          title: 'Biometric Logs',
          subtitle: 'Daily machine punches',
          icon: Icons.fingerprint_rounded,
          color: MobilePalette.emerald,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AttendanceScreen()),
          ),
        ),
      );
    }
    if (_hasPermission('leaves_apply') || _hasPermission('leaves_approve')) {
      tiles.add(
        _buildMobileHrTile(
          isDark: isDark,
          title: 'Staff Leaves',
          subtitle: 'Apply & approvals',
          icon: Icons.event_busy_rounded,
          color: MobilePalette.amber,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LeaveManagementScreen(),
            ),
          ),
        ),
      );
    }
    if (_hasPermission('salary_manage_increment')) {
      tiles.add(
        _buildMobileHrTile(
          isDark: isDark,
          title: 'Salary Increment',
          subtitle: 'Hike & appraisals',
          icon: Icons.trending_up_rounded,
          color: MobilePalette.violet,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SalaryIncrementScreen(),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Team Performance',
                      style: TextStyle(
                        color: textTitle,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Roster, biometric logs & appraisals in one place',
                      style: TextStyle(
                        color: textSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MobileLivePill(label: 'LIVE', isDark: isDark),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Appraisal hero
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MobileGlassCard(
            isDark: isDark,
            gradient: MobilePalette.heroGradient(isDark),
            radius: 20,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            border: Border.all(
              color: MobilePalette.border(isDark),
            ),
            boxShadow: MobilePalette.softShadow(isDark),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appraisal Index',
                            style: TextStyle(
                              color: textTitle,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rolling 30-day workforce score',
                            style: TextStyle(
                              color: textSub,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: MobilePalette.emerald.withValues(
                          alpha: isDark ? 0.16 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Top 5%',
                        style: TextStyle(
                          color: isDark
                              ? MobilePalette.mint
                              : MobilePalette.emeraldDeep,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedDonutChart(
                  centerTitle: '94.8%',
                  centerSubtitle: 'Appraisal Index',
                  size: 152,
                  strokeWidth: 19,
                  segments: const [
                    ChartSegment(
                      label: 'Attendance',
                      value: 45,
                      color: Color(0xFF22C55E),
                    ),
                    ChartSegment(
                      label: 'Tasks',
                      value: 35,
                      color: Color(0xFF0284C7),
                    ),
                    ChartSegment(
                      label: 'Quality',
                      value: 20,
                      color: Color(0xFFF59E0B),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: MobileMetricPill(
                        icon: Icons.people_alt_rounded,
                        label: 'TEAM',
                        value: '${_employees.length}',
                        color: MobilePalette.blue,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: MobileMetricPill(
                        icon: Icons.apartment_rounded,
                        label: 'DEPTS',
                        value: '${_departments.length}',
                        color: MobilePalette.violet,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: MobileMetricPill(
                        icon: Icons.fingerprint_rounded,
                        label: 'ON-TIME',
                        value: '98%',
                        color: MobilePalette.emerald,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),

        // HR operations
        MobileSectionHeader(
          title: 'HR Operations',
          subtitle: 'One tap to every people workflow',
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (tiles.isEmpty) {
                return MobileGlassCard(
                  isDark: isDark,
                  radius: 20,
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No HR modules are enabled for your role yet.',
                    style: TextStyle(color: textSub, fontSize: 12),
                  ),
                );
              }
              final isWide = constraints.maxWidth >= 560;
              final isNarrow = constraints.maxWidth < 330;
              return GridView.count(
                crossAxisCount: isWide ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isWide ? 1.35 : (isNarrow ? 1.05 : 1.24),
                children: tiles,
              );
            },
          ),
        ),
        const SizedBox(height: 22),

        // Team spotlight
        if (_hasPermission('hr_view_directory')) ...[
          MobileSectionHeader(
            title: 'Team Members',
            subtitle: _employees.isEmpty
                ? 'Add your first employee'
                : '${_employees.length} people in your plant',
            actionLabel: 'See all',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EmployeeManagementScreen(),
              ),
            ).then((_) => _fetchLiveStats()),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildMobileTeamSpotlight(isDark),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildMobileHrTile({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MobileGlassCard(
      isDark: isDark,
      radius: 18,
      padding: const EdgeInsets.all(13),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MobileGradientIcon(
                icon: icon,
                color: color,
                isDark: isDark,
                size: 36,
                iconSize: 17,
              ),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                size: 14,
                color: MobilePalette.faint(isDark),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MobilePalette.title(isDark),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MobilePalette.body(isDark),
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHRHub() {
    final isDark = ThemeController.isDarkMode.value;
    // Solid background taaki leaves text ke beech na aayin
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP HEADER + ZERO-OVERFLOW SCROLLABLE ACTIONS
        Text(
          'Team Performance',
          style: TextStyle(color: textTitle, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Text(
          'Workforce roster, biometric machine records & appraisals',
          style: TextStyle(color: textSub, fontSize: 12),
        ),
        const SizedBox(height: 14),




        // 2. HERO DONUT RING CARD (Exact Image 2 Vibe)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: AnimatedDonutChart(
              centerTitle: '94.8%',
              centerSubtitle: 'Appraisal Index',
              size: 190,
              strokeWidth: 24,
              // Image 2 jaisa 3 vibrant multi-color segments: Green, Blue, Orange!
              segments: const [
                ChartSegment(label: 'Attendance (98%)', value: 45, color: Color(0xFF22C55E)), // Emerald Green
                ChartSegment(label: 'Tasks (94%)', value: 35, color: Color(0xFF0284C7)), // Electric Blue
                ChartSegment(label: 'Quality (96%)', value: 20, color: Color(0xFFF59E0B)), // Amber Orange
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 3. SECTION TITLE: "Performance Breakdown"
        Text(
          'Performance Breakdown',
          style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        // 4. INDIVIDUAL BREAKDOWN CARDS (Side-by-Side 3 Compact Cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 850;
            return isDesktop
                ? Row(
              children: [
                // Card 1
                Expanded(
                  child: _buildBreakdownCard(
                    icon: Icons.fingerprint_rounded,
                    title: 'Attendance & Punctuality',
                    subtitle: '98% on-time shift record',
                    percentText: '98%',
                    trendText: '+2.4%',
                    progressValue: 0.98,
                    progressColor: const Color(0xFF22C55E),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 14),

                // Card 2
                Expanded(
                  child: _buildBreakdownCard(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Production Tasks Done',
                    subtitle: '94% work orders completed',
                    percentText: '94%',
                    trendText: '+3.1%',
                    progressValue: 0.94,
                    progressColor: const Color(0xFF0284C7),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 14),

                // Card 3
                Expanded(
                  child: _buildBreakdownCard(
                    icon: Icons.verified_user_rounded,
                    title: 'Quality & Zero Defects',
                    subtitle: '96% defect-free QA output',
                    percentText: '96%',
                    trendText: '+1.5%',
                    progressValue: 0.96,
                    progressColor: const Color(0xFFF59E0B),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),
                ),
              ],
            )
                : Column(
              children: [
                _buildBreakdownCard(
                  icon: Icons.fingerprint_rounded,
                  title: 'Attendance & Punctuality',
                  subtitle: '98% on-time shift record',
                  percentText: '98%',
                  trendText: '+2.4%',
                  progressValue: 0.98,
                  progressColor: const Color(0xFF22C55E),
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                  textTitle: textTitle,
                  textSub: textSub,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildBreakdownCard(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Production Tasks Done',
                  subtitle: '94% work orders completed',
                  percentText: '94%',
                  trendText: '+3.1%',
                  progressValue: 0.94,
                  progressColor: const Color(0xFF0284C7),
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                  textTitle: textTitle,
                  textSub: textSub,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildBreakdownCard(
                  icon: Icons.verified_user_rounded,
                  title: 'Quality & Zero Defects',
                  subtitle: '96% defect-free QA output',
                  percentText: '96%',
                  trendText: '+1.5%',
                  progressValue: 0.96,
                  progressColor: const Color(0xFFF59E0B),
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                  textTitle: textTitle,
                  textSub: textSub,
                  isDark: isDark,
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // 🏷️ SECTION TITLE: HR OPERATIONS & MANAGEMENT
        Text(
          'HR Operations & Management',
          style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // 🎴 3 LUXURY ACTION CARDS (Desktop pe 3 Columns, Mobile pe 1 Column)
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final columns = constraints.maxWidth > 1000
                ? 4
                : (constraints.maxWidth > 560 ? 2 : 1);
            final cardWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            // Fixed visual height per row so content never gets clipped.
            final cardHeight = columns == 1 ? 172.0 : 176.0;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              childAspectRatio: cardWidth / cardHeight,
              children: [
                // 1. Sirf tab dikhega jab View Directory ON ho
                if (_hasPermission('hr_view_directory'))
                  _buildHrFeatureCard(
                    title: 'Employee Directory',
                    badgeText: '${_employees.length} Staff Enrolled',
                    subtitle: 'Manage staff profiles, designations, contacts & onboarding.',
                    icon: Icons.badge_outlined,
                    color: const Color(0xFF2563EB),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementScreen())),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),

                // 2. Sirf tab dikhega jab Attendance Logs ya Import ON ho
                if (_hasPermission('attendance_view_logs') || _hasPermission('attendance_import_excel'))
                  _buildHrFeatureCard(
                    title: 'Biometric Import',
                    badgeText: 'Daily Machine Logs',
                    subtitle: 'Upload Excel biometric punch dumps & track staff punctuality.',
                    icon: Icons.fingerprint_rounded,
                    color: const Color(0xFF059669),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen())),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),

                // 3. Sirf tab dikhega jab Apply ya Approve Leaves ON ho
                if (_hasPermission('leaves_apply') || _hasPermission('leaves_approve'))
                  _buildHrFeatureCard(
                    title: 'Staff Leaves',
                    badgeText: 'Apply & Approvals',
                    subtitle: 'Submit leave requests & view time-off status.',
                    icon: Icons.event_busy_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaveManagementScreen())),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),

                // 4. Salary Increment & Appraisal Card (Sirf permission walon ko dikhega)
                if (_hasPermission('salary_manage_increment'))
                  _buildHrFeatureCard(
                    title: 'Salary Increment',
                    badgeText: 'Hike & Appraisal',
                    subtitle: 'Manage salary increments, performance appraisals & promotion letters.',
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SalaryIncrementScreen()),
                    ),
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textTitle: textTitle,
                    textSub: textSub,
                    isDark: isDark,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // 5. REAL WORKFORCE MEMBERS ROSTER + VIEW ALL STAFF BUTTON
        if (_hasPermission('hr_view_directory')) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Active Team Members (${_employees.length})',
                style: TextStyle(color: textTitle, fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementScreen())),
              icon: const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF10B981)),
              label: const Text('View All Staff', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_employees.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
            child: Center(
              child: Text('No employees found. Click "View All Staff" to add employees.', style: TextStyle(color: textSub, fontSize: 12)),
            ),
          )
        else
          ..._employees.take(4).map((emp) {
            final name = emp['full_name'] ?? 'Staff Member';
            final code = emp['emp_code'] ?? 'EMP';
            final dept = emp['department_name'] ?? 'Operations';
            final desig = emp['designation'] ?? 'Staff';
            final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // 👈 Staff member click - Guarded with hr_view_lifecycle
                  onTap: () async {
                    final session = await SessionManager.getUserSession();
                    final isOwnProfile = session['userId'] != null && session['userId'] == emp['user_id'];
                    final canViewLifecycle = _hasPermission('hr_view_lifecycle');

                    if (canViewLifecycle || isOwnProfile) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmployeeDetailsScreen(employeeId: emp['employee_id']),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🔒 Access Denied: Aapke paas dusre staff ki profile & lifecycle dekhne ki permission nahi hai.'),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                          child: Text(initial, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text('$code • $desig • $dept', style: TextStyle(color: textSub, fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Grade A+', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, size: 20, color: textSub),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  // ================= 👤 EMPLOYEE PERSONAL PERFORMANCE & DETAILS MODAL =================
  // ================= 👤 EMPLOYEE PERSONAL PERFORMANCE & LIVE DATA MODAL =================
  void _openEmployeePerformanceDialog(Map<String, dynamic> emp) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = ThemeController.isDarkMode.value;
        final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
        final cardBorder = isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0);
        final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

        final name = emp['full_name'] ?? 'Staff Member';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'E';
        final code = emp['emp_code'] ?? 'EMP';
        final dept = emp['department_name'] ?? 'Operations';
        final desig = emp['designation'] ?? 'Staff';
        final bioId = emp['biometric_emp_code'] ?? code;
        final branch = emp['branch_name'] ?? 'Main Plant';

        return FutureBuilder<http.Response>(
          // 👈 Backend se is employee ka live performance data manga rahe hain
          future: http.get(Uri.parse('http://localhost:5000/api/hr/employees/${emp['employee_id']}/performance')),
          builder: (context, snapshot) {
            Map<String, dynamic> perf = {};
            bool isLoading = snapshot.connectionState == ConnectionState.waiting;

            if (snapshot.hasData && snapshot.data!.statusCode == 200) {
              final json = jsonDecode(snapshot.data!.body);
              if (json['success'] == true && json['data'] != null) {
                perf = json['data'];
              }
            }

            // Real Data Extract (With safe defaults agar load ho raha ho)
            final ratingStars = (perf['rating_stars'] ?? '4.8').toString();
            final grade = (perf['grade'] ?? 'Grade A+').toString();
            final attRate = double.tryParse((perf['attendance_rate'] ?? '98.0').toString()) ?? 98.0;
            final taskRate = double.tryParse((perf['task_rate'] ?? '100.0').toString()) ?? 100.0;
            final completedTasks = perf['completed_tasks'] ?? 0;
            final totalTasks = perf['total_tasks'] ?? 0;
            final presentDays = perf['present_days'] ?? 0;
            final totalDays = perf['total_days'] ?? 0;
            final qualityScore = double.tryParse((perf['quality_score'] ?? '96.0').toString()) ?? 96.0;
            final safetyScore = double.tryParse((perf['safety_score'] ?? '99.0').toString()) ?? 99.0;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: Container(
                width: 520,
                decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 35, offset: const Offset(0, 15)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. TOP GRADIENT BANNER
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF047857), Color(0xFF10B981)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.white.withValues(alpha: 0.25),
                                child: Text(initial, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text('$desig • $dept', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => Navigator.pop(ctx),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. MODAL BODY
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isLoading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
                                )
                              else ...[
                                // 3 Live Real KPI Badges
                                Row(
                                  children: [
                                    _buildEmpKpiBadge('Rating', '$ratingStars ★', grade, const Color(0xFFF59E0B), cardBg, cardBorder, textTitle, textSub),
                                    const SizedBox(width: 8),
                                    _buildEmpKpiBadge('Attendance', '$attRate%', totalDays > 0 ? '$presentDays / $totalDays Days' : 'On-Time', const Color(0xFF10B981), cardBg, cardBorder, textTitle, textSub),
                                    const SizedBox(width: 8),
                                    _buildEmpKpiBadge('Tasks Done', '$taskRate%', totalTasks > 0 ? '$completedTasks / $totalTasks' : 'All Clear', const Color(0xFF0284C7), cardBg, cardBorder, textTitle, textSub),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // Personal Performance Breakdown Bars (Real Values)
                                Text('Personal Performance Analysis', style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),

                                _buildEmpBarItem('Shift Punctuality', (attRate / 100).clamp(0.0, 1.0), '$attRate%', const Color(0xFF10B981), textTitle, textSub, isDark),
                                const SizedBox(height: 10),
                                _buildEmpBarItem('Production Tasks Done', (taskRate / 100).clamp(0.0, 1.0), '$taskRate%', const Color(0xFF0284C7), textTitle, textSub, isDark),
                                const SizedBox(height: 10),
                                _buildEmpBarItem('QA & Zero Defects Output', (qualityScore / 100).clamp(0.0, 1.0), '$qualityScore%', const Color(0xFFF59E0B), textTitle, textSub, isDark),
                                const SizedBox(height: 10),
                                _buildEmpBarItem('Safety & Machine Protocols', (safetyScore / 100).clamp(0.0, 1.0), '$safetyScore%', const Color(0xFF047857), textTitle, textSub, isDark),
                                const SizedBox(height: 20),

                                // Employment Details Box (Real Database Data)
                                Text('Workforce Records', style: TextStyle(color: textTitle, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  child: Column(
                                    children: [
                                      _buildEmpDetailRow('Employee Code', code, textTitle, textSub),
                                      const Divider(height: 16),
                                      _buildEmpDetailRow('Biometric Machine ID', bioId, textTitle, textSub),
                                      const Divider(height: 16),
                                      _buildEmpDetailRow('Plant / Branch', branch, textTitle, textSub),
                                      const Divider(height: 16),
                                      _buildEmpDetailRow('Lifecycle Status', 'Active Staff', const Color(0xFF10B981), textSub, isStatus: true),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 22),
                              ],

                              // Action Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('Close', style: TextStyle(color: textTitle)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF059669),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        elevation: 0,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()));
                                      },
                                      icon: const Icon(Icons.person_search_rounded, size: 16),
                                      label: const Text('Full Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
      },
    );
  }

  // Helper: Mini KPI Badge inside modal
  Widget _buildEmpKpiBadge(String title, String value, String sub, Color color, Color bg, Color border, Color textTitle, Color textSub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: textSub, fontSize: 10.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: textSub, fontSize: 9.5)),
          ],
        ),
      ),
    );
  }

  // Helper: Progress bar row inside modal
  Widget _buildEmpBarItem(String label, double val, String percent, Color color, Color textTitle, Color textSub, bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: textTitle, fontSize: 12, fontWeight: FontWeight.w500)),
            Text(percent, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: val,
            minHeight: 5,
            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // Helper: Key-Value row inside modal
  Widget _buildEmpDetailRow(String label, String value, Color valueColor, Color textSub, {bool isStatus = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: textSub, fontSize: 12)),
        isStatus
            ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: valueColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
          child: Text(value, style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.bold)),
        )
            : Text(value, style: TextStyle(color: valueColor, fontSize: 12.5, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // 🎴 HELPER 1: IMAGE 2 STYLE INDIVIDUAL BREAKDOWN CARD
  Widget _buildBreakdownCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String percentText,
    required String trendText,
    required double progressValue,
    required Color progressColor,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Left Soft Rounded Icon Box (Image 2 style)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: progressColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: textTitle, fontSize: 13.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: textSub, fontSize: 11)),
                  ],
                ),
              ),
              // Right: Value + Upward Trend Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(percentText, style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up_rounded, size: 14, color: progressColor),
                      const SizedBox(width: 2),
                      Text(trendText, style: TextStyle(color: progressColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Bottom Rounded Mini Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 5.5,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  // 🎴 LUXURY HR FEATURE CARD (Clean, Modern & Interactive)
  Widget _buildHrFeatureCard({
    required String title,
    required String badgeText,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: textTitle, fontSize: 20, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: textSub, fontSize: 11.5, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Open Console',
                      style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, color: color, size: 13),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🏷️ HELPER 2: ACTION CHIP FOR TOP HEADER
  Widget _buildHrActionChip(String label, IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // 🍩 CARD 1: ANIMATED CIRCULAR DONUT GRAPH (Exact Reference Image Style)
  Widget _buildPerformanceGraphCard(Color bg, Color border, Color textTitle, Color textSub) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Performance Distribution', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Overall: 94.8%', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 🍩 ANIMATED SEGMENTED DONUT CHART
              const AnimatedDonutChart(
                centerTitle: '94.8%',
                centerSubtitle: 'Appraisal Score',
                size: 200,
                strokeWidth: 32,
                segments: [
                  ChartSegment(label: 'Punctuality', value: 30, color: Color(0xFF10B981)),
                  ChartSegment(label: 'Task Execution', value: 25, color: Color(0xFF059669)),
                  ChartSegment(label: 'Assembly Quality', value: 20, color: Color(0xFF047857)),
                  ChartSegment(label: 'Zero Defects', value: 15, color: Color(0xFF065F46)),
                  ChartSegment(label: 'Machine Safety', value: 10, color: Color(0xFF064E3B)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⭐ CARD 2: EMPLOYEE APPRAISAL SCORECARD
  Widget _buildAppraisalScorecard(Color bg, Color border, Color textTitle, Color textSub) {
    final isDark = ThemeController.isDarkMode.value; // Clean isDark definition

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Appraisal Breakdown', style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                  Row(
                    children: const [
                      Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
                      SizedBox(width: 4),
                      Text('4.8 / 5.0', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Progress Bar 1: Attendance
              _buildMetricProgressBar('Attendance Punctuality', 0.98, '98%', const Color(0xFF10B981), textTitle, textSub),
              const SizedBox(height: 16),

              // Progress Bar 2: Task Completion
              _buildMetricProgressBar('Production Tasks Done', 0.94, '94%', const Color(0xFF0284C7), textTitle, textSub),
              const SizedBox(height: 16),

              // Progress Bar 3: Quality Check
              _buildMetricProgressBar('Quality & Zero Defects', 0.96, '96%', const Color(0xFF8B5CF6), textTitle, textSub),
              const SizedBox(height: 24),

              // Feedback Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Quarter Appraisal: Eligible for Performance Incentive',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartBar(String month, double heightFraction, String label, bool isPeak, Color textSub) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: isPeak ? const Color(0xFF10B981) : textSub, fontSize: 10.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          width: 34,
          height: 120 * heightFraction,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isPeak
                  ? const [Color(0xFF059669), Color(0xFF34D399)]
                  : [const Color(0xFF0284C7).withValues(alpha: 0.6), const Color(0xFF38BDF8)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(month, style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }


  Widget _buildMetricProgressBar(String title, double fraction, String percentText, Color color, Color textTitle, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: textTitle, fontSize: 12.5, fontWeight: FontWeight.w500)),
            Text(percentText, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            backgroundColor: Colors.black.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
  // Helper Widget: Mini Stat Card
  Widget _buildHrMiniStat(String label, String value, IconData icon, Color color, Color bg, Color border, Color textTitle, Color textSub) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: TextStyle(color: textSub, fontSize: 11.5)),
                    Text(value, style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper Widget: Big Action Card
  Widget _buildHrActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color cardBorder,
    required Color textTitle,
    required Color textSub,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: textSub, size: 18),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: textTitle, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: textSub, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderView(String title, IconData icon) {
    final isDark = ThemeController.isDarkMode.value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: MobileGlassCard(
        isDark: isDark,
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 36),
        child: Column(
          children: [
            MobileGradientIcon(
              icon: icon,
              color: MobilePalette.emerald,
              isDark: isDark,
              size: 64,
              iconSize: 28,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MobilePalette.title(isDark),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This module is being calibrated for launch. Everything else keeps running as usual.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MobilePalette.body(isDark),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            MobileLivePill(
              label: 'COMING SOON',
              isDark: isDark,
              color: MobilePalette.amber,
            ),
          ],
        ),
      ),
    );
  }

  // ⚙️ PROFILE & SETTINGS (Adaptive, mobile-first)
  Widget _buildSettingsAndMoreView() {
    final isDark = ThemeController.isDarkMode.value;
    final textTitle = MobilePalette.title(isDark);
    final textSub = MobilePalette.body(isDark);

    final rawName = widget.adminEmail.isNotEmpty
        ? widget.adminEmail.split('@')[0]
        : 'Admin';
    final displayName = rawName.isNotEmpty
        ? (rawName[0].toUpperCase() + rawName.substring(1))
        : 'Admin';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile hero
            MobileGlassCard(
              isDark: isDark,
              gradient: MobilePalette.heroGradient(isDark),
              radius: 20,
              padding: const EdgeInsets.all(17),
              border: Border.all(
                color: MobilePalette.border(isDark),
              ),
              boxShadow: MobilePalette.softShadow(isDark),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: MobilePalette.emerald,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: MobilePalette.emerald,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF111C2E)
                                  : Colors.white,
                              width: 2.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textTitle,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.adminEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 7),
                        MobileLivePill(
                          label: widget.role.toUpperCase(),
                          isDark: isDark,
                          color: MobilePalette.violet,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Appearance
            MobileSectionHeader(title: 'Appearance', isDark: isDark),
            const SizedBox(height: 10),
            MobileGlassCard(
              isDark: isDark,
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  MobileGradientIcon(
                    icon: isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: isDark
                        ? MobilePalette.violet
                        : MobilePalette.amber,
                    isDark: isDark,
                    size: 40,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDark ? 'Dark mode' : 'Light mode',
                          style: TextStyle(
                            color: textTitle,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isDark
                              ? 'Slate surfaces with calmer contrast'
                              : 'Neutral surfaces with emerald accents',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSub,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isDark,
                    onChanged: (_) => ThemeController.toggleTheme(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Workspace
            MobileSectionHeader(title: 'Workspace', isDark: isDark),
            const SizedBox(height: 10),
            MobileGlassCard(
              isDark: isDark,
              radius: 20,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              child: Column(
                children: [
                  _buildMobileInfoRow(
                    icon: Icons.business_rounded,
                    label: 'COMPANY',
                    value: widget.companyName,
                    isDark: isDark,
                  ),
                  Divider(color: MobilePalette.hairline(isDark), height: 1),
                  _buildMobileInfoRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'SIGNED IN AS',
                    value: widget.adminEmail,
                    isDark: isDark,
                  ),
                  Divider(color: MobilePalette.hairline(isDark), height: 1),
                  _buildMobileInfoRow(
                    icon: Icons.shield_rounded,
                    label: 'ACCESS ROLE',
                    value: widget.role,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Session
            MobileSectionHeader(title: 'Session', isDark: isDark),
            const SizedBox(height: 10),
            MobileGlassCard(
              isDark: isDark,
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: _handleLogout,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(
                        alpha: isDark ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sign out',
                          style: TextStyle(
                            color: textTitle,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'End this session on this device',
                          style: TextStyle(
                            color: textSub,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: MobilePalette.faint(isDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'APEX ERP  •  MOBILE BUILD 1.0.0',
                style: TextStyle(
                  color: MobilePalette.faint(isDark),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: isDark
                ? Colors.white.withValues(alpha: 0.55)
                : const Color(0xFF64748B),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: MobilePalette.faint(isDark),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobilePalette.title(isDark),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }
}

// ================= 🚫 ACCESS DENIED FULL SCREEN =================
class AccessDeniedScreen extends StatelessWidget {
  final String moduleTitle;

  const AccessDeniedScreen({super.key, required this.moduleTitle});

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.isDarkMode.value;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textTitle = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return Scaffold(
      body: BotanicalBackground(
        showThemeToggle: false,
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_person_rounded, size: 54, color: Colors.redAccent),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Permission Denied',
                    style: TextStyle(color: textTitle, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You do not have permission to access "$moduleTitle".\nPlease contact your System Administrator to request access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSub, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


