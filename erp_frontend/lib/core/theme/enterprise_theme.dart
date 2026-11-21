import 'package:flutter/material.dart';

/// Desktop/web design tokens for the clean enterprise UI.
///
/// MOBILE IS DELIBERATELY EXCLUDED: none of these helpers are used by the
/// existing mobile widgets (`MobilePalette`, `MobileWallpaper`, `mobile_ui.dart`).
/// Apply them only inside desktop branches (`MediaQuery.sizeOf(context).width >= 900`).
abstract final class EnterpriseColors {
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color canvasAlt = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color emerald = Color(0xFF059669);
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color emeraldSoft = Color(0xFFECFDF5);
  static const Color emeraldSoftBorder = Color(0xFFA7F3D0);

  static const Color sidebar = Color(0xFF13241B);
  static const Color sidebarDeep = Color(0xFF0F172A);
  static const Color sidebarHover = Color(0xFF1E293B);
  static const Color sidebarMuted = Color(0xFF94A3B8);

  static const Color amberSoft = Color(0xFFFEF3C7);
  static const Color amberText = Color(0xFF92400E);
  static const Color amberBorder = Color(0xFFFDE68A);

  static const Color skySoft = Color(0xFFE0F2FE);
  static const Color skyText = Color(0xFF0369A1);
  static const Color skyBorder = Color(0xFFBAE6FD);

  static const Color violetSoft = Color(0xFFEDE9FE);
  static const Color violetText = Color(0xFF5B21B6);
  static const Color violetBorder = Color(0xFFDDD6FE);

  static const Color roseSoft = Color(0xFFFFE4E6);
  static const Color roseText = Color(0xFF9F1239);
  static const Color roseBorder = Color(0xFFFECDD3);

  static const Color slateSoft = Color(0xFFF1F5F9);
  static const Color slateText = Color(0xFF475569);
}

abstract final class EnterpriseRadius {
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double pill = 999;
}

abstract final class EnterpriseTheme {
  /// Same threshold as the dashboard so desktop-only styling never leaks to
  /// the mobile layout.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  static BoxDecoration card({
    Color color = EnterpriseColors.surface,
    Color borderColor = EnterpriseColors.border,
    double radius = EnterpriseRadius.lg,
    bool shadow = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x0D000000), // rgba(0,0,0,0.05)
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );
  }

  static BoxDecoration softChip({
    required Color background,
    required Color border,
  }) {
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(EnterpriseRadius.pill),
      border: Border.all(color: border),
    );
  }

  static InputDecoration input({
    String? hint,
    String label = 'Search',
    Widget? prefix,
    Widget? suffix,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      prefixIcon: prefix ?? const Icon(Icons.search_rounded, size: 18),
      suffixIcon: suffix ?? const EnterpriseShortcutHint(),
      filled: true,
      fillColor: EnterpriseColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EnterpriseRadius.md),
        borderSide: const BorderSide(color: EnterpriseColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EnterpriseRadius.md),
        borderSide: const BorderSide(color: EnterpriseColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EnterpriseRadius.md),
        borderSide: const BorderSide(
          color: EnterpriseColors.emerald,
          width: 1.5,
        ),
      ),
    );
  }
}

class EnterpriseShortcutHint extends StatelessWidget {
  const EnterpriseShortcutHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: EnterpriseColors.slateSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: EnterpriseColors.border),
        ),
        child: const Text(
          '⌘K',
          style: TextStyle(
            color: EnterpriseColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

enum EnterpriseStatus { active, inProgress, done, pending, danger, info, neutral }

/// Soft-background, bold-text status chip used by every desktop module.
class EnterpriseStatusChip extends StatelessWidget {
  const EnterpriseStatusChip(
    this.label, {
    super.key,
    this.status = EnterpriseStatus.neutral,
    this.count,
  });

  final String label;
  final EnterpriseStatus status;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    final text = count == null ? label : '$label · $count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: EnterpriseTheme.softChip(
        background: style.background,
        border: style.border,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: style.foreground,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

_StatusStyle _styleFor(EnterpriseStatus status) {
  switch (status) {
    case EnterpriseStatus.active:
    case EnterpriseStatus.done:
      return const _StatusStyle(
        background: EnterpriseColors.emeraldSoft,
        border: EnterpriseColors.emeraldSoftBorder,
        foreground: EnterpriseColors.emeraldDeep,
      );
    case EnterpriseStatus.inProgress:
      return const _StatusStyle(
        background: EnterpriseColors.amberSoft,
        border: EnterpriseColors.amberBorder,
        foreground: EnterpriseColors.amberText,
      );
    case EnterpriseStatus.pending:
      return const _StatusStyle(
        background: EnterpriseColors.violetSoft,
        border: EnterpriseColors.violetBorder,
        foreground: EnterpriseColors.violetText,
      );
    case EnterpriseStatus.danger:
      return const _StatusStyle(
        background: EnterpriseColors.roseSoft,
        border: EnterpriseColors.roseBorder,
        foreground: EnterpriseColors.roseText,
      );
    case EnterpriseStatus.info:
      return const _StatusStyle(
        background: EnterpriseColors.skySoft,
        border: EnterpriseColors.skyBorder,
        foreground: EnterpriseColors.skyText,
      );
    case EnterpriseStatus.neutral:
      return const _StatusStyle(
        background: EnterpriseColors.slateSoft,
        border: EnterpriseColors.border,
        foreground: EnterpriseColors.slateText,
      );
  }
}

/// Clean white surface with 12px corners, 1px border and a soft shadow.
class EnterpriseCard extends StatelessWidget {
  const EnterpriseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.color = EnterpriseColors.surface,
    this.borderColor = EnterpriseColors.border,
    this.radius = EnterpriseRadius.lg,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final double radius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: EnterpriseTheme.card(
        color: color,
        borderColor: borderColor,
        radius: radius,
        shadow: showShadow,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

/// Segmented control / pill toggle for desktop filters.
class EnterpriseSegmented<T> extends StatelessWidget {
  const EnterpriseSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labels,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, String>? labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EnterpriseColors.slateSoft,
        borderRadius: BorderRadius.circular(EnterpriseRadius.md),
        border: Border.all(color: EnterpriseColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            _Segment<T>(
              option: option,
              label: labels?[option] ?? option.toString(),
              selected: value == option,
              onTap: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final T option;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EnterpriseRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? EnterpriseColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(EnterpriseRadius.sm),
          border: selected
              ? Border.all(color: EnterpriseColors.border)
              : Border.all(color: Colors.transparent),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? EnterpriseColors.textPrimary
                : EnterpriseColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
