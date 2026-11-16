import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

/// Urban Thread look: the logo's black and thread-gold on a cool chalk
/// canvas. Hairline seams instead of shadows, slightly tight corners
/// (like a card swing tag), and one wide face for headings and money.
class AppTheme {
  // ── Palette ──
  static const ink = Color(0xFF16171B); // brand black: text, primary actions
  static const gold = Color(0xFFA68D50); // the thread in the logo
  static const goldText = Color(
    0xFF7C6833,
  ); // gold dark enough to read on white
  static const background = Color(0xFFEFEFEC); // chalk
  static const surface = Colors.white;
  static const border = Color(0xFFDCDCD6);
  static const muted = Color(0xFF6A6B70);

  // Status (muted, dye-like, so they sit with the brand colours).
  static const danger = Color(0xFFA8432F); // madder
  static const success = Color(0xFF4E7448); // moss
  static const warning = Color(0xFFB07A1E); // ochre

  // Legacy names still used by screens.
  static const brand = ink;
  static const brandDeep = ink;
  static const accent = gold;

  static const radius = 10.0;
  static const font = 'Archivo';
  static const display = 'ArchivoExpanded';

  /// Money and counts: wide face with tabular figures so columns line up.
  static TextStyle figure(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w800,
  }) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.1,
    letterSpacing: size > 24 ? -0.5 : 0,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: ink,
          brightness: Brightness.light,
        ).copyWith(
          primary: ink,
          onPrimary: Colors.white,
          secondary: gold,
          onSecondary: ink,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: border,
          error: danger,
          surfaceContainerLowest: surface,
          surfaceContainerLow: surface,
          surfaceContainer: surface,
          surfaceContainerHigh: surface,
          surfaceContainerHighest: const Color(0xFFF4F4F1),
        );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: font,
    );
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);

    // Type scale (≈ 1.25 ratio): 12 / 13 / 15 / 17 / 21 / 26 / 33.
    TextStyle wide(double size, FontWeight w) => TextStyle(
      fontFamily: display,
      fontSize: size,
      fontWeight: w,
      color: ink,
      letterSpacing: -0.2,
      height: 1.15,
    );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c, width: w),
    );

    final squared = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    const buttonText = TextStyle(
      fontFamily: font,
      fontWeight: FontWeight.w600,
      fontSize: 15,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      textTheme: text.copyWith(
        displaySmall: wide(33, FontWeight.w800),
        headlineMedium: wide(26, FontWeight.w800),
        headlineSmall: wide(21, FontWeight.w800),
        titleLarge: wide(17, FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
        bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: muted),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),

      // ── App bar: flat on the canvas, wide-face title ──
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: Colors.transparent)),
        centerTitle: false,
        titleTextStyle: wide(19, FontWeight.w800),
        iconTheme: const IconThemeData(color: ink),
        actionsIconTheme: const IconThemeData(color: ink),
      ),

      // ── Bottom navigation (phones): gold thread under the active tab ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: gold.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
      ),

      // ── Cards: white panel, one hairline seam, no shadow ──
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: field(border),
        enabledBorder: field(border),
        focusedBorder: field(ink, 1.6),
        errorBorder: field(danger.withValues(alpha: 0.6)),
        focusedErrorBorder: field(danger, 1.6),
        labelStyle: const TextStyle(fontFamily: font, color: muted),
        floatingLabelStyle: const TextStyle(fontFamily: font, color: ink),
        hintStyle: TextStyle(
          fontFamily: font,
          color: muted.withValues(alpha: 0.8),
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),

      // ── Buttons: ink is the action colour ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48),
          shape: squared,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: squared,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 48),
          shape: squared,
          side: const BorderSide(color: border, width: 1.2),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          shape: squared,
          textStyle: buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        extendedTextStyle: buttonText,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: squared),
      ),

      // ── Chips, segmented buttons, switches ──
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: ink,
        secondarySelectedColor: ink,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        // Chips resolve only the label *colour* per state (not the whole
        // style), so the selected/unselected switch must live in the colour.
        labelStyle: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : ink,
          ),
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          selectedBackgroundColor: ink,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: border),
          shape: squared,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : null,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : muted,
        ),
      ),

      // ── Sheets, dialogs, snackbars ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        constraints: BoxConstraints(maxWidth: 640),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: wide(19, FontWeight.w800),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        actionTextColor: gold,
        contentTextStyle: const TextStyle(
          fontFamily: font,
          color: Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        width: 420,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontFamily: font,
          color: Colors.white,
          fontSize: 12,
        ),
      ),

      // ── Lists & dividers ──
      listTileTheme: const ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontFamily: font,
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: font,
          color: muted,
          fontSize: 13,
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ink,
        linearTrackColor: border,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: danger,
        textColor: Colors.white,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
