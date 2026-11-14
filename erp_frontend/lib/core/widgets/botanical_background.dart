import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

/// A pure procedural tropical botanical background that supports both
/// luxurious Dark Forest mode and Fresh Clean Light Mint mode.
class BotanicalBackground extends StatefulWidget {
  final Widget child;
  final bool showThemeToggle;

  const BotanicalBackground({
    super.key,
    required this.child,
    this.showThemeToggle = true,
  });

  @override
  State<BotanicalBackground> createState() => _BotanicalBackgroundState();
}

class _BotanicalBackgroundState extends State<BotanicalBackground> {
  /// Latest pointer position. Repainting is driven by this notifier so the
  /// whole page does not rebuild on every mouse move.
  final ValueNotifier<Offset?> _pointer = ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return MouseRegion(
      opaque: false,
      onHover: (event) => _pointer.value = event.localPosition,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _pointer.value = event.localPosition,
        onPointerMove: (event) => _pointer.value = event.localPosition,
        child: isMobile
            ? _MobileCanvas(
                showThemeToggle: widget.showThemeToggle,
                pointer: _pointer,
                child: widget.child,
              )
            : _buildDesktopCanvas(),
      ),
    );
  }

  Widget _buildDesktopCanvas() {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        return Stack(
          children: [
            // 1. Base Gradient
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.3),
                    radius: 1.2,
                    colors: isDark
                        ? const [
                            Color(0xFF09291A), // Moody forest emerald center
                            Color(0xFF04170E), // Deep dark green mid
                            Color(0xFF010A06), // Near black edge
                          ]
                        : const [
                            Color(0xFFF0FDF4), // Fresh clean mint white center
                            Color(0xFFDCFCE7), // Soft pastel sage green
                            Color(0xFFE2E8F0), // Crisp light slate edge
                          ],
                  ),
                ),
              ),
            ),

            // 2. Custom Painted Botanical Foliage
            Positioned.fill(
              child: CustomPaint(
                painter: _BotanicalFoliagePainter(isDark: isDark),
              ),
            ),

            // 3. Vignette overlay for cinematic depth
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: isDark
                        ? [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.75),
                          ]
                        : [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.04),
                            Colors.black.withValues(alpha: 0.12),
                          ],
                  ),
                ),
              ),
            ),

            // 3b. Soft spotlight that follows the pointer
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PointerGlowPainter(
                    pointer: _pointer,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // 4. Content (Child)
            Positioned.fill(child: widget.child),

            // 5. Floating Theme Toggle Pill (Top-Right)
            if (widget.showThemeToggle)
              Positioned(
                top: 24,
                right: 28,
                child: SafeArea(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: ThemeController.toggleTheme,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            size: 16,
                            color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF0F172A),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDark ? 'Light Mode' : 'Dark Mode',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BotanicalFoliagePainter extends CustomPainter {
  final bool isDark;

  _BotanicalFoliagePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (isDark) {
      // Dark Mode Foliage
      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.08, size.height * 0.12),
        radius: size.width > 900 ? 240 : 160,
        rotation: 0.35,
        color: const Color(0xFF135332),
        veinColor: const Color(0xFF1E7547),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.92, size.height * 0.15),
        radius: size.width > 900 ? 220 : 140,
        rotation: -0.4,
        color: const Color(0xFF0D4026),
        veinColor: const Color(0xFF18633C),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.12, size.height * 0.88),
        radius: size.width > 900 ? 260 : 170,
        rotation: -0.6,
        color: const Color(0xFF0B3821),
        veinColor: const Color(0xFF135734),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.88, size.height * 0.85),
        radius: size.width > 900 ? 280 : 180,
        rotation: 0.5,
        color: const Color(0xFF165C38),
        veinColor: const Color(0xFF238552),
      );
    } else {
      // Light Mode Foliage (Fresh pastel sage / mint)
      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.08, size.height * 0.12),
        radius: size.width > 900 ? 240 : 160,
        rotation: 0.35,
        color: const Color(0xFF86EFAC).withValues(alpha: 0.38),
        veinColor: const Color(0xFF4ADE80).withValues(alpha: 0.5),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.92, size.height * 0.15),
        radius: size.width > 900 ? 220 : 140,
        rotation: -0.4,
        color: const Color(0xFFA7F3D0).withValues(alpha: 0.35),
        veinColor: const Color(0xFF34D399).withValues(alpha: 0.45),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.12, size.height * 0.88),
        radius: size.width > 900 ? 260 : 170,
        rotation: -0.6,
        color: const Color(0xFFBBF7D0).withValues(alpha: 0.35),
        veinColor: const Color(0xFF22C55E).withValues(alpha: 0.45),
      );

      _drawMonsteraLeaf(
        canvas,
        origin: Offset(size.width * 0.88, size.height * 0.85),
        radius: size.width > 900 ? 280 : 180,
        rotation: 0.5,
        color: const Color(0xFF86EFAC).withValues(alpha: 0.42),
        veinColor: const Color(0xFF16A34A).withValues(alpha: 0.5),
      );
    }
  }

  void _drawMonsteraLeaf(
    Canvas canvas, {
    required Offset origin,
    required double radius,
    required double rotation,
    required Color color,
    required Color veinColor,
  }) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(rotation);

    final leafPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final veinPaint = Paint()
      ..color = veinColor
      ..strokeWidth = radius * 0.02
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.25 : 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final path = Path();
    final w = radius * 0.85;
    final h = radius * 1.25;

    path.moveTo(0, -h * 0.5);
    path.cubicTo(w, -h * 0.45, w * 1.1, h * 0.35, 0, h * 0.6);
    path.cubicTo(-w * 1.1, h * 0.35, -w, -h * 0.45, 0, -h * 0.5);
    path.close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, leafPaint);

    final centralVein = Path();
    centralVein.moveTo(0, -h * 0.48);
    centralVein.lineTo(0, h * 0.58);
    canvas.drawPath(centralVein, veinPaint..strokeWidth = radius * 0.035);

    final ribPaint = Paint()
      ..color = isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (int i = 1; i <= 4; i++) {
      final y = -h * 0.3 + (i * h * 0.18);
      final cutoutRight = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.42, y),
          width: radius * 0.25,
          height: radius * 0.07,
        ));
      canvas.drawPath(cutoutRight, ribPaint);

      final cutoutLeft = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(-w * 0.42, y),
          width: radius * 0.25,
          height: radius * 0.07,
        ));
      canvas.drawPath(cutoutLeft, ribPaint);

      canvas.drawLine(
        Offset(0, y),
        Offset(w * 0.75, y - radius * 0.08),
        veinPaint..strokeWidth = radius * 0.015,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(-w * 0.75, y - radius * 0.08),
        veinPaint..strokeWidth = radius * 0.015,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BotanicalFoliagePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Calm, near-flat mobile canvas for max readability.
class _MobileCanvas extends StatelessWidget {
  final Widget child;
  final bool showThemeToggle;
  final ValueNotifier<Offset?> pointer;

  const _MobileCanvas({
    required this.child,
    required this.showThemeToggle,
    required this.pointer,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDarkMode,
      builder: (context, isDark, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? const [Color(0xFF0B1220), Color(0xFF0F172A)]
                        : const [Color(0xFFF1F5F9), Color(0xFFE3E9F0)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -140,
              left: -100,
              child: IgnorePointer(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF059669)
                            .withValues(alpha: isDark ? 0.10 : 0.07),
                        const Color(0xFF059669).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PointerGlowPainter(
                    pointer: pointer,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
            Positioned.fill(child: child),
            if (showThemeToggle)
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: ThemeController.toggleTheme,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF111C2E)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              size: 14,
                              color: isDark
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF475569),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isDark ? 'Light' : 'Dark',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Soft emerald spotlight drawn under the content that follows the pointer.
/// Repaints come from [pointer], so moving the mouse never rebuilds the page.
class _PointerGlowPainter extends CustomPainter {
  final ValueNotifier<Offset?> pointer;
  final bool isDark;

  _PointerGlowPainter({
    required this.pointer,
    required this.isDark,
  }) : super(repaint: pointer);

  @override
  void paint(Canvas canvas, Size size) {
    final center = pointer.value ?? Offset(size.width * 0.5, size.height * 0.28);
    final radius = (size.shortestSide * 0.42).clamp(170.0, 420.0);
    final color = isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
    final alpha = isDark ? 0.16 : 0.10;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.45),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, glow);

    // Tiny bright core for a subtle "spotlight" feel.
    final coreColor = isDark ? Colors.white : const Color(0xFF34D399);
    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          coreColor.withValues(alpha: isDark ? 0.07 : 0.05),
          coreColor.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius * 0.28),
      );
    canvas.drawCircle(center, radius * 0.28, core);
  }

  @override
  bool shouldRepaint(covariant _PointerGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
