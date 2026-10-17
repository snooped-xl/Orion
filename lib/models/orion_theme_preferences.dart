import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Orion's palette is independent of the preserved interfaces' source themes.
@immutable
class OrionThemePreferences {
  factory OrionThemePreferences({
    String presetId = 'expressive',
    String basePalette = 'expressive',
    ThemeMode themeMode = ThemeMode.dark,
    Color accent = const Color(0xFF88B5FF),
    bool gradientEnabled = false,
    bool rainEnabled = false,
    bool liquidGlassEnabled = false,
    double windowOpacity = 1,
    List<Color> gradientColors = defaultGradientColors,
    List<double>? gradientStops,
    double gradientAngle = 135,
    double surfaceTint = 0,
    double outlineStrength = 1,
    Map<String, Color> overrides = const {},
  }) {
    final colors = gradientColors.length >= 2
        ? gradientColors.take(4).map(_opaque).toList()
        : defaultGradientColors;
    final stops =
        gradientStops != null &&
            gradientStops.length == colors.length &&
            gradientStops.every(
              (stop) => stop.isFinite && stop >= 0 && stop <= 1,
            ) &&
            List.generate(
              gradientStops.length - 1,
              (i) => i,
            ).every((i) => gradientStops[i] <= gradientStops[i + 1])
        ? List<double>.unmodifiable(gradientStops)
        : null;
    return OrionThemePreferences._(
      presetId: presetId.trim().isEmpty
          ? 'custom'
          : presetId.trim().substring(0, presetId.trim().length.clamp(0, 80)),
      basePalette:
          const {
            'original-orion',
            'material-rain',
            'liquid-glass',
          }.contains(basePalette)
          ? basePalette
          : 'expressive',
      themeMode: themeMode,
      accent: _opaque(accent),
      gradientEnabled: gradientEnabled,
      rainEnabled: rainEnabled,
      liquidGlassEnabled: liquidGlassEnabled,
      windowOpacity: _bounded(windowOpacity, .5, 1, 1),
      gradientColors: List.unmodifiable(colors),
      gradientStops: stops,
      gradientAngle: gradientAngle.isFinite ? gradientAngle % 360 : 135,
      surfaceTint: _bounded(surfaceTint, 0, 1, 0),
      outlineStrength: _bounded(outlineStrength, 0, 2, 1),
      overrides: Map.unmodifiable({
        for (final role in colorRoles)
          if (overrides.containsKey(role)) role: _opaque(overrides[role]!),
      }),
    );
  }

  const OrionThemePreferences._({
    required this.presetId,
    required this.basePalette,
    required this.themeMode,
    required this.accent,
    required this.gradientEnabled,
    required this.rainEnabled,
    required this.liquidGlassEnabled,
    required this.windowOpacity,
    required this.gradientColors,
    required this.gradientStops,
    required this.gradientAngle,
    required this.surfaceTint,
    required this.outlineStrength,
    required this.overrides,
  });

  final String presetId, basePalette;
  final ThemeMode themeMode;
  final Color accent;
  final bool gradientEnabled, rainEnabled, liquidGlassEnabled;
  final double windowOpacity;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final double gradientAngle, surfaceTint, outlineStrength;
  final Map<String, Color> overrides;

  static const defaultGradientColors = [Color(0xFF11151B), Color(0xFF181E27)];
  static const originalAccent = Color(0xFFD5D5D5);
  static const materialRainAccent = Color(0xFF164A80);
  static const liquidGlassAccent = Color(0xFF62B0FF);
  static const primaryPresetCount = 5;
  static const liquidGlassPalette = {
    'background': Color(0xFF151719),
    'panel': Color(0xFF191C20),
    'elevated': Color(0xFF24282D),
    'border': Color(0xFF85919C),
    'ink': Color(0xFFF3F7FC),
    'muted': Color(0xFFBDC7D1),
    'editor': Color(0xFF151719),
  };
  static const materialRainPalette = {
    'background': Color(0xFF000000),
    'panel': Color(0xFF050505),
    'elevated': Color(0xFF101113),
    'border': Color(0xFF343638),
    'ink': Color(0xFFF5F6F7),
    'muted': Color(0xFFACAFB5),
    'editor': Color(0xFF000000),
  };
  // OrionWindow.axaml's authored roles, independent of manual fine controls.
  static const originalPalette = {
    'background': Color(0xFF08090A),
    'panel': Color(0xFF07080A),
    'elevated': Color(0xFF111315),
    'border': Color(0xFF303235),
    'ink': Color(0xFFFFFFFF),
    'muted': Color(0xFF7D7D80),
    'editor': Color(0xFF101112),
  };
  static const colorRoles = [
    'background',
    'panel',
    'elevated',
    'border',
    'ink',
    'muted',
    'editor',
    'lavender',
    'peach',
  ];
  static final defaults = OrionThemePreferences();
  static final List<OrionThemePreset> builtInPresets = List.unmodifiable([
    OrionThemePreset(
      id: 'expressive',
      name: 'Orion Expressive',
      description: 'Orion charcoal with clear blue actions.',
      preferences: defaults,
    ),
    OrionThemePreset(
      id: 'original-orion',
      name: 'Original Orion',
      description: 'Classic graphite, silver accents and fine outlines.',
      // OrionWindow.axaml semantic resources, lines 25–71.
      preferences: OrionThemePreferences(
        presetId: 'original-orion',
        basePalette: 'original-orion',
        accent: originalAccent,
        gradientEnabled: true,
        gradientColors: const [Color(0xFF181A1B), Color(0xFF08090A)],
        gradientStops: const [0, .37019],
        gradientAngle: 45,
        outlineStrength: 1.5,
      ),
    ),
    OrionThemePreset(
      id: 'material-rain',
      name: 'Material Rain',
      description: 'Black surfaces, deep blue actions and quiet rainfall.',
      preferences: OrionThemePreferences(
        presetId: 'material-rain',
        basePalette: 'material-rain',
        accent: materialRainAccent,
        rainEnabled: true,
        windowOpacity: .9,
      ),
    ),
    OrionThemePreset(
      id: 'liquid-glass',
      name: 'Glassy',
      description: 'Clear glass, a light neutral tint and blue actions.',
      preferences: OrionThemePreferences(
        presetId: 'liquid-glass',
        basePalette: 'liquid-glass',
        accent: liquidGlassAccent,
        liquidGlassEnabled: true,
        windowOpacity: .63,
        gradientEnabled: false,
        gradientColors: const [Color(0xFF151719), Color(0xFF191C20)],
        gradientAngle: 135,
        outlineStrength: .65,
      ),
    ),
    OrionThemePreset(
      id: 'blue-glass',
      name: 'Blue Glass',
      description: 'Blue glass with a soft angled gradient and clear actions.',
      preferences: OrionThemePreferences(
        presetId: 'blue-glass',
        basePalette: 'liquid-glass',
        accent: liquidGlassAccent,
        gradientEnabled: true,
        liquidGlassEnabled: true,
        windowOpacity: .63,
        gradientColors: const [Color(0xFF0057AD), Color(0xFF49525E)],
        gradientAngle: 41.48092830882346,
        surfaceTint: .15541865620736706,
        outlineStrength: .65,
      ),
    ),
    OrionThemePreset(
      id: 'midnight',
      name: 'Midnight',
      description: 'Deep navy with a quiet blue horizon.',
      preferences: OrionThemePreferences(
        presetId: 'midnight',
        accent: const Color(0xFF9CC6FF),
        gradientEnabled: true,
        gradientColors: const [
          Color(0xFF10182A),
          Color(0xFF172F48),
          Color(0xFF111821),
        ],
        gradientAngle: 30,
        surfaceTint: .3,
      ),
    ),
    OrionThemePreset(
      id: 'aurora',
      name: 'Aurora',
      description: 'Soft teal and indigo over dark slate.',
      preferences: OrionThemePreferences(
        presetId: 'aurora',
        accent: const Color(0xFF8FE0D0),
        gradientEnabled: true,
        gradientColors: const [
          Color(0xFF122C2E),
          Color(0xFF1E2341),
          Color(0xFF151B27),
        ],
        gradientAngle: 135,
        surfaceTint: .25,
      ),
    ),
    OrionThemePreset(
      id: 'ember',
      name: 'Ember',
      description: 'Warm graphite with a restrained peach glow.',
      preferences: OrionThemePreferences(
        presetId: 'ember',
        accent: const Color(0xFFF3BBA1),
        gradientEnabled: true,
        gradientColors: const [
          Color(0xFF2E2025),
          Color(0xFF211E30),
          Color(0xFF171A23),
        ],
        gradientAngle: 70,
        surfaceTint: .2,
      ),
    ),
  ]);

  OrionThemePreferences copyWith({
    String? presetId,
    String? basePalette,
    ThemeMode? themeMode,
    Color? accent,
    bool? gradientEnabled,
    bool? rainEnabled,
    bool? liquidGlassEnabled,
    double? windowOpacity,
    List<Color>? gradientColors,
    List<double>? gradientStops,
    bool clearGradientStops = false,
    double? gradientAngle,
    double? surfaceTint,
    double? outlineStrength,
    Map<String, Color>? overrides,
  }) => OrionThemePreferences(
    presetId: presetId ?? this.presetId,
    basePalette: basePalette ?? this.basePalette,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    gradientEnabled: gradientEnabled ?? this.gradientEnabled,
    rainEnabled: rainEnabled ?? this.rainEnabled,
    liquidGlassEnabled: liquidGlassEnabled ?? this.liquidGlassEnabled,
    windowOpacity: windowOpacity ?? this.windowOpacity,
    gradientColors: gradientColors ?? this.gradientColors,
    gradientStops: clearGradientStops
        ? null
        : gradientStops ?? this.gradientStops,
    gradientAngle: gradientAngle ?? this.gradientAngle,
    surfaceTint: surfaceTint ?? this.surfaceTint,
    outlineStrength: outlineStrength ?? this.outlineStrength,
    overrides: overrides ?? this.overrides,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'presetId': presetId,
    'basePalette': basePalette,
    'themeMode': themeMode.name,
    'accent': accent.toARGB32(),
    'gradientEnabled': gradientEnabled,
    'rainEnabled': rainEnabled,
    'liquidGlassEnabled': liquidGlassEnabled,
    'windowOpacity': windowOpacity,
    'gradientColors': gradientColors.map((color) => color.toARGB32()).toList(),
    if (gradientStops != null) 'gradientStops': gradientStops,
    'gradientAngle': gradientAngle,
    'surfaceTint': surfaceTint,
    'outlineStrength': outlineStrength,
    'overrides': overrides.map(
      (role, color) => MapEntry(role, color.toARGB32()),
    ),
  };

  static OrionThemePreferences fromJson(Object? value) {
    if (value is! Map) return defaults;
    final rawColors = value['gradientColors'];
    final rawStops = value['gradientStops'];
    final rawOverrides = value['overrides'];
    final mode = value['themeMode'];
    final originalPreset = value['presetId'] == 'original-orion';
    final storedAccent = _readColor(value['accent']);
    // Refresh the shipped preset while retaining every manually edited look.
    // Easy/Fine edits mark a theme custom; version2 imports keep explicit colors.
    final oldOriginalAccent =
        originalPreset &&
        (value['version'] is! num || (value['version'] as num) < 2) &&
        storedAccent == const Color(0xFF8DB7FF);
    final legacyOriginal =
        !value.containsKey('basePalette') &&
        value['presetId'] == 'original-orion';
    final overrides = {
      if (rawOverrides is Map)
        for (final role in colorRoles)
          if (_readColor(rawOverrides[role]) case final Color color)
            role: color,
    };
    // Accept the unpublished first preset format without turning its authored
    // base palette into explicit manual locks on the easy controls.
    if (legacyOriginal &&
        originalPalette.entries.every(
          (entry) => overrides[entry.key] == entry.value,
        )) {
      overrides.removeWhere((role, _) => originalPalette.containsKey(role));
    }
    final preferences = OrionThemePreferences(
      presetId: value['presetId'] is String
          ? value['presetId'] as String
          : 'expressive',
      basePalette: value['basePalette'] is String
          ? value['basePalette'] as String
          : legacyOriginal
          ? 'original-orion'
          : 'expressive',
      themeMode: ThemeMode.values.firstWhere(
        (item) => item.name == mode,
        orElse: () => ThemeMode.dark,
      ),
      accent: oldOriginalAccent
          ? originalAccent
          : storedAccent ?? (originalPreset ? originalAccent : defaults.accent),
      gradientEnabled: value['gradientEnabled'] == true,
      rainEnabled: value['rainEnabled'] == true,
      liquidGlassEnabled: value['liquidGlassEnabled'] == true,
      windowOpacity: _number(value['windowOpacity'], 1),
      gradientColors: rawColors is List
          ? rawColors.take(4).map(_readColor).whereType<Color>().toList()
          : defaultGradientColors,
      gradientStops: rawStops is List && rawStops.every((stop) => stop is num)
          ? rawStops.take(4).map((stop) => (stop as num).toDouble()).toList()
          : null,
      gradientAngle: _number(value['gradientAngle'], 135),
      surfaceTint: _number(value['surfaceTint'], 0),
      outlineStrength: _number(value['outlineStrength'], 1),
      overrides: overrides,
    );
    // Refresh only exact shipped Glass looks. Every custom, Easy, light-mode,
    // opacity or color edit stays intact, including saved/imported themes.
    final unchangedGlass =
        preferences.presetId == 'liquid-glass' &&
        preferences.basePalette == 'liquid-glass' &&
        preferences.themeMode == ThemeMode.dark &&
        preferences.liquidGlassEnabled &&
        !preferences.rainEnabled &&
        preferences.gradientEnabled &&
        listEquals(preferences.gradientStops, const [0.0, .52, 1.0]) &&
        preferences.gradientAngle == 135 &&
        preferences.surfaceTint == 0 &&
        preferences.overrides.isEmpty;
    final firstGlass =
        preferences.accent == const Color(0xFFAFDFFF) &&
        preferences.windowOpacity == 1 &&
        preferences.outlineStrength == 1 &&
        listEquals(preferences.gradientColors, const [
          Color(0xFF111923),
          Color(0xFF3E596C),
          Color(0xFF17252F),
        ]);
    final secondGlass =
        preferences.accent == const Color(0xFFA1D7FF) &&
        preferences.windowOpacity == .9 &&
        preferences.outlineStrength == .65 &&
        listEquals(preferences.gradientColors, const [
          Color(0xFF181B20),
          Color(0xFF333B44),
          Color(0xFF181C22),
        ]);
    final thirdGlass =
        preferences.accent == liquidGlassAccent &&
        preferences.windowOpacity == .9 &&
        preferences.outlineStrength == .65 &&
        listEquals(preferences.gradientColors, const [
          Color(0xFF0B1017),
          Color(0xFF142333),
          Color(0xFF0A1018),
        ]);
    if (unchangedGlass && (firstGlass || secondGlass || thirdGlass)) {
      return builtInPresets[3].preferences;
    }
    for (final previousOpacity in const [.55, .70]) {
      final previousGlassy = builtInPresets[3].preferences.copyWith(
        windowOpacity: previousOpacity,
      );
      if (preferences == previousGlassy) {
        return builtInPresets[3].preferences;
      }
    }
    return preferences;
  }

  @override
  bool operator ==(Object other) =>
      other is OrionThemePreferences &&
      presetId == other.presetId &&
      basePalette == other.basePalette &&
      themeMode == other.themeMode &&
      accent == other.accent &&
      gradientEnabled == other.gradientEnabled &&
      rainEnabled == other.rainEnabled &&
      liquidGlassEnabled == other.liquidGlassEnabled &&
      windowOpacity == other.windowOpacity &&
      listEquals(gradientColors, other.gradientColors) &&
      listEquals(gradientStops, other.gradientStops) &&
      gradientAngle == other.gradientAngle &&
      surfaceTint == other.surfaceTint &&
      outlineStrength == other.outlineStrength &&
      mapEquals(overrides, other.overrides);

  @override
  int get hashCode => Object.hash(
    presetId,
    basePalette,
    themeMode,
    accent,
    gradientEnabled,
    rainEnabled,
    liquidGlassEnabled,
    windowOpacity,
    Object.hashAll(gradientColors),
    Object.hashAll(gradientStops ?? const []),
    gradientAngle,
    surfaceTint,
    outlineStrength,
    Object.hashAll(colorRoles.map((role) => overrides[role])),
  );

  static Color _opaque(Color color) => color.withValues(alpha: 1);
  static double _number(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;
  static double _bounded(
    double value,
    double min,
    double max,
    double fallback,
  ) => value.isFinite ? value.clamp(min, max) : fallback;
  static Color? _readColor(Object? value) {
    if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
      return _opaque(Color(value));
    }
    if (value is String &&
        RegExp(r'^#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
      final hex = value.replaceFirst('#', '');
      return _opaque(
        Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16)),
      );
    }
    return null;
  }
}

@immutable
class OrionThemePreset {
  const OrionThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.preferences,
  });
  final String id, name, description;
  final OrionThemePreferences preferences;
}

@immutable
class SavedOrionTheme {
  const SavedOrionTheme({
    required this.id,
    required this.name,
    required this.preferences,
  });
  final String id, name;
  final OrionThemePreferences preferences;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'preferences': preferences.toJson(),
  };
  static SavedOrionTheme? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], name = value['name'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 96 ||
        name is! String ||
        value['preferences'] is! Map) {
      return null;
    }
    final trimmed = name.trim();
    return SavedOrionTheme(
      id: id,
      name: trimmed.isEmpty
          ? 'Untitled theme'
          : trimmed.substring(0, trimmed.length.clamp(0, 80)),
      preferences: OrionThemePreferences.fromJson(value['preferences']),
    );
  }
}
