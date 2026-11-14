import 'package:flutter/material.dart';

/// Shared visual language for every mobile screen.
///
/// Quiet premium ERP: neutral surfaces, a single emerald accent, crisp
/// borders and soft shadows. No neon glows or rainbow gradients.
class MobilePalette {
  MobilePalette._();

  static const Color emerald = Color(0xFF059669);
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color mint = Color(0xFF34D399);
  static const Color cyan = Color(0xFF0891B2);
  static const Color sky = Color(0xFF0284C7);
  static const Color violet = Color(0xFF7C3AED);
  static const Color amber = Color(0xFFD97706);
  static const Color rose = Color(0xFFE11D48);
  static const Color blue = Color(0xFF2563EB);

  static const Color pageBg = Color(0xFFFFFFFF);
  static const Color inputFill = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFF4F4F5);
  static const Color primaryBtn = Color(0xFF18181B);
  static const Color primaryBtnText = Color(0xFFFFFFFF);

  static Color title(bool isDark) =>
      isDark ? const Color(0xFFF1F5F9) : const Color(0xFF09090B);

  static Color body(bool isDark) =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF52525B);

  static Color faint(bool isDark) =>
      isDark ? const Color(0xFF64748B) : const Color(0xFF71717A);

  static Color card(bool isDark) =>
      isDark ? const Color(0xFF111C2E) : const Color(0xFFFFFFFF);

  static Color cardSolid(bool isDark) =>
      isDark ? const Color(0xFF111C2E) : const Color(0xFFFFFFFF);

  static Color border(bool isDark) =>
      isDark ? const Color(0xFF22304A) : const Color(0xFFE4E4E7);

  static Color hairline(bool isDark) =>
      isDark ? const Color(0xFF1E293B) : const Color(0xFFE4E4E7);

  static LinearGradient heroGradient(bool isDark) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF16233A), Color(0xFF111C2E)]
            : const [Colors.white, Color(0xFFF8FAFC)],
      );

  static LinearGradient accentGradient(Color color) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.92),
          color.withValues(alpha: 0.74),
        ],
      );

  static List<BoxShadow> softShadow(bool isDark, {Color? glow}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.055),
          blurRadius: isDark ? 20 : 18,
          offset: const Offset(0, 6),
        ),
      ];
}

/// A clean, softly shadowed surface used across mobile dashboards.
class MobileGlassCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? tint;
  final Gradient? gradient;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final bool clip;

  const MobileGlassCard({
    super.key,
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 18,
    this.tint,
    this.gradient,
    this.border,
    this.boxShadow,
    this.onTap,
    this.clip = true,
  });

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? (tint ?? MobilePalette.card(isDark))
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            Border.all(
              color: MobilePalette.border(isDark),
              width: 1,
            ),
        boxShadow: boxShadow ?? MobilePalette.softShadow(isDark),
      ),
      child: child,
    );

    final withRipple = onTap == null
        ? decorated
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: clip ? Clip.antiAlias : Clip.none,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              splashColor: MobilePalette.emerald.withValues(alpha: 0.08),
              highlightColor: MobilePalette.emerald.withValues(alpha: 0.04),
              child: decorated,
            ),
          );

    if (margin == null) return withRipple;
    return Padding(padding: margin!, child: withRipple);
  }
}

/// Section title with an optional "See all" action.
class MobileSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isDark;
  final EdgeInsetsGeometry padding;

  const MobileSectionHeader({
    super.key,
    required this.title,
    required this.isDark,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: MobilePalette.title(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.25,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: MobilePalette.body(isDark),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? MobilePalette.mint : MobilePalette.emeraldDeep,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward_rounded, size: 13),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Flat, tinted rounded icon used in headers and action tiles.
class MobileGradientIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool isDark;

  const MobileGradientIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.isDark,
    this.size = 46,
    this.iconSize = 21,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: Icon(
        icon,
        color: isDark ? Color.lerp(color, Colors.white, 0.18) : color,
        size: iconSize,
      ),
    );
  }
}

/// Flat app-launcher action: a bare icon with a label underneath.
///
/// Deliberately has no card surface, border or shadow so quick actions read as
/// direct icons rather than a grid of cards.
class MobileActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  final String? badge;

  const MobileActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.isDark,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        splashColor: color.withValues(alpha: 0.14),
        highlightColor: color.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.16 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: isDark
                          ? Color.lerp(color, Colors.white, 0.28)
                          : color,
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -5,
                      right: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF111C2E) : Colors.white,
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MobilePalette.title(isDark),
                  fontSize: 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact metric chip used inside hero cards.
class MobileMetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const MobileMetricPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MobilePalette.border(isDark)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: MobilePalette.title(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: MobilePalette.faint(isDark),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim status/live chip.
class MobileLivePill extends StatelessWidget {
  final String label;
  final bool isDark;
  final Color color;

  const MobileLivePill({
    super.key,
    required this.label,
    required this.isDark,
    this.color = MobilePalette.emerald,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? MobilePalette.mint
                  : MobilePalette.emeraldDeep,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}
