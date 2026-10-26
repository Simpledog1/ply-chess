import 'package:flutter/material.dart';

import '../analysis/review.dart';

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
    required this.text,
    required this.muted,
  });

  final Color background; // page
  final Color panel; // cards / side panel
  final Color panelHigh; // section headers, tabs
  final Color input; // fields
  final Color button; // dark secondary button (Analyse)
  final Color text;
  final Color muted;

  static const dark = PlyPalette(
    background: Color(0xFF0C0F14),
    panel: Color(0xFF1A1D23),
    panelHigh: Color(0xFF23272E),
    input: Color(0xFF15181D),
    button: Color(0xFF1E2840),
    text: Color(0xFFE8EAED),
    muted: Color(0xFF9AA3AD),
  );

  static const light = PlyPalette(
    background: Color(0xFFF1F3F6),
    panel: Color(0xFFFFFFFF),
    panelHigh: Color(0xFFE6E9EE),
    input: Color(0xFFF6F7F9),
    button: Color(0xFFDCE4F7),
    text: Color(0xFF15181D),
    muted: Color(0xFF5D6670),
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
        outlineVariant: p.panelHigh,
      );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: p.background,
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
