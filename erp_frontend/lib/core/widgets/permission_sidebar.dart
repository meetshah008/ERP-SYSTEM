import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../theme/enterprise_theme.dart';
import '../utils/display_name.dart';

/// Reusable, permission-driven sidebar for every non-Super-Admin role.
///
/// Desktop/web only (the dashboard renders it only at width >= 900).
/// Clean obsidian slate panel with muted slate links and emerald active pills.
class PermissionSidebar extends StatefulWidget {
  const PermissionSidebar({
    super.key,
    required this.groups,
    required this.companyName,
    required this.role,
    required this.userName,
    required this.activeNavId,
    required this.activeMenu,
    required this.onItemSelected,
    required this.onLogout,
  });

  final List<AppNavGroup> groups;
  final String companyName;
  final String role;
  final String userName;
  final String activeNavId;
  final String activeMenu;
  final ValueChanged<AppNavItem> onItemSelected;
  final VoidCallback onLogout;

  @override
  State<PermissionSidebar> createState() => _PermissionSidebarState();
}

class _PermissionSidebarState extends State<PermissionSidebar> {
  late final Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.groups.map((g) => g.id).toSet();
  }

  @override
  void didUpdateWidget(covariant PermissionSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.groups.map((g) => g.id).toSet();
    // Keep the user's collapse choices, but open any newly granted group.
    _expanded.addAll(current);
    _expanded.removeWhere((id) => !current.contains(id));
  }

  bool _isActive(AppNavItem item) {
    if (widget.activeNavId == item.id) return true;
    if (item.targetMenu != null && widget.activeMenu == item.targetMenu) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EnterpriseColors.sidebar,
        border: Border(
          right: BorderSide(color: EnterpriseColors.sidebarDeep, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrand(),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                for (final group in widget.groups) ...[
                  if (group.label.isNotEmpty) _buildGroupHeader(group),
                  if (group.label.isNotEmpty && !_expanded.contains(group.id))
                    const SizedBox(height: 2),
                  if (_expanded.contains(group.id))
                    for (final item in group.items)
                      _buildItem(item, indented: group.label.isNotEmpty),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          _buildProfileCard(),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(EnterpriseRadius.md),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/app_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cleanCompanyName(widget.companyName).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const Text(
                'Plant Command Center',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader(AppNavGroup group) {
    final expanded = _expanded.contains(group.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadius.sm),
        hoverColor: EnterpriseColors.sidebarHover,
        onTap: () {
          setState(() {
            if (expanded) {
              _expanded.remove(group.id);
            } else {
              _expanded.add(group.id);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(group.icon,
                  size: 15, color: EnterpriseColors.sidebarMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    color: EnterpriseColors.sidebarMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 16,
                color: EnterpriseColors.sidebarMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(AppNavItem item, {required bool indented}) {
    final selected = _isActive(item);
    return Padding(
      padding: EdgeInsets.only(
        left: indented ? 12.0 : 0.0,
        bottom: 4.0,
      ),
      child: Tooltip(
        message: item.description ?? item.label,
        preferBelow: false,
        child: InkWell(
          borderRadius: BorderRadius.circular(EnterpriseRadius.md),
          hoverColor: selected
              ? EnterpriseColors.emeraldDeep
              : EnterpriseColors.sidebarHover,
          onTap: () => widget.onItemSelected(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? EnterpriseColors.emerald
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(EnterpriseRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 19,
                  color: selected
                      ? Colors.white
                      : EnterpriseColors.sidebarMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Colors.white
                          : EnterpriseColors.sidebarMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.opensScreen)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.9)
                        : EnterpriseColors.textMuted.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final roleInfo = _roleVisuals(widget.role);
    final initial = widget.userName.trim().isEmpty
        ? 'U'
        : widget.userName.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EnterpriseColors.sidebarDeep,
        borderRadius: BorderRadius.circular(EnterpriseRadius.lg),
        border: Border.all(color: EnterpriseColors.sidebarHover),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: EnterpriseColors.emerald,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleInfo.color.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(EnterpriseRadius.pill),
                    border: Border.all(
                      color: roleInfo.color.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(roleInfo.icon, size: 9, color: roleInfo.color),
                      const SizedBox(width: 3),
                      Text(
                        roleInfo.label,
                        style: TextStyle(
                          color: roleInfo.color,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                color: Color(0xFFF87171), size: 18),
            tooltip: 'Logout',
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: widget.onLogout,
          ),
        ],
      ),
    );
  }
}

class _RoleVisuals {
  const _RoleVisuals({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;
}

_RoleVisuals _roleVisuals(String role) {
  final clean = role.trim().isEmpty ? 'Employee' : role.trim();
  final lower = clean.toLowerCase();
  if (lower.contains('super admin') || lower == 'admin') {
    return const _RoleVisuals(
      color: Color(0xFFC4B5FD),
      icon: Icons.shield_rounded,
      label: 'SUPER ADMIN',
    );
  }
  if (lower.contains('manager') || lower.contains('supervisor')) {
    return const _RoleVisuals(
      color: Color(0xFF7DD3FC),
      icon: Icons.verified_user_rounded,
      label: 'MANAGER',
    );
  }
  return _RoleVisuals(
    color: const Color(0xFF6EE7B7),
    icon: Icons.badge_rounded,
    label: clean.toUpperCase(),
  );
}
