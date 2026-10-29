import 'package:flutter/material.dart';

import '../analysis/review.dart';

/// Windows at least this wide get the three-column desktop layout.
const desktopWidth = 1000.0;

/// Accent blue from the design references ("Game Analysis" header).
const plyBlue = Color(0xFF1C4DC4);

/// Surface colours for the dark design and its light counterpart.
class PlyPalette {
  const PlyPalette({
    required this.background,
    required this.panel,
    required this.panelHigh,
    required this.input,
    required this.button,
    required this.border,
    required this.text,
    required this.muted,
  });

  final Color background; // page
  final Color panel; // cards / side panel
  final Color panelHigh; // raised cards inside panels, section headers
  final Color input; // fields
  final Color button; // accent-tinted secondary surface
  final Color border; // hairlines around panels and cards
  final Color text;
  final Color muted;

  static const dark = PlyPalette(
    background: Color(0xFF0E1116),
    panel: Color(0xFF161A20),
    panelHigh: Color(0xFF1F242C),
    input: Color(0xFF11151A),
    button: Color(0xFF1D2A45),
    border: Color(0xFF2A313B),
    text: Color(0xFFE6E9EE),
    muted: Color(0xFF98A2AE),
  );

  static const light = PlyPalette(
    background: Color(0xFFF2F4F7),
    panel: Color(0xFFFFFFFF),
    panelHigh: Color(0xFFF0F2F6),
    input: Color(0xFFF7F8FA),
    button: Color(0xFFDDE6F8),
    border: Color(0xFFDCE1E8),
    text: Color(0xFF14181E),
    muted: Color(0xFF5A6471),
  );

  /// Panel surface: rounded, with a hairline border.
  BoxDecoration panelBox({double radius = 12}) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
  );

  /// Raised card inside a panel.
  BoxDecoration cardBox({Color? accent, double radius = 10}) => BoxDecoration(
    color: panelHigh,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent?.withValues(alpha: 0.6) ?? border),
  );

  static PlyPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData plyTheme(Brightness b) {
  final p = b == Brightness.dark ? PlyPalette.dark : PlyPalette.light;
  final scheme = ColorScheme.fromSeed(seedColor: plyBlue, brightness: b)
      .copyWith(
        primary: b == Brightness.dark ? const Color(0xFF4F7BEA) : plyBlue,
        onPrimary: Colors.white,
        primaryContainer: plyBlue,
        onPrimaryContainer: Colors.white,
        surface: p.background,
        onSurface: p.text,
        onSurfaceVariant: p.muted,
        surfaceContainerLowest: p.input,
        surfaceContainerLow: p.panel,
        surfaceContainer: p.panel,
        surfaceContainerHigh: p.panelHigh,
        surfaceContainerHighest: p.panelHigh,
        secondaryContainer: p.button,
        onSecondaryContainer: p.text,
        outline: p.border,
        outlineVariant: p.border,
      );
  final base = ThemeData(brightness: b, useMaterial3: true).textTheme;
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: p.background,
    visualDensity: VisualDensity.compact,
    textTheme: base.copyWith(
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: base.bodySmall?.copyWith(height: 1.35),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: TextStyle(color: p.text, fontSize: 12),
      decoration: BoxDecoration(
        color: p.panelHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(6),
      radius: Radius.circular(3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: p.input,
      linearMinHeight: 5,
      borderRadius: BorderRadius.circular(3),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.panel,
      indicatorColor: plyBlue.withValues(alpha: 0.35),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.panel),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.panel),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? plyBlue : p.input,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : p.muted,
      ),
    ),
    dividerTheme: DividerThemeData(color: p.panelHigh),
  );
}

class BoardColors {
  // Slate-blue squares after the references, lightened so the black
  // Cburnett pieces keep enough contrast on dark squares.
  static const light = Color(0xFF9DB1BE);
  static const dark = Color(0xFF5E7889);
  static const lastMove = Color(0x66E5C14A);
  static const selected = Color(0x804F7BEA);
  static const dot = Color(0x59101820);
  static const arrow = Color(0xD94F7BEA);
  static const check = Color(0xFFE53935);
}

/// Classification colours and symbols in the style of common review tools.
Color classColor(MoveClass c) => switch (c) {
  MoveClass.brilliant => const Color(0xFF1BACA6),
  MoveClass.critical => const Color(0xFF5B8BB4),
  MoveClass.best => const Color(0xFF7FB13D),
  MoveClass.excellent => const Color(0xFF96BC4B),
  MoveClass.good => const Color(0xFF8AA79A),
  MoveClass.theory => const Color(0xFFC79A6C),
  MoveClass.inaccuracy => const Color(0xFFF2BE2B),
  MoveClass.mistake => const Color(0xFFF28B30),
  MoveClass.blunder => const Color(0xFFE5403A),
  MoveClass.forced => const Color(0xFF8C939B),
};

String classSymbol(MoveClass c) => switch (c) {
  MoveClass.brilliant => '!!',
  MoveClass.critical => '!',
  MoveClass.inaccuracy => '?!',
  MoveClass.mistake => '?',
  MoveClass.blunder => '??',
  _ => '',
};

IconData? classIcon(MoveClass c) => switch (c) {
  MoveClass.best => Icons.star_rounded,
  MoveClass.excellent => Icons.thumb_up_alt_rounded,
  MoveClass.good => Icons.check_rounded,
  MoveClass.theory => Icons.menu_book_rounded,
  MoveClass.forced => Icons.arrow_forward_rounded,
  _ => null,
};

/// Round badge for a classification (symbol or icon on its colour).
class ClassBadge extends StatelessWidget {
  const ClassBadge(this.cls, {super.key, this.size = 20});
  final MoveClass cls;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = classIcon(cls);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: classColor(cls),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black38)],
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: Colors.white, size: size * 0.7)
          : Text(
              classSymbol(cls),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.5,
                height: 1,
              ),
            ),
    );
  }
}
