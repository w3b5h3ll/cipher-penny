import 'package:flutter/material.dart';

// Same TDesign tokens as src/styles.css (design D9): values only, no component library.

class Td extends ThemeExtension<Td> {
  const Td({
    required this.brand,
    required this.brandHover,
    required this.brandActive,
    required this.brandLight,
    required this.error,
    required this.errorLight,
    required this.success,
    required this.textPrimary,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.bgPage,
    required this.bgContainer,
    required this.bgSecondaryContainer,
    required this.bgComponent,
    required this.stroke,
    required this.border,
    required this.shadow1,
  });

  final Color brand;
  final Color brandHover;
  final Color brandActive;
  final Color brandLight;
  final Color error;
  final Color errorLight;
  final Color success;
  final Color textPrimary;
  final Color textSecondary;
  final Color textPlaceholder;
  final Color bgPage;
  final Color bgContainer;
  final Color bgSecondaryContainer;
  final Color bgComponent;
  final Color stroke;
  final Color border;
  final List<BoxShadow> shadow1;

  Color get expense => error;
  Color get textAnti => Colors.white;

  static const radiusDefault = 3.0;
  static const radiusMedium = 6.0;
  static const radiusLarge = 9.0;

  /// `--td-comp-size-m` on touch screens.
  static const compSize = 40.0;
  static const compPaddingLR = 12.0;

  static const light = Td(
    brand: Color(0xFFE37318),
    brandHover: Color(0xFFFA9550),
    brandActive: Color(0xFFBE5A00),
    brandLight: Color(0xFFFFF1E9),
    error: Color(0xFFD54941),
    errorLight: Color(0xFFFFF0ED),
    success: Color(0xFF2BA471),
    textPrimary: Color(0xE6000000),
    textSecondary: Color(0x99000000),
    textPlaceholder: Color(0x66000000),
    bgPage: Color(0xFFF3F3F3),
    bgContainer: Color(0xFFFFFFFF),
    bgSecondaryContainer: Color(0xFFF3F3F3),
    bgComponent: Color(0xFFE7E7E7),
    stroke: Color(0xFFE7E7E7),
    border: Color(0xFFDCDCDC),
    shadow1: [
      BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x14000000), blurRadius: 5, offset: Offset(0, 4)),
      BoxShadow(color: Color(0x1F000000), blurRadius: 4, spreadRadius: -1, offset: Offset(0, 2)),
    ],
  );

  static const dark = Td(
    brand: Color(0xFFE37318),
    brandHover: Color(0xFFFA9550),
    brandActive: Color(0xFFBE5A00),
    brandLight: Color(0xFF3B1E0B),
    error: Color(0xFFE8665E),
    errorLight: Color(0xFF472324),
    success: Color(0xFF4FBD8A),
    textPrimary: Color(0xE6FFFFFF),
    textSecondary: Color(0x8CFFFFFF),
    textPlaceholder: Color(0x59FFFFFF),
    bgPage: Color(0xFF181818),
    bgContainer: Color(0xFF242424),
    bgSecondaryContainer: Color(0xFF2C2C2C),
    bgComponent: Color(0xFF4B4B4B),
    stroke: Color(0xFF383838),
    border: Color(0xFF4B4B4B),
    shadow1: [],
  );

  static Td of(BuildContext context) => Theme.of(context).extension<Td>()!;

  @override
  Td copyWith() => this;

  @override
  Td lerp(Td? other, double t) => t < 0.5 || other == null ? this : other;
}

/// TDesign type scale with the web's `font-feature-settings: 'cv11'`.
abstract final class TdText {
  static const _features = [FontFeature('cv11')];

  static TextStyle _style(double size, double lineHeight, [FontWeight weight = FontWeight.w400]) => TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        fontFeatures: _features,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static final body = _style(14, 22);
  static final mark = _style(12, 20);
  static final titleSmall = _style(14, 22, FontWeight.w600);
  static final titleMedium = _style(16, 24, FontWeight.w600);
  static final titleLarge = _style(20, 28, FontWeight.w600);
  static final headlineSmall = _style(24, 32, FontWeight.w600);
  static final mono = _style(13, 20).copyWith(fontFamily: 'JetBrains Mono', fontFeatures: const []);

  /// `font-variant-numeric: tabular-nums` for amounts.
  static const tabular = [FontFeature('cv11'), FontFeature.tabularFigures()];
}

ThemeData buildTheme(Td td, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: td.brand,
    onPrimary: td.textAnti,
    primaryContainer: td.brandLight,
    onPrimaryContainer: td.brandActive,
    secondary: td.brand,
    onSecondary: td.textAnti,
    error: td.error,
    onError: td.textAnti,
    errorContainer: td.errorLight,
    onErrorContainer: td.error,
    surface: td.bgContainer,
    onSurface: td.textPrimary,
    onSurfaceVariant: td.textSecondary,
    outline: td.border,
    outlineVariant: td.stroke,
    surfaceContainerLowest: td.bgContainer,
    surfaceContainerLow: td.bgContainer,
    surfaceContainer: td.bgContainer,
    surfaceContainerHigh: td.bgContainer,
    surfaceContainerHighest: td.bgComponent,
    surfaceTint: Colors.transparent,
  );

  final textTheme = TextTheme(
    headlineSmall: TdText.headlineSmall,
    titleLarge: TdText.titleLarge,
    titleMedium: TdText.titleMedium,
    titleSmall: TdText.titleSmall,
    bodyLarge: TdText.body,
    bodyMedium: TdText.body,
    bodySmall: TdText.mark,
    labelLarge: TdText.body,
    labelMedium: TdText.mark,
    labelSmall: TdText.mark,
  ).apply(bodyColor: td.textPrimary, displayColor: td.textPrimary);

  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Td.radiusDefault)));
  const minSize = Size(0, Td.compSize);
  const padding = EdgeInsets.symmetric(horizontal: Td.compPaddingLR);

  // Web buttons fade to 45 % opacity when disabled.
  Color faded(Color c) => c.withValues(alpha: c.a * 0.45);

  OutlineInputBorder outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Td.radiusDefault),
        borderSide: BorderSide(color: color),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [td],
    fontFamily: 'Inter',
    textTheme: textTheme,
    scaffoldBackgroundColor: td.bgPage,
    splashFactory: NoSplash.splashFactory,
    highlightColor: td.bgSecondaryContainer,
    hoverColor: td.bgSecondaryContainer,
    dividerTheme: DividerThemeData(color: td.stroke, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: td.bgContainer,
      foregroundColor: td.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      centerTitle: false,
      titleTextStyle: TdText.titleMedium.copyWith(color: td.textPrimary),
      shape: Border(bottom: BorderSide(color: td.stroke)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: td.bgContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      hintStyle: TdText.body.copyWith(color: td.textPlaceholder),
      errorStyle: TdText.mark.copyWith(color: td.error),
      border: outline(td.border),
      enabledBorder: outline(td.border),
      disabledBorder: outline(td.stroke),
      focusedBorder: outline(td.brand),
      errorBorder: outline(td.error),
      focusedErrorBorder: outline(td.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        shape: const WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(TdText.body),
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? faded(td.textAnti) : td.textAnti),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return faded(td.brand);
          if (s.contains(WidgetState.pressed)) return td.brandActive;
          return td.brand;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        shape: const WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(TdText.body),
        backgroundColor: WidgetStatePropertyAll(td.bgContainer),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return faded(td.textPrimary);
          if (s.contains(WidgetState.pressed)) return td.brand;
          return td.textPrimary;
        }),
        side: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return BorderSide(color: faded(td.border));
          if (s.contains(WidgetState.pressed)) return BorderSide(color: td.brandHover);
          return BorderSide(color: td.border);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(shape),
        textStyle: WidgetStatePropertyAll(TdText.body),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? faded(td.brand) : td.brand),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(2))),
      side: BorderSide(color: td.border, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? td.brand : Colors.transparent),
      checkColor: WidgetStatePropertyAll(td.textAnti),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: td.bgContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Td.radiusLarge))),
      contentTextStyle: TdText.body.copyWith(color: td.textPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Td.radiusMedium))),
      contentTextStyle: TdText.body.copyWith(color: Colors.white),
    ),
    popupMenuTheme: PopupMenuThemeData(color: td.bgContainer, surfaceTintColor: Colors.transparent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: td.brand),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: td.bgContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Td.radiusLarge))),
    ),
  );
}
