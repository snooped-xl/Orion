import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/theme/orion_surfaces.dart';

double contrast(Color a, Color b) =>
    (math.max(a.computeLuminance(), b.computeLuminance()) + .05) /
    (math.min(a.computeLuminance(), b.computeLuminance()) + .05);

void main() {
  test(
    'theme collections are immutable and normalized independently of inputs',
    () {
      final stops = [0.0, 1.0];
      final colors = [Colors.blue, Colors.teal];
      final overrides = {'panel': Colors.black};
      final preferences = OrionThemePreferences(
        gradientColors: colors,
        gradientStops: stops,
        overrides: overrides,
        gradientAngle: -450,
      );
      colors[0] = Colors.red;
      stops[1] = .4;
      overrides['panel'] = Colors.white;
      expect(
        preferences.gradientColors.first.toARGB32(),
        Colors.blue.toARGB32(),
      );
      expect(preferences.gradientStops, [0, 1]);
      expect(preferences.overrides['panel'], Colors.black);
      expect(preferences.gradientAngle, 270);
      expect(
        () => preferences.gradientColors.add(Colors.red),
        throwsUnsupportedError,
      );
      expect(
        () => preferences.overrides['panel'] = Colors.red,
        throwsUnsupportedError,
      );
      expect(() => preferences.gradientStops![0] = .2, throwsUnsupportedError);
    },
  );

  test('complete themes survive JSON and the native untyped map codec', () {
    final preferences = OrionThemePreferences(
      presetId: 'custom',
      basePalette: 'original-orion',
      themeMode: ThemeMode.system,
      accent: const Color(0xFF55DDAA),
      gradientEnabled: true,
      gradientColors: const [
        Color(0xFF142532),
        Color(0xFF212D19),
        Color(0xFF303125),
      ],
      gradientStops: const [0, .4, 1],
      gradientAngle: 280,
      surfaceTint: .6,
      outlineStrength: 1.4,
      overrides: {
        for (final role in OrionThemePreferences.colorRoles)
          role: const Color(0xFF123456),
      },
    );
    const codec = StandardMessageCodec();
    expect(
      OrionThemePreferences.fromJson(
        jsonDecode(jsonEncode(preferences.toJson())),
      ),
      preferences,
    );
    expect(
      OrionThemePreferences.fromJson(
        codec.decodeMessage(codec.encodeMessage(preferences.toJson())),
      ),
      preferences,
    );
    final saved = SavedOrionTheme(
      id: 'one',
      name: 'My theme',
      preferences: preferences,
    );
    expect(
      SavedOrionTheme.fromJson(
        jsonDecode(jsonEncode(saved.toJson())),
      )!.preferences,
      preferences,
    );
  });

  test('malformed and out-of-range theme data is bounded without throwing', () {
    final preferences = OrionThemePreferences.fromJson({
      'presetId': '',
      'themeMode': 'invalid',
      'accent': 'url(script)',
      'gradientEnabled': 'true',
      'gradientColors': ['#123456', 'not-color', -1, 0x100000000],
      'gradientStops': [double.nan, double.infinity],
      'gradientAngle': double.infinity,
      'surfaceTint': 8,
      'outlineStrength': -4,
      'overrides': {
        'panel': '#112233',
        'editor': '#80112233',
        'ink': {},
        'unknown': '#abcdef',
      },
    });
    expect(preferences.presetId, 'custom');
    expect(preferences.themeMode, ThemeMode.dark);
    expect(preferences.accent, OrionThemePreferences.defaults.accent);
    expect(preferences.gradientEnabled, false);
    expect(
      preferences.gradientColors,
      OrionThemePreferences.defaultGradientColors,
    );
    expect(preferences.gradientStops, isNull);
    expect(preferences.gradientAngle, 135);
    expect(preferences.surfaceTint, 1);
    expect(preferences.outlineStrength, 0);
    expect(preferences.overrides, {
      'panel': const Color(0xFF112233),
      'editor': const Color(0xFF112233),
    });
    expect(OrionThemePreferences.fromJson([]), OrionThemePreferences.defaults);
    expect(SavedOrionTheme.fromJson({'id': '', 'name': 'bad'}), isNull);
    expect(
      OrionThemePreferences(
        gradientColors: List.filled(20, Colors.red),
      ).gradientColors,
      hasLength(4),
    );
    expect(
      OrionThemePreferences(gradientStops: const [.9, .2]).gradientStops,
      isNull,
    );
  });

  test(
    'default preferences leave the existing dark and light palettes exact',
    () {
      for (final brightness in Brightness.values) {
        final old = orionTheme(
          brightness,
          OrionThemePreferences.defaults.accent,
        ).extension<OrionColors>()!;
        final current = orionTheme(
          brightness,
          Colors.red,
          preferences: OrionThemePreferences.defaults,
        ).extension<OrionColors>()!;
        expect(current.background, old.background);
        expect(current.panel, old.panel);
        expect(current.elevated, old.elevated);
        expect(current.border, old.border);
        expect(current.ink, old.ink);
        expect(current.muted, old.muted);
        expect(current.accent, old.accent);
        expect(current.editorColor, old.panel);
        expect(current.backgroundGradient, isNull);
        expect(current.outline(.18), old.border.withValues(alpha: .18));
      }
    },
  );

  test(
    'Original Orion uses the authoritative source palette and early gradient stop',
    () {
      final original = OrionThemePreferences.builtInPresets.singleWhere(
        (preset) => preset.id == 'original-orion',
      );
      expect(original.preferences.accent, OrionThemePreferences.originalAccent);
      expect(original.preferences.basePalette, 'original-orion');
      expect(original.preferences.overrides, isEmpty);
      expect(original.preferences.gradientColors, const [
        Color(0xFF181A1B),
        Color(0xFF08090A),
      ]);
      expect(original.preferences.gradientStops, [0, .37019]);
      expect(original.preferences.outlineStrength, 1.5);
      final colors = orionTheme(
        Brightness.dark,
        Colors.red,
        preferences: original.preferences,
      ).extension<OrionColors>()!;
      expect(
        colors.backgroundGradient!.colors,
        original.preferences.gradientColors,
      );
      expect(colors.backgroundGradient!.stops, [0, .37019]);
      expect(colors.panel, const Color(0xFF07080A));
      expect(colors.elevated, const Color(0xFF111315));
      expect(colors.border, const Color(0xFF303235));
      expect(colors.editorColor, const Color(0xFF101112));
      expect(colors.ink, Colors.white);
    },
  );

  test(
    'Original easy edits retain the authored base and tint surfaces without manual locks',
    () {
      final original = OrionThemePreferences.builtInPresets
          .singleWhere((preset) => preset.id == 'original-orion')
          .preferences;
      final edited = original.copyWith(presetId: 'custom', surfaceTint: .6);
      expect(edited.basePalette, 'original-orion');
      expect(edited.overrides.containsKey('editor'), false);
      expect(OrionThemePreferences.fromJson(edited.toJson()), edited);
      final base = orionTheme(
        Brightness.dark,
        Colors.blue,
        preferences: original,
      ).extension<OrionColors>()!;
      final tinted = orionTheme(
        Brightness.dark,
        Colors.blue,
        preferences: edited,
      ).extension<OrionColors>()!;
      expect(tinted.panel, isNot(base.panel));
      expect(tinted.elevated, isNot(base.elevated));
      expect(tinted.editorColor, isNot(base.editorColor));
      final manual = orionTheme(
        Brightness.dark,
        Colors.blue,
        preferences: edited.copyWith(
          overrides: const {
            'panel': Color(0xFF242526),
            'editor': Color(0xFF121314),
          },
        ),
      ).extension<OrionColors>()!;
      expect(manual.panel, const Color(0xFF242526));
      expect(manual.editorColor, const Color(0xFF121314));
      final light = orionTheme(
        Brightness.light,
        Colors.blue,
        preferences: original,
      ).extension<OrionColors>()!;
      final customLight = orionTheme(
        Brightness.light,
        Colors.blue,
        preferences: original.copyWith(presetId: 'custom'),
      ).extension<OrionColors>()!;
      expect(customLight.panel, light.panel);
      expect(customLight.editorColor, light.editorColor);
      expect(customLight.backgroundGradient, light.backgroundGradient);
      expect(customLight.panel.computeLuminance(), greaterThan(.5));
      expect(customLight.editorColor.computeLuminance(), greaterThan(.5));
    },
  );

  test(
    'unpublished Original authored override format migrates into its base palette',
    () {
      final legacy = {
        ...OrionThemePreferences.defaults.toJson(),
        'presetId': 'original-orion',
        'overrides': OrionThemePreferences.originalPalette.map(
          (key, value) => MapEntry(key, value.toARGB32()),
        ),
      }..remove('basePalette');
      final preferences = OrionThemePreferences.fromJson(legacy);
      expect(preferences.basePalette, 'original-orion');
      expect(preferences.overrides, isEmpty);
      expect(
        OrionThemePreferences(basePalette: 'unknown').basePalette,
        'expressive',
      );
    },
  );

  test(
    'all curated looks retain readable text and actions in dark and light modes',
    () {
      for (final preset in OrionThemePreferences.builtInPresets) {
        for (final brightness in Brightness.values) {
          final theme = orionTheme(
            brightness,
            Colors.red,
            preferences: preset.preferences,
          );
          final colors = theme.extension<OrionColors>()!;
          expect(
            colors.background.computeLuminance(),
            brightness == Brightness.dark ? lessThan(.12) : greaterThan(.5),
            reason: '${preset.id} ${brightness.name} background',
          );
          for (final surface in [
            colors.background,
            colors.panel,
            colors.elevated,
            colors.editorColor,
            ...?colors.backgroundGradient?.colors,
          ]) {
            expect(
              contrast(colors.ink, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${preset.id} ${brightness.name} ink',
            );
            expect(
              contrast(colors.muted, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${preset.id} ${brightness.name} muted',
            );
          }
          expect(
            contrast(colors.accent, colors.onAccent),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  test(
    'bright gradient choices become readable tonal stops without changing saved choices',
    () {
      final preferences = OrionThemePreferences(
        presetId: 'custom',
        gradientEnabled: true,
        gradientColors: const [
          Colors.white,
          Colors.greenAccent,
          Colors.yellowAccent,
        ],
      );
      for (final brightness in Brightness.values) {
        final colors = orionTheme(
          brightness,
          Colors.red,
          preferences: preferences,
        ).extension<OrionColors>()!;
        for (final stop in colors.backgroundGradient!.colors) {
          expect(
            stop.computeLuminance(),
            brightness == Brightness.dark
                ? lessThanOrEqualTo(.120001)
                : greaterThanOrEqualTo(.719999),
          );
          expect(contrast(colors.ink, stop), greaterThanOrEqualTo(4.5));
        }
      }
      expect(preferences.gradientColors.map((color) => color.toARGB32()), [
        Colors.white.toARGB32(),
        Colors.greenAccent.toARGB32(),
        Colors.yellowAccent.toARGB32(),
      ]);
    },
  );

  test(
    'explicit surface and editor overrides win over tint while text stays readable',
    () {
      final preferences = OrionThemePreferences(
        presetId: 'custom',
        accent: Colors.red,
        surfaceTint: 1,
        overrides: const {
          'panel': Color(0xFF202020),
          'elevated': Color(0xFF303030),
          'editor': Color(0xFF101010),
          'ink': Color(0xFF101010),
          'muted': Color(0xFF101010),
        },
      );
      final colors = orionTheme(
        Brightness.dark,
        Colors.blue,
        preferences: preferences,
      ).extension<OrionColors>()!;
      expect(colors.panel, const Color(0xFF202020));
      expect(colors.elevated, const Color(0xFF303030));
      expect(colors.editorColor, const Color(0xFF101010));
      expect(contrast(colors.ink, colors.panel), greaterThanOrEqualTo(4.5));
      expect(
        contrast(colors.muted, colors.elevated),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.accent, colors.onAccent),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  test('outline controls and animated gradient fields interpolate safely', () {
    final first = orionTheme(
      Brightness.dark,
      Colors.blue,
      preferences: OrionThemePreferences(outlineStrength: 0),
    ).extension<OrionColors>()!;
    final second = orionTheme(
      Brightness.dark,
      Colors.blue,
      preferences: OrionThemePreferences(
        gradientEnabled: true,
        outlineStrength: 2,
      ),
    ).extension<OrionColors>()!;
    expect(first.outline().a, 0);
    expect(second.outline(.8).a, 1);
    final halfway = first.lerp(second, .5);
    expect(halfway.outlineStrength, 1);
    expect(halfway.backgroundGradient, isNotNull);
    expect(halfway.editorColor, first.editorColor);
    expect(second.outline(double.nan).a, 0);
  });
  test(
    'Material Rain is the third default with black surfaces and blue white-label actions',
    () {
      expect(OrionThemePreferences.builtInPresets.take(3).map((p) => p.id), [
        'expressive',
        'original-orion',
        'material-rain',
      ]);
      final rain = OrionThemePreferences.builtInPresets[2].preferences;
      expect(rain.presetId, 'material-rain');
      expect(rain.basePalette, 'material-rain');
      expect(rain.rainEnabled, true);
      expect(rain.windowOpacity, .9);
      expect(rain.gradientEnabled, false);
      expect(rain.overrides, isEmpty);
      final theme = orionTheme(Brightness.dark, Colors.red, preferences: rain);
      final colors = theme.extension<OrionColors>()!;
      expect(colors.background, Colors.black);
      expect(colors.editorColor, Colors.black);
      expect(colors.panel, const Color(0xFF050505));
      expect(colors.elevated, const Color(0xFF101113));
      expect(colors.border, const Color(0xFF343638));
      expect(colors.accent, const Color(0xFF164A80));
      expect(colors.onAccent, Colors.white);
      expect(theme.colorScheme.primary, colors.accent);
      expect(theme.colorScheme.onPrimary, Colors.white);
      expect(colors.backgroundGradient, isNull);
      expect(orionSurfaceGradient(colors), isNull);
      expect(colors.transparentSurfaces, false);
      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
        colors.accent,
      );
      expect(
        theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
        Colors.white,
      );
      expect(contrast(colors.ink, colors.elevated), greaterThanOrEqualTo(4.5));
      expect(
        contrast(colors.muted, colors.elevated),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.readableAccent, colors.panel),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  test(
    'rain and window opacity survive easy and fine edits, named themes and JSON',
    () {
      final rain = OrionThemePreferences.builtInPresets[2].preferences;
      final edited = rain.copyWith(
        presetId: 'custom',
        accent: Colors.teal,
        surfaceTint: .4,
        overrides: {'panel': const Color(0xFF101010)},
      );
      expect(edited.rainEnabled, true);
      expect(edited.windowOpacity, .9);
      expect(edited.basePalette, 'material-rain');
      expect(
        OrionThemePreferences.fromJson(jsonDecode(jsonEncode(edited.toJson()))),
        edited,
      );
      final saved = SavedOrionTheme(
        id: 'rain-copy',
        name: 'Rain custom',
        preferences: edited,
      );
      expect(
        SavedOrionTheme.fromJson(
          jsonDecode(jsonEncode(saved.toJson())),
        )!.preferences,
        edited,
      );
      final withoutRain = edited.copyWith(rainEnabled: false, windowOpacity: 1);
      expect(withoutRain.rainEnabled, false);
      expect(withoutRain.windowOpacity, 1);
      expect(withoutRain, isNot(edited));
      expect(withoutRain.hashCode, isNot(edited.hashCode));
      expect(edited.copyWith(), edited);
    },
  );

  test(
    'old themes default to no effects and malformed opacity stays finite and visible',
    () {
      final migrated = OrionThemePreferences.fromJson({'presetId': 'custom'});
      expect(migrated.rainEnabled, false);
      expect(migrated.windowOpacity, 1);
      final malformed = OrionThemePreferences.fromJson({
        'rainEnabled': 'true',
        'windowOpacity': double.nan,
      });
      expect(malformed.rainEnabled, false);
      expect(malformed.windowOpacity, 1);
      expect(
        OrionThemePreferences(windowOpacity: double.infinity).windowOpacity,
        1,
      );
      expect(OrionThemePreferences(windowOpacity: -1).windowOpacity, .5);
      expect(
        OrionThemePreferences.fromJson({'windowOpacity': 50}).windowOpacity,
        1,
      );
      expect(
        OrionThemePreferences.fromJson({
          'rainEnabled': true,
          'windowOpacity': .73,
        }).windowOpacity,
        .73,
      );
      for (final preset in OrionThemePreferences.builtInPresets.where(
        (p) => p.id != 'material-rain',
      )) {
        expect(preset.preferences.rainEnabled, false, reason: preset.id);
        expect(
          preset.preferences.windowOpacity,
          {'liquid-glass', 'blue-glass'}.contains(preset.id) ? .63 : 1,
          reason: preset.id,
        );
      }
      expect(OrionThemePreferences.defaults.rainEnabled, false);
      expect(OrionThemePreferences.defaults.windowOpacity, 1);
    },
  );

  test(
    'custom Material Rain keeps its neutral base with exact manual overrides',
    () {
      final rain = OrionThemePreferences.builtInPresets[2].preferences;
      final edited = rain.copyWith(
        presetId: 'custom',
        outlineStrength: 1.2,
        overrides: {'panel': const Color(0xFF121212)},
      );
      final colors = orionTheme(
        Brightness.dark,
        Colors.red,
        preferences: edited,
      ).extension<OrionColors>()!;
      expect(colors.background, Colors.black);
      expect(colors.panel, const Color(0xFF121212));
      expect(colors.editorColor, Colors.black);
      expect(colors.accent, OrionThemePreferences.materialRainAccent);
      expect(colors.backgroundGradient, isNull);
    },
  );
}
