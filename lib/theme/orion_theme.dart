import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/orion_theme_preferences.dart';
import '../widgets/orion_glass.dart';
import 'orion_typography.dart';
import 'orion_density.dart';
export 'orion_typography.dart';

class OrionColors extends ThemeExtension<OrionColors> {
  final Color background,
      panel,
      elevated,
      border,
      muted,
      accent,
      ink,
      lavender,
      peach;
  final Color editorColor;
  final LinearGradient? backgroundGradient;
  final double outlineStrength, surfaceTint;
  final bool transparentSurfaces;
  final bool glassEnabled;
  final Set<String> opaqueSurfaceRoles;
  const OrionColors({
    required this.background,
    required this.panel,
    required this.elevated,
    required this.border,
    required this.muted,
    required this.accent,
    required this.ink,
    required this.lavender,
    required this.peach,
    Color? editorColor,
    this.backgroundGradient,
    this.outlineStrength = 1,
    this.surfaceTint = 0,
    this.transparentSurfaces = false,
    this.glassEnabled = false,
    this.opaqueSurfaceRoles = const {},
  }) : editorColor = editorColor ?? panel;
  static OrionColors of(BuildContext context) =>
      Theme.of(context).extension<OrionColors>()!;

  // Keep pastel fills while giving text and thin icons enough contrast.
  bool get isLight => background.computeLuminance() > .5;
  Color get readableAccent =>
      _readable(isLight ? Color.lerp(accent, ink, .7)! : accent, [panel]);
  Color get onAccent => _onFill(
    accent,
    preferred: _isNeutral(accent)
        ? const Color(0xFF17191B)
        : const Color(0xFF092C57),
  );
  Color outline([double alpha = .18]) => border.withValues(
    alpha: alpha.isFinite ? (alpha * outlineStrength).clamp(0, 1) : 0,
  );
  // Keep the palette opaque for readable overlays; only page chrome clears.
  Color chrome(Color color, {String? role}) =>
      transparentSurfaces && !opaqueSurfaceRoles.contains(role)
      ? Colors.transparent
      : color;
  Color stateFill(double opacity, {Color? base}) => transparentSurfaces
      ? accent.withValues(alpha: opacity)
      : Color.alphaBlend(accent.withValues(alpha: opacity), base ?? panel);
  Color get readableLavender => isLight
      ? Color.lerp(
          lavender,
          _isNeutral(lavender) ? ink : const Color(0xFF463066),
          .7,
        )!
      : lavender;
  Color get readablePeach => isLight
      ? Color.lerp(
          peach,
          _isNeutral(peach) ? ink : const Color(0xFF703C2D),
          .76,
        )!
      : peach;

  Color readableForeground(Color color) =>
      isLight && color.computeLuminance() > .24
      ? Color.lerp(color, ink, .7)!
      : color;

  @override
  OrionColors copyWith({
    Color? background,
    Color? panel,
    Color? elevated,
    Color? border,
    Color? muted,
    Color? accent,
    Color? ink,
    Color? lavender,
    Color? peach,
    Color? editorColor,
    LinearGradient? backgroundGradient,
    double? outlineStrength,
    double? surfaceTint,
    bool? transparentSurfaces,
    bool? glassEnabled,
    Set<String>? opaqueSurfaceRoles,
  }) => OrionColors(
    background: background ?? this.background,
    panel: panel ?? this.panel,
    elevated: elevated ?? this.elevated,
    border: border ?? this.border,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    ink: ink ?? this.ink,
    lavender: lavender ?? this.lavender,
    peach: peach ?? this.peach,
    editorColor: editorColor ?? this.editorColor,
    backgroundGradient: backgroundGradient ?? this.backgroundGradient,
    outlineStrength: outlineStrength ?? this.outlineStrength,
    surfaceTint: surfaceTint ?? this.surfaceTint,
    transparentSurfaces: transparentSurfaces ?? this.transparentSurfaces,
    glassEnabled: glassEnabled ?? this.glassEnabled,
    opaqueSurfaceRoles: opaqueSurfaceRoles ?? this.opaqueSurfaceRoles,
  );
  @override
  OrionColors lerp(OrionColors? other, double t) => other == null
      ? this
      : OrionColors(
          background: Color.lerp(background, other.background, t)!,
          panel: Color.lerp(panel, other.panel, t)!,
          elevated: Color.lerp(elevated, other.elevated, t)!,
          border: Color.lerp(border, other.border, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          lavender: Color.lerp(lavender, other.lavender, t)!,
          peach: Color.lerp(peach, other.peach, t)!,
          editorColor: Color.lerp(editorColor, other.editorColor, t)!,
          backgroundGradient: LinearGradient.lerp(
            backgroundGradient,
            other.backgroundGradient,
            t,
          ),
          outlineStrength:
              outlineStrength + (other.outlineStrength - outlineStrength) * t,
          surfaceTint: surfaceTint + (other.surfaceTint - surfaceTint) * t,
          transparentSurfaces: t < .5
              ? transparentSurfaces
              : other.transparentSurfaces,
          glassEnabled: t < .5 ? glassEnabled : other.glassEnabled,
          opaqueSurfaceRoles: t < .5
              ? opaqueSurfaceRoles
              : other.opaqueSurfaceRoles,
        );
}

ThemeData orionTheme(
  Brightness brightness,
  Color accent, {
  bool reducedMotion = false,
  bool compactMode = false,
  OrionThemePreferences? preferences,
  String? fontFamily,
}) {
  final family = fontFamily ?? OrionType.family;
  final density = compactMode ? OrionDensity.compact : OrionDensity.comfortable;
  final dark = brightness == Brightness.dark;
  var colors = OrionColors(
    background: dark ? const Color(0xFF11151B) : const Color(0xFFF0F3F8),
    panel: dark ? const Color(0xFF181E27) : const Color(0xFFF8FAFE),
    elevated: dark ? const Color(0xFF222B37) : const Color(0xFFE6ECF5),
    border: dark ? const Color(0xFF303C4D) : const Color(0xFFD2DAE7),
    muted: dark ? const Color(0xFF9FAFC4) : const Color(0xFF58677C),
    accent: preferences?.accent ?? accent,
    ink: dark ? const Color(0xFFF0F4FA) : const Color(0xFF1B2738),
    lavender: const Color(0xFFC7B9F8),
    peach: const Color(0xFFF3BBA1),
  );
  final prefs = preferences;
  if (prefs != null) {
    if (prefs.basePalette == 'original-orion') {
      Color baseRole(String name) {
        final authored = OrionThemePreferences.originalPalette[name]!;
        if (dark) return authored;
        // The classic light variant stays neutral too, without inheriting
        // Expressive's blue-tinted paper, labels or panel surfaces.
        return const {
          'background': Color(0xFFF1F1F1),
          'panel': Color(0xFFF9F9F9),
          'elevated': Color(0xFFE7E7E7),
          'border': Color(0xFFD0D0D0),
          'ink': Color(0xFF1D1D1D),
          'muted': Color(0xFF666666),
          'editor': Color(0xFFF6F6F6),
        }[name]!;
      }

      colors = colors.copyWith(
        background: baseRole('background'),
        panel: baseRole('panel'),
        elevated: baseRole('elevated'),
        border: baseRole('border'),
        ink: baseRole('ink'),
        muted: baseRole('muted'),
        editorColor: baseRole('editor'),
        lavender: const Color(0xFFC6C6C6),
        peach: const Color(0xFFB8B8B8),
      );
    }
    if (prefs.basePalette == 'material-rain') {
      Color baseRole(String name) => dark
          ? OrionThemePreferences.materialRainPalette[name]!
          : const {
              'background': Color(0xFFF2F2F3),
              'panel': Color(0xFFFAFAFA),
              'elevated': Color(0xFFE8E8EB),
              'border': Color(0xFFCBCDD2),
              'ink': Color(0xFF16181B),
              'muted': Color(0xFF5F646B),
              'editor': Color(0xFFFFFFFF),
            }[name]!;
      colors = colors.copyWith(
        background: baseRole('background'),
        panel: baseRole('panel'),
        elevated: baseRole('elevated'),
        border: baseRole('border'),
        ink: baseRole('ink'),
        muted: baseRole('muted'),
        editorColor: baseRole('editor'),
        lavender: dark ? const Color(0xFFB8C4DA) : const Color(0xFF556274),
        peach: dark ? const Color(0xFFB7C0D2) : const Color(0xFF586577),
      );
    }
    if (prefs.basePalette == 'liquid-glass') {
      Color baseRole(String name) => dark
          ? OrionThemePreferences.liquidGlassPalette[name]!
          : const {
              'background': Color(0xFFE9F1F8),
              'panel': Color(0xFFF8FBFF),
              'elevated': Color(0xFFDCE8F3),
              'border': Color(0xFF8197AF),
              'ink': Color(0xFF142234),
              'muted': Color(0xFF455C72),
              'editor': Color(0xFFE4EDF6),
            }[name]!;
      colors = colors.copyWith(
        background: baseRole('background'),
        panel: baseRole('panel'),
        elevated: baseRole('elevated'),
        border: baseRole('border'),
        ink: baseRole('ink'),
        muted: baseRole('muted'),
        editorColor: baseRole('editor'),
        lavender: dark ? const Color(0xFFC9D4F0) : const Color(0xFF536783),
        peach: dark ? const Color(0xFFE4CFBD) : const Color(0xFF79604D),
      );
    }
    final overrides = prefs.overrides;
    Color role(String name, Color fallback) => overrides[name] ?? fallback;

    Color tinted(Color color) => Color.alphaBlend(
      colors.accent.withValues(alpha: prefs.surfaceTint * .16),
      color,
    );
    final background = role('background', colors.background);
    final panel = role('panel', tinted(colors.panel));
    final elevated = role('elevated', tinted(colors.elevated));
    final editor = role('editor', tinted(colors.editorColor));
    final gradientColors = prefs.gradientColors
        .map((color) => _gradientTone(color, dark))
        .toList();
    final radians = prefs.gradientAngle * math.pi / 180;
    final dx = math.cos(radians), dy = math.sin(radians);
    final extent = math.max(dx.abs(), dy.abs());
    final gradient = prefs.gradientEnabled
        ? LinearGradient(
            begin: Alignment(-dx / extent, -dy / extent),
            end: Alignment(dx / extent, dy / extent),
            colors: gradientColors,
            stops: prefs.gradientStops,
          )
        : null;
    final surfaces = [
      background,
      panel,
      elevated,
      editor,
      if (gradient != null) ...gradientColors,
    ];
    colors = colors.copyWith(
      background: background,
      panel: panel,
      elevated: elevated,
      editorColor: editor,
      border: role('border', colors.border),
      ink: _readable(role('ink', colors.ink), surfaces),
      muted: _readable(role('muted', colors.muted), surfaces),
      lavender: role('lavender', colors.lavender),
      peach: role('peach', colors.peach),
      backgroundGradient: gradient,
      outlineStrength: prefs.outlineStrength,
      surfaceTint: prefs.surfaceTint,
      transparentSurfaces:
          prefs.basePalette == 'original-orion' || prefs.liquidGlassEnabled,
      glassEnabled: prefs.liquidGlassEnabled,
      opaqueSurfaceRoles: Set.unmodifiable(prefs.overrides.keys),
    );
  }
  accent = colors.accent;
  // Rain's actions keep their deep blue fill; thin labels and icons continue
  // to use readableAccent, which has separate contrast against dark surfaces.
  final primary = prefs?.basePalette == 'material-rain'
      ? colors.accent
      : colors.readableAccent;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        dynamicSchemeVariant:
            prefs?.basePalette == 'original-orion' && _isNeutral(accent)
            ? DynamicSchemeVariant.monochrome
            : DynamicSchemeVariant.tonalSpot,
      ).copyWith(
        primary: primary,
        onPrimary: _onFill(
          primary,
          preferred: dark ? colors.onAccent : Colors.white,
        ),
        primaryContainer: Color.alphaBlend(
          accent.withValues(alpha: dark ? .15 : .2),
          colors.elevated,
        ),
        onPrimaryContainer: colors.readableAccent,
        secondaryContainer: Color.alphaBlend(
          accent.withValues(alpha: .1),
          colors.elevated,
        ),
        onSecondaryContainer: colors.ink,
        surface: colors.panel,
        surfaceContainerLowest: colors.background,
        surfaceContainerLow: Color.lerp(colors.panel, colors.elevated, .2),
        surfaceContainer: colors.panel,
        surfaceContainerHigh: colors.elevated,
        surfaceContainerHighest: Color.lerp(colors.elevated, colors.border, .3),
        onSurface: colors.ink,
        onSurfaceVariant: colors.muted,
        outline: colors.outline(1),
        outlineVariant: colors.outline(.45),
      );
  final actionShape = WidgetStateProperty.resolveWith<OutlinedBorder>((states) {
    final pressed = states.contains(WidgetState.pressed) && !reducedMotion;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        colors.glassEnabled ? 20 : (pressed ? 12 : 24),
      ),
    );
  });
  ButtonLayerBuilder? glassButtonBackground({bool primary = false}) =>
      colors.glassEnabled
      ? (context, states, child) {
          final disabled = states.contains(WidgetState.disabled);
          final fillAlpha = primary
              ? disabled
                    ? .07
                    : states.contains(WidgetState.pressed)
                    ? .34
                    : states.contains(WidgetState.hovered)
                    ? .28
                    : .22
              : disabled
              ? 0.0
              : states.contains(WidgetState.pressed)
              ? .05
              : states.contains(WidgetState.hovered)
              ? .025
              : 0.0;
          return Builder(
            builder: (materialContext) {
              // ButtonStyle invokes its layer builder above Material. Resolve
              // its actual shape once this layer is mounted inside Material.
              final shape =
                  materialContext
                      .findAncestorWidgetOfExactType<Material>()
                      ?.shape ??
                  actionShape.resolve(states);
              final fillShape = shape is OutlinedBorder
                  ? shape.copyWith(side: BorderSide.none)
                  : shape;
              if (OrionGlassSurface.hasMaterialAncestor(materialContext)) {
                // Fill and outline share the resolved geometry even when a
                // button overrides its corners or leaves Material unclipped.
                return ClipPath(
                  clipper: _ButtonInteriorClipper(
                    shape,
                    Directionality.of(materialContext),
                  ),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: fillShape,
                      color: colors.accent.withValues(alpha: fillAlpha),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              }
              return ClipPath(
                clipper: _ButtonInteriorClipper(
                  shape,
                  Directionality.of(materialContext),
                ),
                child: OrionGlassSurface(
                  radius: 20,
                  borderRadius: shape is RoundedRectangleBorder
                      ? shape.borderRadius
                      : null,
                  shape: fillShape,
                  interactive: !disabled,
                  tint: colors.accent.withValues(alpha: fillAlpha),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          );
        }
      : null;
  final actionDuration = reducedMotion
      ? Duration.zero
      : const Duration(milliseconds: 160);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: family,
    scaffoldBackgroundColor: colors.background,
    extensions: [colors, density],
  );
  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          headlineSmall: OrionType.pageTitle.copyWith(color: colors.ink),
          titleLarge: OrionType.sectionTitle.copyWith(color: colors.ink),
          titleMedium: OrionType.sectionTitle.copyWith(color: colors.ink),
          titleSmall: OrionType.label.copyWith(
            fontFamily: family,
            color: colors.ink,
          ),
          bodyLarge: OrionType.body.copyWith(
            fontFamily: family,
            color: colors.ink,
          ),
          bodyMedium: OrionType.body.copyWith(
            fontFamily: family,
            color: colors.ink,
          ),
          bodySmall: OrionType.metadata.copyWith(color: colors.muted),
          labelLarge: OrionType.label.copyWith(
            fontFamily: family,
            color: colors.ink,
          ),
          labelMedium: OrionType.label.copyWith(
            fontFamily: family,
            color: colors.ink,
          ),
          labelSmall: OrionType.metadata.copyWith(color: colors.muted),
        )
        .apply(fontFamily: family),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: colors.glassEnabled
            ? null
            : Border.all(color: colors.outline(.4)),
      ),
      textStyle: OrionType.label.copyWith(
        fontFamily: family,
        color: colors.ink,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.chrome(colors.accent),
            foregroundColor: colors.glassEnabled
                ? colors.ink
                : colors.transparentSurfaces
                ? colors.readableAccent
                : colors.onAccent,
            side: colors.glassEnabled
                ? BorderSide.none
                : colors.outlineStrength > 1
                ? BorderSide(color: colors.outline(.3), width: .67)
                : null,
            minimumSize: Size(48, density.mix(36, 32)),
            padding: EdgeInsets.symmetric(
              horizontal: density.mix(16, 12),
              vertical: density.mix(10, 8),
            ),
            textStyle: OrionType.label.copyWith(fontFamily: family),
          ).copyWith(
            shape: actionShape,
            animationDuration: actionDuration,
            backgroundBuilder: glassButtonBackground(primary: true),
          ),
    ),
    elevatedButtonTheme: colors.glassEnabled
        ? ElevatedButtonThemeData(
            style:
                ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: colors.ink,
                  elevation: 0,
                  minimumSize: Size(48, density.mix(36, 32)),
                ).copyWith(
                  shape: actionShape,
                  animationDuration: actionDuration,
                  backgroundBuilder: glassButtonBackground(),
                ),
          )
        : null,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: Size(48, density.mix(36, 32)),
            foregroundColor: colors.ink,
            side: colors.glassEnabled
                ? BorderSide.none
                : BorderSide(color: colors.outline(.7)),
            padding: EdgeInsets.symmetric(
              horizontal: density.mix(16, 12),
              vertical: density.mix(10, 8),
            ),
            textStyle: OrionType.label.copyWith(fontFamily: family),
          ).copyWith(
            shape: actionShape,
            animationDuration: actionDuration,
            backgroundBuilder: glassButtonBackground(),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: colors.glassEnabled
                ? colors.ink
                : colors.readableAccent,
            minimumSize: Size(40, density.mix(36, 32)),
            padding: EdgeInsets.symmetric(
              horizontal: density.mix(14, 10),
              vertical: density.mix(10, 8),
            ),
            textStyle: OrionType.label.copyWith(fontFamily: family),
          ).copyWith(
            shape: actionShape,
            animationDuration: actionDuration,
            backgroundBuilder: glassButtonBackground(),
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        hoverColor: colors.accent.withValues(alpha: .08),
        focusColor: colors.accent.withValues(alpha: .12),
        highlightColor: colors.accent.withValues(alpha: .16),
      ).copyWith(shape: actionShape, animationDuration: actionDuration),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        animationDuration: actionDuration,
        minimumSize: WidgetStatePropertyAll(Size(0, density.mix(36, 32))),
        shape: actionShape,
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.chrome(colors.elevated, role: 'elevated');
          }
          return states.contains(WidgetState.selected)
              ? colors.transparentSurfaces
                    ? colors.stateFill(.08)
                    : colors.accent
              : colors.chrome(colors.elevated, role: 'elevated');
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return colors.muted;
          return states.contains(WidgetState.selected)
              ? colors.transparentSurfaces
                    ? colors.readableAccent
                    : colors.onAccent
              : colors.ink;
        }),
        textStyle: WidgetStatePropertyAll(
          OrionType.label.copyWith(fontFamily: family),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.chrome(colors.elevated, role: 'elevated'),
      selectedColor: colors.transparentSurfaces
          ? colors.stateFill(.08)
          : scheme.primaryContainer,
      secondarySelectedColor: colors.transparentSurfaces
          ? colors.stateFill(.08)
          : scheme.primaryContainer,
      checkmarkColor: colors.readableAccent,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: OrionType.label.copyWith(
        fontFamily: family,
        color: colors.ink,
      ),
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.chrome(colors.elevated, role: 'elevated'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: colors.transparentSurfaces && !colors.glassEnabled
            ? BorderSide(color: colors.outline(.45), width: .67)
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.readableAccent, width: 1.5),
      ),
      hintStyle: OrionType.body.copyWith(
        fontFamily: family,
        color: colors.muted,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: OrionType.sectionTitle.copyWith(
        fontFamily: family,
        fontSize: 22,
        color: colors.ink,
      ),
      contentTextStyle: OrionType.body.copyWith(
        fontFamily: family,
        color: colors.muted,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      menuPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      textStyle: OrionType.body.copyWith(fontFamily: family, color: colors.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.elevated,
      contentTextStyle: OrionType.body.copyWith(
        fontFamily: family,
        color: colors.ink,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outline(colors.glassEnabled ? .18 : .5),
      space: 1,
      thickness: 1,
    ),
  );
}

// Button background layers paint after Material's outline. Keep their tint
// inside that outline so thin borders retain their authored color.
class _ButtonInteriorClipper extends CustomClipper<Path> {
  const _ButtonInteriorClipper(this.shape, this.textDirection);

  final ShapeBorder shape;
  final TextDirection textDirection;

  @override
  Path getClip(Size size) =>
      shape.getInnerPath(Offset.zero & size, textDirection: textDirection);

  @override
  bool shouldReclip(_ButtonInteriorClipper oldClipper) =>
      shape != oldClipper.shape || textDirection != oldClipper.textDirection;
}

bool _isNeutral(Color color) {
  final channels = [color.r, color.g, color.b];
  return channels.reduce(math.max) - channels.reduce(math.min) < .025;
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

Color _onFill(Color fill, {required Color preferred}) {
  if (_contrast(fill, preferred) >= 4.5) return preferred;
  return _contrast(fill, Colors.black) > _contrast(fill, Colors.white)
      ? Colors.black
      : Colors.white;
}

Color _readable(Color preferred, List<Color> surfaces) {
  double minimum(Color color) =>
      surfaces.map((surface) => _contrast(surface, color)).reduce(math.min);
  if (minimum(preferred) >= 4.5) return preferred;
  final target = minimum(Colors.white) > minimum(Colors.black)
      ? Colors.white
      : Colors.black;
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(preferred, target, step / 20)!;
    if (minimum(candidate) >= 4.5) return candidate;
  }
  return target;
}

Color _gradientTone(Color color, bool dark) {
  bool suitable(Color candidate) => dark
      ? candidate.computeLuminance() <= .12
      : candidate.computeLuminance() >= .72;
  if (suitable(color)) return color;
  final target = dark ? Colors.black : Colors.white;
  var low = 0.0, high = 1.0;
  for (var step = 0; step < 16; step++) {
    final amount = (low + high) / 2;
    if (suitable(Color.lerp(color, target, amount)!)) {
      high = amount;
    } else {
      low = amount;
    }
  }
  return Color.lerp(color, target, high)!;
}
