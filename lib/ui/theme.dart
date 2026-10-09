import 'package:flutter/material.dart';

/// Colours that aren't part of Material's [ColorScheme]: the laser accent
/// used for "data going onto the disc", the success green for verified
/// discs, and the disc surface itself.
@immutable
class DiscColors extends ThemeExtension<DiscColors> {
  final Color laser;
  final Color laserSoft;
  final Color verified;
  final Color existing;
  final Color discFace;
  final Color discGroove;
  final Color sidebar;

  const DiscColors({
    required this.laser,
    required this.laserSoft,
    required this.verified,
    required this.existing,
    required this.discFace,
    required this.discGroove,
    required this.sidebar,
  });

  static DiscColors of(BuildContext context) => Theme.of(context).extension<DiscColors>()!;

  @override
  DiscColors copyWith() => this;

  @override
  DiscColors lerp(DiscColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DiscColors(
      laser: l(laser, other.laser),
      laserSoft: l(laserSoft, other.laserSoft),
      verified: l(verified, other.verified),
      existing: l(existing, other.existing),
      discFace: l(discFace, other.discFace),
      discGroove: l(discGroove, other.discGroove),
      sidebar: l(sidebar, other.sidebar),
    );
  }
}

const _laser = Color(0xFFFF6B2C);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: _laser, brightness: brightness);
  final scheme = dark
      ? base.copyWith(
          primary: _laser,
          onPrimary: Colors.white,
          surface: const Color(0xFF111318),
          surfaceContainerLowest: const Color(0xFF0B0D11),
          surfaceContainerLow: const Color(0xFF15181E),
          surfaceContainer: const Color(0xFF191C23),
          surfaceContainerHigh: const Color(0xFF1F232B),
          surfaceContainerHighest: const Color(0xFF272B35),
          outline: const Color(0xFF3A3F4B),
          outlineVariant: const Color(0xFF262A33),
          onSurface: const Color(0xFFE8EAEF),
          onSurfaceVariant: const Color(0xFF9AA0AD),
        )
      : base.copyWith(
          primary: const Color(0xFFE5541A),
          onPrimary: Colors.white,
          surface: const Color(0xFFF7F7F9),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF1F2F5),
          surfaceContainer: const Color(0xFFECEDF1),
          surfaceContainerHigh: const Color(0xFFE5E7EC),
          surfaceContainerHighest: const Color(0xFFDDE0E6),
          outline: const Color(0xFFC3C7D0),
          outlineVariant: const Color(0xFFE0E2E8),
          onSurface: const Color(0xFF16181D),
          onSurfaceVariant: const Color(0xFF5D6370),
        );

  final ext = dark
      ? const DiscColors(
          laser: _laser,
          laserSoft: Color(0x33FF6B2C),
          verified: Color(0xFF3DDC97),
          existing: Color(0xFF5B6273),
          discFace: Color(0xFF1A1D24),
          discGroove: Color(0xFF242833),
          sidebar: Color(0xFF0D0F13),
        )
      : const DiscColors(
          laser: Color(0xFFE5541A),
          laserSoft: Color(0x26E5541A),
          verified: Color(0xFF14A06B),
          existing: Color(0xFFA6ACB8),
          discFace: Color(0xFFE9EBF0),
          discGroove: Color(0xFFDCDFE6),
          sidebar: Color(0xFFFFFFFF),
        );

  final text = ThemeData(
    brightness: brightness,
    useMaterial3: true,
  ).textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    extensions: [ext],
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
