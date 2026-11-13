import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central design tokens for a quiet, premium ERP experience.
///
/// Neutral slate surfaces with a single emerald accent keep data-dense
/// screens readable on phones while still feeling polished.
class AppTheme {
  AppTheme._();

  static const Color emerald = Color(0xFF059669);
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color mint = Color(0xFF34D399);
  static const Color cyan = Color(0xFF0891B2);
  static const Color sky = Color(0xFF0284C7);
  static const Color violet = Color(0xFF7C3AED);
  static const Color amber = Color(0xFFD97706);
  static const Color rose = Color(0xFFE11D48);

  static const Color ink = Color(0xFF0B1220);
  static const Color inkSoft = Color(0xFF111C2E);
  static const Color inkCard = Color(0xFF16233A);
  static const Color lightBg = Color(0xFFF1F5F9);
  static const Color lightCard = Color(0xFFFFFFFF);

  static const Color darkTitle = Color(0xFFF1F5F9);
  static const Color darkBody = Color(0xFF94A3B8);
  static const Color lightTitle = Color(0xFF0F172A);
  static const Color lightBody = Color(0xFF475569);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color titleColor = isDark ? darkTitle : lightTitle;
    final Color bodyColor = isDark ? darkBody : lightBody;
    final Color cardColor = isDark ? inkSoft : lightCard;

    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? mint : emerald,
      onPrimary: isDark ? const Color(0xFF04140D) : Colors.white,
      secondary: isDark ? const Color(0xFF38BDF8) : cyan,
      onSecondary: isDark ? const Color(0xFF04141A) : Colors.white,
      tertiary: violet,
      surface: cardColor,
      onSurface: titleColor,
      error: isDark ? const Color(0xFFFB7185) : const Color(0xFFDC2626),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    final textTheme = _textTheme(base.textTheme, titleColor, bodyColor);
    final fieldBorder = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);
    final fieldFill = isDark
        ? const Color(0xFF0F1A2B)
        : Colors.white;

    InputBorder outline(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? ink : lightBg,
      canvasColor: isDark ? ink : lightBg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white70 : const Color(0xFF475569),
        size: 22,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: titleColor),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(
          color: isDark
              ? Colors.white.withValues(alpha: 0.38)
              : const Color(0xFF93A3B1),
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(color: bodyColor, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
          color: isDark ? mint : emeraldDeep,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor:
            isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF7A8B99),
        suffixIconColor:
            isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF7A8B99),
        border: outline(fieldBorder, 1),
        enabledBorder: outline(fieldBorder, 1),
        disabledBorder: outline(fieldBorder.withValues(alpha: 0.5), 1),
        focusedBorder: outline(isDark ? mint : emerald, 1.6),
        errorBorder: outline(scheme.error.withValues(alpha: 0.65), 1.2),
        focusedErrorBorder: outline(scheme.error, 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? mint : emeraldDeep,
          foregroundColor: isDark ? const Color(0xFF04140D) : Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: titleColor,
          side: BorderSide(color: fieldBorder, width: 1.1),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? mint : emeraldDeep,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? mint : emeraldDeep,
        foregroundColor: isDark ? const Color(0xFF04140D) : Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      cardTheme: CardThemeData(
        color: cardColor.withValues(alpha: isDark ? 0.85 : 0.95),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? inkSoft : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? inkSoft : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor:
            isDark ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFCBD5E1),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDark ? Colors.white70 : const Color(0xFF475569),
        textColor: titleColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? mint : emeraldDeep,
        linearTrackColor: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFE2E8F0),
        circularTrackColor: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFE2E8F0),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? const Color(0xFF04140D) : Colors.white)
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? mint : emerald)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFCBD5E1)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFEFF6F3),
        selectedColor: (isDark ? mint : emerald).withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF334155),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF0C1A24) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFE2E8F0),
          ),
        ),
        textStyle: TextStyle(color: titleColor, fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFF0F172A).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
    );
  }

  static TextTheme _textTheme(
    TextTheme base,
    Color titleColor,
    Color bodyColor,
  ) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        color: titleColor,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: titleColor,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        color: titleColor,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        color: titleColor,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: titleColor,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: titleColor,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: titleColor,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: titleColor,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: titleColor,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: bodyColor,
        height: 1.5,
        letterSpacing: 0.05,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: bodyColor,
        height: 1.45,
        letterSpacing: 0.05,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: bodyColor,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}
