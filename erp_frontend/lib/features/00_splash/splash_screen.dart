import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Re-skin the splash by changing these two colours.
///
/// Keep [background] in sync with the native launch screen
/// (`android/app/src/main/res/values/colors.xml` and
/// `ios/Runner/Base.lproj/LaunchScreen.storyboard`).
class SplashColors {
  const SplashColors._();

  /// Solid yellow splash background.
  static const Color background = Color(0xFFFFFFFF);

  /// Logo, wordmark and dot colour. Near-black reads much better on yellow
  /// than white.
  static const Color ink = Color(0xFF111111);
}

/// Timeline, in milliseconds. The controller duration is the sum of these
/// beats, so changing a value here re-times the whole animation automatically.
///
/// Beat map:
///   0    -> 1000  : "E" fades/scales in
///   1000 -> 1500  : wordmark expands to "ERP"
///   1500 -> 2000  : hold
///   2000 -> 2500  : letters collapse into a dot
///   2500 -> 3000  : dot drops
///   3000 -> 3500  : dot shoots up to the notch
///   3500 -> 4200  : circle reveal
class SplashTimings {
  const SplashTimings._();

  static const int logoFadeIn = 1000;
  static const int wordExpand = 500;
  static const int hold = 500;
  static const int collapse = 500;
  static const int drop = 500;
  static const int shoot = 500;
  static const int reveal = 700;

  static const int total =
      logoFadeIn + wordExpand + hold + collapse + drop + shoot + reveal;

  // Absolute boundaries used to derive the Intervals below.
  static const int expandStart = logoFadeIn;
  static const int expandEnd = expandStart + wordExpand;
  static const int holdEnd = expandEnd + hold;
  static const int collapseEnd = holdEnd + collapse;
  static const int dropEnd = collapseEnd + drop;
  static const int shootEnd = dropEnd + shoot;
  static const int revealEnd = shootEnd + reveal;
}

/// Visual sizes. Change these if you want a bigger/smaller logo or dot.
class SplashSizes {
  const SplashSizes._();

  static const double logoFontSize = 150;
  static const double wordFontSize = 64;
  static const double letterGap = 10;
  static const double dotDiameter = 14;
  static const double bigDotDiameter = 40;
  static const double dropDistance = 60;

  /// Nudge the final dot up/down from `MediaQuery.padding.top` if the notch
  /// position needs fine-tuning on a particular device.
  static const double notchOffset = 0;
}

/// The animated cold-start splash.
///
/// The real first screen must be built *behind* this widget (see `main.dart`)
/// so the expanding circle can reveal it without a frame of jank.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  /// Called once, after the circle has covered the whole screen.
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<CurvedAnimation> _curvedAnimations = <CurvedAnimation>[];

  late final Animation<double> _intro;
  late final Animation<double> _expand;
  late final Animation<double> _collapseE;
  late final Animation<double> _collapseR;
  late final Animation<double> _collapseP;
  late final Animation<double> _dotAppear;
  late final Animation<double> _drop;
  late final Animation<double> _shoot;
  late final Animation<double> _reveal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: SplashTimings.total),
    );

    // One controller, many Intervals. Every animated property reads from one
    // of these segments, so the whole sequence stays in sync.
    _intro = _segment(0, SplashTimings.logoFadeIn, Curves.easeOutCubic);
    _expand = _segment(
      SplashTimings.expandStart,
      SplashTimings.expandEnd,
      Curves.easeInOutCubic,
    );

    // Right-to-left collapse: P goes first, then R, then the E.
    _collapseP = _segment(
      SplashTimings.holdEnd,
      SplashTimings.holdEnd + 140,
      Curves.easeInOutCubic,
    );
    _collapseR = _segment(
      SplashTimings.holdEnd + 80,
      SplashTimings.holdEnd + 260,
      Curves.easeInOutCubic,
    );
    _collapseE = _segment(
      SplashTimings.holdEnd + 160,
      SplashTimings.collapseEnd,
      Curves.easeInOutCubic,
    );

    _dotAppear = _segment(
      SplashTimings.holdEnd + 280,
      SplashTimings.collapseEnd,
      Curves.easeOutCubic,
    );
    _drop = _segment(
      SplashTimings.collapseEnd,
      SplashTimings.dropEnd,
      Curves.easeIn,
    );
    _shoot = _segment(
      SplashTimings.dropEnd,
      SplashTimings.shootEnd,
      Curves.easeInOutCubic,
    );
    _reveal = _segment(
      SplashTimings.shootEnd,
      SplashTimings.revealEnd,
      Curves.easeInOutCubic,
    );

    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  Animation<double> _segment(int fromMs, int toMs, Curve curve) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        fromMs / SplashTimings.total,
        toMs / SplashTimings.total,
        curve: curve,
      ),
    );
    _curvedAnimations.add(animation);
    return animation;
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    // Let the fully-revealed frame paint once, then remove the splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    for (final animation in _curvedAnimations) {
      animation.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The dot finishes where the notch / Dynamic Island lives.
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final center = Offset(size.width / 2, size.height / 2);
          final notch = Offset(
            size.width / 2,
            math.max(0.0, topInset + SplashSizes.notchOffset),
          );
          final word = _WordMetrics.measure(
            SplashSizes.wordFontSize,
            SplashSizes.letterGap,
          );
          final maxRevealRadius = math.sqrt(
            size.width * size.width + size.height * size.height,
          );

          return RepaintBoundary(
            child: AnimatedBuilder(
              animation: _reveal,
              // Static artwork is built once and passed through `child`; only
              // the ClipPath below rebuilds for the circle reveal.
              child: _SplashArtwork(
                controller: _controller,
                intro: _intro,
                expand: _expand,
                collapseE: _collapseE,
                collapseR: _collapseR,
                collapseP: _collapseP,
                dotAppear: _dotAppear,
                drop: _drop,
                shoot: _shoot,
                center: center,
                notch: notch,
                word: word,
              ),
              builder: (context, child) {
                final reveal = _reveal.value;
                final radius = reveal <= 0
                    ? 0.0
                    : _lerp(
                        SplashSizes.bigDotDiameter / 2,
                        maxRevealRadius,
                        reveal,
                      );

                return ClipPath(
                  clipper: _CircleRevealClipper(center: notch, radius: radius),
                  child: child,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The static tree that the reveal clip is applied to. Its animated parts get
/// their own listeners, so the outer AnimatedBuilder doesn't rebuild them.
class _SplashArtwork extends StatelessWidget {
  const _SplashArtwork({
    required this.controller,
    required this.intro,
    required this.expand,
    required this.collapseE,
    required this.collapseR,
    required this.collapseP,
    required this.dotAppear,
    required this.drop,
    required this.shoot,
    required this.center,
    required this.notch,
    required this.word,
  });

  final AnimationController controller;
  final Animation<double> intro;
  final Animation<double> expand;
  final Animation<double> collapseE;
  final Animation<double> collapseR;
  final Animation<double> collapseP;
  final Animation<double> dotAppear;
  final Animation<double> drop;
  final Animation<double> shoot;
  final Offset center;
  final Offset notch;
  final _WordMetrics word;

  @override
  Widget build(BuildContext context) {
    final logoStyle = TextStyle(
      color: SplashColors.ink,
      fontSize: SplashSizes.logoFontSize,
      fontWeight: FontWeight.w900,
      height: 1,
    );
    final wordStyle = TextStyle(
      color: SplashColors.ink,
      fontSize: SplashSizes.wordFontSize,
      fontWeight: FontWeight.w900,
      height: 1,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: SplashColors.background),
        Center(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The big "E" is the first letter of the wordmark: it shrinks
              // and shifts left while R and P slide out to the right.
              _AnimatedLetter(
                controller: controller,
                intro: intro,
                expand: expand,
                collapse: collapseE,
                text: 'E',
                style: logoStyle,
                expandOffset: word.eOffset,
                startScale: 1,
                wordScale: SplashSizes.wordFontSize / SplashSizes.logoFontSize,
                collapseScale: 0.10,
                fadeWithExpand: false,
              ),
              _AnimatedLetter(
                controller: controller,
                expand: expand,
                collapse: collapseR,
                text: 'R',
                style: wordStyle,
                expandOffset: word.rOffset,
                startScale: 1.06,
                wordScale: 1,
                collapseScale: 0.10,
                fadeWithExpand: true,
              ),
              _AnimatedLetter(
                controller: controller,
                expand: expand,
                collapse: collapseP,
                text: 'P',
                style: wordStyle,
                expandOffset: word.pOffset,
                startScale: 1.06,
                wordScale: 1,
                collapseScale: 0.10,
                fadeWithExpand: true,
              ),
            ],
          ),
        ),
        // Dot + reveal are painted, not laid out.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _DotPainter(
                repaint: controller,
                center: center,
                notch: notch,
                appear: dotAppear,
                drop: drop,
                shoot: shoot,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single letter. The [Text] is supplied as AnimatedBuilder's `child`, so
/// the paragraph is not rebuilt on every animation tick.
class _AnimatedLetter extends StatelessWidget {
  const _AnimatedLetter({
    required this.controller,
    required this.expand,
    required this.collapse,
    required this.text,
    required this.style,
    required this.expandOffset,
    required this.startScale,
    required this.wordScale,
    required this.collapseScale,
    required this.fadeWithExpand,
    this.intro,
  });

  final AnimationController controller;
  final Animation<double>? intro;
  final Animation<double> expand;
  final Animation<double> collapse;
  final String text;
  final TextStyle style;
  final double expandOffset;
  final double startScale;
  final double wordScale;
  final double collapseScale;
  final bool fadeWithExpand;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: Text(text, style: style, textScaler: TextScaler.noScaling),
      builder: (context, child) {
        final introValue = intro?.value ?? 1.0;
        final expandValue = expand.value;
        final collapseValue = collapse.value;

        final introScale = intro == null ? 1.0 : _lerp(0.9, 1.0, introValue);
        final expandedScale = _lerp(startScale, wordScale, expandValue);
        final scale = _lerp(
          expandedScale * introScale,
          collapseScale,
          collapseValue,
        );

        final expandedOffset = _lerp(0.0, expandOffset, expandValue);
        final x = _lerp(expandedOffset, 0.0, collapseValue);

        final fadeIn = fadeWithExpand
            ? ((expandValue - 0.10) / 0.55).clamp(0.0, 1.0)
            : 1.0;
        final opacity = (introValue * fadeIn * (1.0 - collapseValue)).clamp(
          0.0,
          1.0,
        );

        return Transform.translate(
          offset: Offset(x, 0),
          child: Transform.scale(
            scale: scale,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
    );
  }
}

/// Paints the collapsing dot through its drop, launch and growth. The painter
/// repaints from the controller, so no widget rebuilds are needed for it.
class _DotPainter extends CustomPainter {
  _DotPainter({
    required Listenable repaint,
    required this.center,
    required this.notch,
    required this.appear,
    required this.drop,
    required this.shoot,
  }) : super(repaint: repaint);

  final Offset center;
  final Offset notch;
  final Animation<double> appear;
  final Animation<double> drop;
  final Animation<double> shoot;

  @override
  void paint(Canvas canvas, Size size) {
    final appearValue = appear.value;
    if (appearValue <= 0) {
      return;
    }

    final dropValue = drop.value;
    final shootValue = shoot.value;

    final droppedCenter = center.translate(
      0,
      SplashSizes.dropDistance * dropValue,
    );
    final position = Offset(
      _lerp(droppedCenter.dx, notch.dx, shootValue),
      _lerp(droppedCenter.dy, notch.dy, shootValue),
    );

    final radius = _lerp(
      (SplashSizes.dotDiameter / 2) * appearValue,
      SplashSizes.bigDotDiameter / 2,
      shootValue,
    );

    // Squash & stretch: stretch while accelerating, squash on impact, then
    // recover and stretch slightly as the dot launches upward.
    double scaleX = 1;
    double scaleY = 1;
    if (dropValue > 0) {
      if (dropValue < 0.85) {
        final fall = dropValue / 0.85;
        scaleY = 1 + 0.22 * fall;
        scaleX = 1 - 0.12 * fall;
      } else {
        final impact = (dropValue - 0.85) / 0.15;
        scaleY = _lerp(1.22, 0.80, impact);
        scaleX = _lerp(0.88, 1.18, impact);
      }
    }
    if (shootValue > 0) {
      final recover = (shootValue / 0.25).clamp(0.0, 1.0);
      final flight = math.sin(math.pi * shootValue);
      scaleY = _lerp(scaleY, 1 + 0.10 * flight, recover);
      scaleX = _lerp(scaleX, 1 - 0.06 * flight, recover);
    }

    final paint = Paint()
      ..color = SplashColors.ink
      ..isAntiAlias = true;

    canvas.drawOval(
      Rect.fromCenter(
        center: position,
        width: radius * 2 * scaleX,
        height: radius * 2 * scaleY,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.notch != notch ||
        oldDelegate.appear != appear ||
        oldDelegate.drop != drop ||
        oldDelegate.shoot != shoot;
  }
}

/// Leaves the whole screen yellow and punches an expanding transparent hole
/// around the notch, revealing the real screen behind the splash.
class _CircleRevealClipper extends CustomClipper<Path> {
  const _CircleRevealClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final screen = Offset.zero & size;
    if (radius <= 0) {
      return Path()..addRect(screen);
    }

    // Even-odd fills the rectangle, then removes the circle from it.
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(screen)
      ..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return oldClipper.center != center || oldClipper.radius != radius;
  }
}

/// Wordmark geometry, measured once per layout with the exact text style used
/// by the letter widgets.
class _WordMetrics {
  const _WordMetrics({
    required this.eOffset,
    required this.rOffset,
    required this.pOffset,
  });

  final double eOffset;
  final double rOffset;
  final double pOffset;

  static _WordMetrics measure(double fontSize, double gap) {
    final style = TextStyle(
      color: SplashColors.ink,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1,
    );

    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      return painter.width;
    }

    final e = widthOf('E');
    final r = widthOf('R');
    final p = widthOf('P');
    final wordWidth = e + r + p + gap * 2;

    return _WordMetrics(
      eOffset: -wordWidth / 2 + e / 2,
      rOffset: -wordWidth / 2 + e + gap + r / 2,
      pOffset: wordWidth / 2 - p / 2,
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
