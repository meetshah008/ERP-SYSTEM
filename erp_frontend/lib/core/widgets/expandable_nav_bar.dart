import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Expandable Floating Navigation Bar for Mobile Only.
///
/// Starts as a 54px circular button showing a ">" chevron.
/// When tapped, it expands into a horizontal pill (~280px) and reveals
/// staggered module icons: Home, HR & Team, Projects, Profile, and a "<" close chevron.
class ExpandableNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  const ExpandableNavBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
  });

  @override
  State<ExpandableNavBar> createState() => _ExpandableNavBarState();
}

class _ExpandableNavBarState extends State<ExpandableNavBar>
    with SingleTickerProviderStateMixin {
  static const double _collapsedSize = 54.0;
  static const double _expandedWidth = 280.0;
  static const double _height = 54.0;

  late final AnimationController _controller;
  late final Animation<double> _widthCurve;
  late final List<Animation<double>> _itemAnimations;

  static const List<_NavItemData> _items = [
    _NavItemData(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    _NavItemData(
      label: 'HR & Team',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
    ),
    _NavItemData(
      label: 'Projects',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
    ),
    _NavItemData(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );

    _widthCurve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Staggered icon fade & slide (starts when pill is ~60% open, ~40ms stagger)
    _itemAnimations = List.generate(_items.length, (index) {
      final start = (0.60 + (index * 0.05)).clamp(0.0, 0.95);
      final end = (start + 0.20).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOut),
        reverseCurve: Interval(start, end, curve: Curves.easeIn),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    if (_controller.value > 0.5) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void _handleItemTap(int index) {
    widget.onItemSelected(index);
    // User jab tak chevron button '<' na dabaye, yeh open hi rahega
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final currentWidth =
        lerpDouble(_collapsedSize, _expandedWidth, _widthCurve.value)!;

        return Container(
          width: currentWidth,
          height: _height,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181B) : Colors.white,
            borderRadius: BorderRadius.circular(_height / 2),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE4E4E7),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 18.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          // OverflowBox keeps the chevron anchored on the rightmost 54px slot,
          // so the chevron stays visible while collapsed and during expansion.
          child: OverflowBox(
            minWidth: _expandedWidth,
            maxWidth: _expandedWidth,
            minHeight: _height,
            maxHeight: _height,
            alignment: Alignment.centerRight,
            child: Row(
              children: [
                const SizedBox(width: 4),
                // 4 Module Nav Items
                for (int i = 0; i < _items.length; i++)
                  Expanded(
                    child: _buildNavItem(
                      context: context,
                      data: _items[i],
                      index: i,
                      isSelected: widget.currentIndex == i,
                      colorScheme: colorScheme,
                      progress: _itemAnimations[i].value,
                    ),
                  ),

                // Chevron Toggle Button (">" when closed, rotated to "<" when open)
                _buildToggleButton(
                  context: context,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required _NavItemData data,
    required int index,
    required bool isSelected,
    required ColorScheme colorScheme,
    required double progress,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isSelected
        ? (isDark ? const Color(0xFF09090B) : Colors.white)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF71717A));

    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 8.0 * (1.0 - progress)),
        child: Semantics(
          label: data.label,
          selected: isSelected,
          button: true,
          child: Tooltip(
            message: data.label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _controller.value > 0.7 ? () => _handleItemTap(index) : null,
                borderRadius: BorderRadius.circular(23),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 46.0,
                    minHeight: 46.0,
                  ),
                  child: Center(
                    child: Container(
                      width: 36.0,
                      height: 36.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? (isDark ? Colors.white : const Color(0xFF18181B))
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Icon(
                          isSelected ? data.activeIcon : data.icon,
                          size: 20.0,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required BuildContext context,
    required ColorScheme colorScheme,
  }) {
    final isOpen = _controller.value > 0.5;
    final label = isOpen ? 'Close navigation' : 'Open navigation';

    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(27),
            child: SizedBox(
              width: _collapsedSize,
              height: _height,
              child: Center(
                // Rotates 180 degrees from ">" (angle 0) to "<" (angle pi)
                child: Transform.rotate(
                  angle: _controller.value * math.pi,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 22.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItemData({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}