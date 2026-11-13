import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// A premium, mobile-only "Aurora Forest" wallpaper.
///
/// Layers:
///   1. A vertical twilight gradient tuned for portrait phones.
///   2. Slowly drifting aurora ribbons (emerald / cyan / violet).
///   3. Soft bloom orbs and a fine star-dust field.
///   4. Whispers of botanical foliage in the corners.
///
/// The composition is intentionally calm behind dense ERP screens, while the
/// slow drift keeps the app feeling alive without stealing attention.
class MobileWallpaper extends StatefulWidget {
  final Widget child;
  final bool showThemeToggle;

  const MobileWallpaper({
    super.key,
    required this.child,
    this.showThemeToggle = true,
  });

  @override
  State<MobileWallpaper> createState() => _MobileWallpaperState();
}

class _MobileWallpaperState extends State<MobileWallpaper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 42),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _drift.stop();
      _drift.value = 0.32;
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        final baseColors = isDark
            ? const [
                Color(0xFF06110F),
                Color(0xFF071B1D),
                Color(0xFF0A1526),
                Color(0xFF03070C),
              ]
            : const [
                Color(0xFFF7FCFA),
                Color(0xFFEAF7F1),
                Color(0xFFE8F2FB),
                Color(0xFFF6FAFF),
              ];

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Portrait twilight gradient.
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: baseColors,
                  stops: const [0.0, 0.38, 0.72, 1.0],
                ),
              ),
            ),

            // 2. Aurora + botanicals + star dust.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AuroraForestPainter(
                      progress: _drift.value,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),

            // 3. Readability vignette.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 1.25,
                    colors: isDark
                        ? [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.10),
                            Colors.black.withValues(alpha: 0.46),
                          ]
                        : [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.06),
                          ],
                  ),
                ),
              ),
            ),

            // 4. Screen content.
            Positioned.fill(child: widget.child),

            // 5. Optional floating theme switch (screens without their own).
            if (widget.showThemeToggle)
              Positioned(
                top: 18,
                right: 18,
                child: SafeArea(
                  child: _FloatingThemeToggle(isDark: isDark),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FloatingThemeToggle extends StatelessWidget {
  final bool isDark;

  const _FloatingThemeToggle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: ThemeController.toggleTheme,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF071A16).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 15,
                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF0B1520),
              ),
              const SizedBox(width: 6),
              Text(
                isDark ? 'Light' : 'Dark',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0B1520),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuroraForestPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _AuroraForestPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = progress * math.pi * 2;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // ---------------------------------------------------------------------
    // 1. Bloom orbs
    // ---------------------------------------------------------------------
    final orbs = <_Orb>[
      _Orb(
        center: Offset(
          w * (0.18 + 0.035 * math.sin(t)),
          h * (0.16 + 0.02 * math.cos(t * 0.8)),
        ),
        radius: w * 0.82,
        color: isDark ? const Color(0xFF0E9F6E) : const Color(0xFF6EE7B7),
        opacity: isDark ? 0.34 : 0.46,
      ),
      _Orb(
        center: Offset(
          w * (0.92 + 0.03 * math.cos(t * 1.1)),
          h * (0.28 + 0.025 * math.sin(t)),
        ),
        radius: w * 0.72,
        color: isDark ? const Color(0xFF0EA5E9) : const Color(0xFF7DD3FC),
        opacity: isDark ? 0.24 : 0.38,
      ),
      _Orb(
        center: Offset(
          w * (0.12 + 0.04 * math.cos(t * 0.7)),
          h * (0.78 + 0.02 * math.sin(t * 0.9)),
        ),
        radius: w * 0.88,
        color: isDark ? const Color(0xFF6D28D9) : const Color(0xFFC4B5FD),
        opacity: isDark ? 0.20 : 0.30,
      ),
      _Orb(
        center: Offset(
          w * (0.86 + 0.05 * math.sin(t * 0.6)),
          h * (0.90 + 0.02 * math.cos(t)),
        ),
        radius: w * 0.70,
        color: isDark ? const Color(0xFF10B981) : const Color(0xFFA7F3D0),
        opacity: isDark ? 0.24 : 0.42,
      ),
    ];

    for (final orb in orbs) {
      final shader = RadialGradient(
        colors: [
          orb.color.withValues(alpha: orb.opacity),
          orb.color.withValues(alpha: orb.opacity * 0.35),
          orb.color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: orb.center, radius: orb.radius));

      canvas.drawCircle(
        orb.center,
        orb.radius,
        Paint()
          ..shader = shader
          ..blendMode = isDark ? BlendMode.screen : BlendMode.srcOver,
      );
    }

    // ---------------------------------------------------------------------
    // 2. Aurora ribbons
    // ---------------------------------------------------------------------
    _drawRibbon(
      canvas,
      size,
      phase: t,
      offsetY: h * 0.24,
      amplitude: h * 0.085,
      thickness: w * 0.38,
      colors: isDark
          ? [
              const Color(0xFF10B981).withValues(alpha: 0.30),
              const Color(0xFF06B6D4).withValues(alpha: 0.22),
              const Color(0xFF8B5CF6).withValues(alpha: 0.16),
            ]
          : [
              const Color(0xFF6EE7B7).withValues(alpha: 0.52),
              const Color(0xFF7DD3FC).withValues(alpha: 0.42),
              const Color(0xFFC4B5FD).withValues(alpha: 0.34),
            ],
      blur: w * 0.055,
    );

    _drawRibbon(
      canvas,
      size,
      phase: t + 1.9,
      offsetY: h * 0.67,
      amplitude: h * 0.07,
      thickness: w * 0.32,
      colors: isDark
          ? [
              const Color(0xFF0D9488).withValues(alpha: 0.24),
              const Color(0xFF3B82F6).withValues(alpha: 0.16),
              const Color(0xFF10B981).withValues(alpha: 0.18),
            ]
          : [
              const Color(0xFFA7F3D0).withValues(alpha: 0.46),
              const Color(0xFFBAE6FD).withValues(alpha: 0.38),
              const Color(0xFFDDD6FE).withValues(alpha: 0.30),
            ],
      blur: w * 0.06,
    );

    // ---------------------------------------------------------------------
    // 3. Botanical whispers
    // ---------------------------------------------------------------------
    final leafColor = isDark
        ? const Color(0xFF34D399).withValues(alpha: 0.055)
        : const Color(0xFF059669).withValues(alpha: 0.075);
    final leafVein = isDark
        ? const Color(0xFF6EE7B7).withValues(alpha: 0.075)
        : const Color(0xFF047857).withValues(alpha: 0.10);

    _drawLeaf(
      canvas,
      origin: Offset(-w * 0.10, h * 0.30),
      length: w * 0.52,
      angle: 0.55,
      fill: leafColor,
      vein: leafVein,
    );
    _drawLeaf(
      canvas,
      origin: Offset(w * 1.06, h * 0.16),
      length: w * 0.48,
      angle: -0.65,
      fill: leafColor,
      vein: leafVein,
    );
    _drawLeaf(
      canvas,
      origin: Offset(w * 0.03, h * 1.02),
      length: w * 0.60,
      angle: -0.35,
      fill: leafColor,
      vein: leafVein,
    );
    _drawLeaf(
      canvas,
      origin: Offset(w * 0.98, h * 0.92),
      length: w * 0.54,
      angle: 0.42,
      fill: leafColor,
      vein: leafVein,
    );

    // ---------------------------------------------------------------------
    // 4. Star dust
    // ---------------------------------------------------------------------
    final dustColor = isDark ? Colors.white : const Color(0xFF0F766E);
    final dustAlpha = isDark ? 0.32 : 0.15;
    for (var i = 0; i < 46; i++) {
      final fx = ((i * 73) % 101) / 101;
      final fy = ((i * 47) % 97) / 97;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 1.3 + i * 0.7));
      final radius = 0.55 + (i % 4) * 0.32;
      canvas.drawCircle(
        Offset(fx * w, fy * h),
        radius,
        Paint()
          ..color = dustColor.withValues(alpha: dustAlpha * twinkle * 0.55),
      );
    }

    // ---------------------------------------------------------------------
    // 5. Top highlight (makes the status bar area glow softly)
    // ---------------------------------------------------------------------
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.22),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF6EE7B7).withValues(alpha: 0.10),
                  Colors.transparent,
                ]
              : [
                  Colors.white.withValues(alpha: 0.42),
                  Colors.transparent,
                ],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.22)),
    );

    canvas.restore();
  }

  void _drawRibbon(
    Canvas canvas,
    Size size, {
    required double phase,
    required double offsetY,
    required double amplitude,
    required double thickness,
    required List<Color> colors,
    required double blur,
  }) {
    final w = size.width;

    final path = Path()..moveTo(-w * 0.2, offsetY);

    for (var step = 0; step <= 4; step++) {
      final x0 = -w * 0.2 + (w * 1.4 / 4) * step;
      final x1 = x0 + (w * 1.4 / 4) * 0.5;
      final x2 = x0 + (w * 1.4 / 4);
      final y1 = offsetY +
          math.sin(phase * 0.9 + step * 1.25) * amplitude +
          math.cos(phase * 1.3 + step) * amplitude * 0.35;
      final y2 = offsetY +
          math.sin(phase * 1.1 + step * 1.05 + 0.8) * amplitude * 0.8;
      path.cubicTo(x1, y1, x1, y2, x2, y2);
    }

    final rect = Rect.fromLTWH(0, offsetY - thickness, w, thickness * 2.4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ).createShader(rect)
      ..blendMode = isDark ? BlendMode.screen : BlendMode.srcOver;

    canvas.drawPath(path, paint);

    // A brighter inner filament for a silky look.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 0.16
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.55)
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors
              .map((c) => c.withValues(alpha: isDark ? 0.30 : 0.55))
              .toList(),
        ).createShader(rect)
        ..blendMode = isDark ? BlendMode.screen : BlendMode.srcOver,
    );
  }

  void _drawLeaf(
    Canvas canvas, {
    required Offset origin,
    required double length,
    required double angle,
    required Color fill,
    required Color vein,
  }) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);

    final width = length * 0.42;
    final path = Path()
      ..moveTo(0, -length * 0.5)
      ..cubicTo(
        width,
        -length * 0.32,
        width * 1.12,
        length * 0.30,
        0,
        length * 0.5,
      )
      ..cubicTo(
        -width * 1.12,
        length * 0.30,
        -width,
        -length * 0.32,
        0,
        -length * 0.5,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = fill);

    final veinPaint = Paint()
      ..color = vein
      ..style = PaintingStyle.stroke
      ..strokeWidth = length * 0.008
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, -length * 0.42),
      Offset(0, length * 0.44),
      veinPaint,
    );

    for (var i = 1; i <= 3; i++) {
      final y = -length * 0.20 + (i * length * 0.16);
      canvas.drawLine(
        Offset(0, y),
        Offset(width * 0.62, y - length * 0.055),
        veinPaint,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(-width * 0.62, y - length * 0.055),
        veinPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AuroraForestPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

class _Orb {
  final Offset center;
  final double radius;
  final Color color;
  final double opacity;

  const _Orb({
    required this.center,
    required this.radius,
    required this.color,
    required this.opacity,
  });
}
