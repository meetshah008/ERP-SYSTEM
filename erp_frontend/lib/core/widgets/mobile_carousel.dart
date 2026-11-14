import 'dart:async';
import 'package:flutter/material.dart';
import 'mobile_ui.dart';

/// A network image that fades in when loaded and quietly falls back to a
/// branded gradient when the device is offline or the URL fails.
class MobileNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Color accent;
  final IconData fallbackIcon;

  const MobileNetworkImage({
    super.key,
    required this.url,
    required this.accent,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.factory_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 1000,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _FallbackSurface(accent: accent, icon: fallbackIcon);
      },
      errorBuilder: (_, _, _) =>
          _FallbackSurface(accent: accent, icon: fallbackIcon),
    );
  }
}

class _FallbackSurface extends StatelessWidget {
  final Color accent;
  final IconData icon;

  const _FallbackSurface({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.black, 0.28)!,
            Color.lerp(accent, Colors.black, 0.55)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 54,
          color: Colors.white.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

/// One full-bleed story card inside [MobileHeroCarousel].
class MobileHeroSlide {
  final String imageUrl;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String metric;
  final String metricLabel;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const MobileHeroSlide({
    required this.imageUrl,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.metricLabel,
    required this.icon,
    required this.accent,
    this.onTap,
  });
}

/// Auto-playing image carousel with a gentle gallery scale effect.
///
/// Users can swipe freely; the timer pauses while a finger is down and
/// resumes afterwards so the carousel never fights the user.
class MobileHeroCarousel extends StatefulWidget {
  final List<MobileHeroSlide> slides;
  final bool isDark;
  final double height;
  final Duration interval;

  const MobileHeroCarousel({
    super.key,
    required this.slides,
    required this.isDark,
    this.height = 214,
    this.interval = const Duration(seconds: 5),
  });

  @override
  State<MobileHeroCarousel> createState() => _MobileHeroCarouselState();
}

class _MobileHeroCarouselState extends State<MobileHeroCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _current = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || _dragging || !_controller.hasClients) return;
      final next = (_current + 1) % widget.slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                _dragging = true;
              } else if (notification is ScrollEndNotification) {
                _dragging = false;
                _startTimer();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.slides.length,
              onPageChanged: (index) => setState(() => _current = index),
              padEnds: false,
              itemBuilder: (context, index) {
                final slide = widget.slides[index];
                final active = index == _current;
                return AnimatedScale(
                  scale: active ? 1 : 0.955,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 16 : 5,
                      right: index == widget.slides.length - 1 ? 16 : 5,
                    ),
                    child: _HeroSlideCard(
                      slide: slide,
                      active: active,
                      isDark: widget.isDark,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.slides.length, (index) {
            final active = index == _current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? (widget.isDark
                        ? MobilePalette.mint
                        : MobilePalette.emeraldDeep)
                    : MobilePalette.border(widget.isDark),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _HeroSlideCard extends StatelessWidget {
  final MobileHeroSlide slide;
  final bool active;
  final bool isDark;

  const _HeroSlideCard({
    required this.slide,
    required this.active,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: slide.onTap,
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileNetworkImage(
                url: slide.imageUrl,
                accent: slide.accent,
                fallbackIcon: slide.icon,
              ),
              // Cinematic bottom fade keeps text readable on any photo.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    stops: const [0, 0.35, 0.66, 1],
                  ),
                ),
              ),
              // Accent wash for brand consistency.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      slide.accent.withValues(alpha: 0.30),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                slide.eyebrow.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Icon(
                            slide.icon,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      slide.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.55,
                        height: 1.08,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slide.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                slide.metric,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                slide.metricLabel,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: active
                                ? const Color(0xFF0F172A)
                                : Colors.white,
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
    );
  }
}

/// Compact image card used in horizontally scrolling module rails.
class MobileImageRailCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;
  final double width;
  final double height;

  const MobileImageRailCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.onTap,
    this.width = 188,
    this.height = 134,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white.withValues(alpha: 0.10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileNetworkImage(
                  url: imageUrl,
                  accent: accent,
                  fallbackIcon: icon,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.34),
                        Colors.black.withValues(alpha: 0.80),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.26),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                            ),
                            child: Icon(icon, size: 15, color: Colors.white),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.north_east_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.74),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
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
  }
}

/// Instagram-style circular story avatar.
class MobileStoryItem {
  final String label;
  final String initials;
  final Color color;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool live;
  final bool add;

  const MobileStoryItem({
    required this.label,
    required this.initials,
    required this.color,
    required this.onTap,
    this.imageUrl,
    this.live = false,
    this.add = false,
  });
}

/// Horizontal, swipeable row of story avatars with an emerald gradient ring.
class MobileStoryRail extends StatelessWidget {
  final List<MobileStoryItem> items;
  final bool isDark;
  final double avatarSize;

  const MobileStoryRail({
    super.key,
    required this.items,
    required this.isDark,
    this.avatarSize = 54,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: avatarSize + 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final item = items[index];
          final ring = item.add
              ? [MobilePalette.border(isDark), MobilePalette.border(isDark)]
              : item.live
                  ? const [Color(0xFF34D399), Color(0xFF059669)]
                  : [
                      MobilePalette.emerald,
                      MobilePalette.violet,
                      MobilePalette.sky,
                    ];

          return SizedBox(
            width: avatarSize + 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: item.onTap,
                splashColor: item.color.withValues(alpha: 0.10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: avatarSize + 6,
                      height: avatarSize + 6,
                      padding: const EdgeInsets.all(2.2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [...ring, ring.first]),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF0B1220)
                              : Colors.white,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: item.color.withValues(
                                  alpha: isDark ? 0.22 : 0.12,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: item.add
                                  ? Icon(
                                      Icons.add_rounded,
                                      size: 24,
                                      color: MobilePalette.emeraldDeep,
                                    )
                                  : item.imageUrl != null
                                      ? MobileNetworkImage(
                                          url: item.imageUrl!,
                                          accent: item.color,
                                          fallbackIcon:
                                              Icons.person_rounded,
                                        )
                                      : Center(
                                          child: Text(
                                            item.initials,
                                            style: TextStyle(
                                              color: isDark
                                                  ? Color.lerp(item.color,
                                                      Colors.white, 0.35)
                                                  : item.color,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                            ),
                            if (item.live)
                              Positioned(
                                right: 1,
                                bottom: 1,
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
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MobilePalette.body(isDark),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fade + slide entrance used to stagger dashboard sections.
class MobileReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;

  const MobileReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
  });

  @override
  State<MobileReveal> createState() => _MobileRevealState();
}

class _MobileRevealState extends State<MobileReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(curved);

    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Smoothly counts up to a target value, used for live KPI numbers.
class MobileCountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const MobileCountUp({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 720),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(
        animated.round().toString(),
        style: style,
      ),
    );
  }
}
