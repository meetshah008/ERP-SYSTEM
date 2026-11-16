# Splash screen

The cold-start splash lives in
`lib/features/00_splash/splash_screen.dart` and is mounted by `lib/main.dart`
inside `_ColdStartSplash`. The real first screen (`AuthGate` -> login or
dashboard) is built behind it in a `Stack`, so the circle reveal uncovers an
already-painted screen.

## Change the colours

All colours are constants at the top of `splash_screen.dart`:

```dart
class SplashColors {
  static const Color background = Color(0xFFFFC800); // yellow
  static const Color ink = Color(0xFF111111);        // near-black
}
```

`background` must stay in sync with the native launch screen, otherwise there
is a flash of a different colour before Flutter starts:

- `android/app/src/main/res/values/colors.xml` -> `splash_background`
- `android/app/src/main/res/values/styles.xml` and
  `values-night/styles.xml` (plus the `values-v31` / `values-night-v31`
  Android 12+ overrides) reference that colour
- `ios/Runner/Base.lproj/LaunchScreen.storyboard` -> background colour

If you use `flutter_native_splash`, set `color: "#FFC800"` there too.

## Change the timings

The whole animation is driven by one `AnimationController`. Its duration is
the sum of the beats in `SplashTimings` (4.2s total by default):

```dart
class SplashTimings {
  static const int logoFadeIn = 1000; // E fades/scales in
  static const int wordExpand = 500;  // R and P slide out, E shifts left
  static const int hold = 500;        // hold "ERP"
  static const int collapse = 500;    // letters collapse into the dot
  static const int drop = 500;        // dot drops 60px
  static const int shoot = 500;       // dot shoots to the notch
  static const int reveal = 700;      // circle reveal
}
```

Change any value in milliseconds. `SplashTimings.total` and every
`Interval` are derived from these numbers, so the sequence re-times
automatically. The curves (`easeOutCubic`, `easeInOutCubic`, `easeIn`) are in
the `_segment(...)` calls in `initState`.

## Change the sizes

`SplashSizes` holds the logo/wordmark font sizes, dot diameter, drop distance
and the notch nudge:

```dart
logoFontSize = 150;
wordFontSize = 64;
dotDiameter = 14;
bigDotDiameter = 40;
dropDistance = 60;
notchOffset = 0;
```

## Performance notes

- One `AnimationController` + `Interval`-based `CurvedAnimation` segments.
- `AnimatedBuilder` `child` keeps the letter `Text` widgets and the static
  artwork out of the per-frame rebuild.
- Only `Transform`, `Opacity`, a `CustomPainter` (dot) and a `ClipPath` have
  changing paint state. No layout properties (width/height/padding) animate.
- Dot and reveal sit inside `RepaintBoundary`.
- The next screen is built behind the splash for the whole duration, so the
  reveal has no first-frame pop.

Validate on a physical device with:

```sh
flutter run --profile
```

and check the frame chart in DevTools Performance (no frame above 16ms).
