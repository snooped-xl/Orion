import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

// The authored look captured from Orion's active theme when Blue Glass was
// requested. Keep its exact values, rather than approximating its gradient.
const _currentLook = <String, Object?>{
  'version': 2,
  'presetId': 'custom',
  'basePalette': 'liquid-glass',
  'themeMode': 'dark',
  'accent': 4284657919,
  'gradientEnabled': true,
  'rainEnabled': false,
  'liquidGlassEnabled': true,
  'windowOpacity': 0.63,
  'gradientColors': [4278212525, 4282995294],
  'gradientAngle': 41.48092830882346,
  'surfaceTint': 0.15541865620736706,
  'outlineStrength': 0.65,
  'overrides': <String, int>{},
};

OrionThemePreferences get _blueGlass => OrionThemePreferences.builtInPresets
    .singleWhere((preset) => preset.id == 'blue-glass')
    .preferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Blue Glass is the fifth primary preset with the exact current look',
    () {
      expect(
        OrionThemePreferences.builtInPresets
            .take(OrionThemePreferences.primaryPresetCount)
            .map((preset) => preset.id),
        [
          'expressive',
          'original-orion',
          'material-rain',
          'liquid-glass',
          'blue-glass',
        ],
      );
      expect(OrionThemePreferences.builtInPresets[3].name, 'Glassy');
      expect(OrionThemePreferences.builtInPresets[4].name, 'Blue Glass');
      expect(_blueGlass.toJson(), {..._currentLook, 'presetId': 'blue-glass'});
      expect(OrionThemePreferences.defaults.presetId, 'expressive');
      expect(
        OrionThemePreferences.builtInPresets.first.preferences,
        OrionThemePreferences.defaults,
      );
    },
  );

  test('naming the preset changes none of its resolved glass rendering', () {
    final before = OrionThemePreferences.fromJson(_currentLook);
    for (final brightness in Brightness.values) {
      final old = orionTheme(brightness, before.accent, preferences: before);
      final next = orionTheme(
        brightness,
        _blueGlass.accent,
        preferences: _blueGlass,
      );
      expect(next.colorScheme, old.colorScheme);
      final previousColors = old.extension<OrionColors>()!;
      final nextColors = next.extension<OrionColors>()!;
      expect(nextColors.backgroundGradient, previousColors.backgroundGradient);
      expect(nextColors.surfaceTint, previousColors.surfaceTint);
      expect(nextColors.outlineStrength, previousColors.outlineStrength);
      expect(
        nextColors.transparentSurfaces,
        previousColors.transparentSurfaces,
      );
      expect(nextColors.glassEnabled, previousColors.glassEnabled);
      expect(nextColors.opaqueSurfaceRoles, previousColors.opaqueSurfaceRoles);
      expect(
        SynapseThemeCatalog.orionPalette(_blueGlass, brightness: brightness),
        SynapseThemeCatalog.orionPalette(before, brightness: brightness),
      );
    }
    // An existing manually edited look keeps its identity on ordinary restore.
    expect(before.presetId, 'custom');
    expect(before.toJson(), _currentLook);
  });

  test(
    'Blue Glass keeps gradients and optics in JSON and Studio documents',
    () {
      final c = OrionController(persistChanges: false)
        ..setOrionTheme(_blueGlass);
      addTearDown(c.dispose);
      expect(
        OrionThemePreferences.fromJson(
          jsonDecode(jsonEncode(_blueGlass.toJson())),
        ),
        _blueGlass,
      );
      final studio = SynapseThemeCatalog.current(c, InterfacePreset.orion);
      final restored = SynapseStudioTheme.decode(studio.encode());
      expect(restored.orionTheme, _blueGlass);
      expect(
        SynapseThemeCatalog.orionPreferencesForTheme(restored),
        _blueGlass,
      );
      final saved = c.saveOrionTheme('Blue Glass saved');
      c.resetOrionTheme();
      c.applySavedOrionTheme(saved.id);
      expect(c.orionTheme, _blueGlass);
      final exported = c.exportOrionTheme();
      c.resetOrionTheme();
      expect(c.importOrionTheme(exported), true);
      expect(c.orionTheme, _blueGlass);
    },
  );

  test(
    'first launch and old default profiles still open Orion Expressive',
    () async {
      final storage = await Directory.systemTemp.createTemp(
        'orion-blue-default-',
      );
      addTearDown(() => storage.delete(recursive: true));
      Future<void> checkDefault() async {
        final c = OrionController(storageDirectory: storage);
        await c.initialize();
        expect(c.orionTheme, OrionThemePreferences.defaults);
        expect(c.themeMode, ThemeMode.dark);
        c.dispose();
        await c.flushPersistence();
      }

      await checkDefault();
      await File('${storage.path}/orion-workspace.json').writeAsString(
        jsonEncode({
          'appearanceVersion': 1,
          'themeMode': 'dark',
          'accent': 'blue',
        }),
      );
      await checkDefault();
    },
  );

  test(
    'saved Blue Glass persists while reset always returns Expressive',
    () async {
      final storage = await Directory.systemTemp.createTemp('orion-blue-save-');
      addTearDown(() => storage.delete(recursive: true));
      final first = OrionController(storageDirectory: storage);
      await first.initialize();
      first.setOrionTheme(_blueGlass);
      first.saveOrionTheme('Keep Blue Glass');
      first.dispose();
      await first.flushPersistence();
      final restored = OrionController(storageDirectory: storage);
      await restored.initialize();
      expect(restored.orionTheme, _blueGlass);
      expect(restored.savedOrionThemes.single.preferences, _blueGlass);
      restored.resetOrionTheme();
      expect(restored.orionTheme, OrionThemePreferences.defaults);
      expect(restored.orionTheme.liquidGlassEnabled, false);
      expect(restored.orionTheme.gradientEnabled, false);
      restored.dispose();
      await restored.flushPersistence();
    },
  );
}
