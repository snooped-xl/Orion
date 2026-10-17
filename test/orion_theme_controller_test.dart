import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/state/orion_controller.dart';

Uint8List logo() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);

void main() {
  late Directory storage;
  setUp(
    () async =>
        storage = await Directory.systemTemp.createTemp('orion-theme-core-'),
  );
  tearDown(() async => storage.delete(recursive: true));
  Future<void> close(OrionController controller) async {
    controller.dispose();
    await controller.flushPersistence();
  }

  test(
    'normal Logo control replaces Studio image and preserves layer geometry',
    () {
      final c = OrionController(persistChanges: false);
      addTearDown(c.dispose);
      c.setInterfacePreference(InterfacePreset.orion, 'themeStudio', {
        'windows': {
          'main': {
            'logo': {'data': 'old-logo'},
            'elements': {
              'logo': {
                'image': {'data': 'old-element-logo'},
                'x': 12,
                'opacity': .7,
              },
              'editor': {'fill': 0xff222333},
            },
          },
        },
      });
      c.setCustomLogo(logo());
      final doc =
          c.getInterfacePreferences(InterfacePreset.orion)['themeStudio']
              as Map;
      final main = (doc['windows'] as Map)['main'] as Map;
      expect(main.containsKey('logo'), false);
      expect((main['elements'] as Map)['logo'], {'x': 12, 'opacity': .7});
      expect((main['elements'] as Map)['editor'], {'fill': 0xff222333});
      expect(c.customLogoBytes, orderedEquals(logo()));
    },
  );
  test(
    'themes saved looks and custom logo persist independently of workspace data',
    () async {
      final first = OrionController(storageDirectory: storage);
      await first.initialize();
      final preferences = OrionThemePreferences.builtInPresets
          .singleWhere((preset) => preset.id == 'aurora')
          .preferences
          .copyWith(
            themeMode: ThemeMode.system,
            outlineStrength: 1.4,
            rainEnabled: true,
            windowOpacity: .77,
          );
      first.setOrionTheme(preferences);
      first.setCustomLogo(logo());
      final saved = first.saveOrionTheme('My aurora');
      first.updateDocumentContent(
        first.activeDocumentId,
        'print("keep this dirty")',
      );
      await close(first);

      final restored = OrionController(storageDirectory: storage);
      await restored.initialize();
      expect(restored.orionTheme, preferences);
      expect(restored.themeMode, ThemeMode.system);
      expect(restored.savedOrionThemes.single.id, saved.id);
      expect(restored.savedOrionThemes.single.preferences, preferences);
      expect(restored.customLogoBytes, orderedEquals(logo()));
      expect(restored.activeDocument.content, 'print("keep this dirty")');
      expect(restored.activeDocument.isDirty, true);
      await close(restored);
    },
  );

  test(
    'legacy explicit accent and mode migrate into the new theme without losing edits',
    () async {
      await File('${storage.path}/orion-workspace.json').writeAsString(
        jsonEncode({
          'appearanceVersion': 1,
          'themeMode': 'light',
          'accent': 'coral',
          'documents': [
            const EditorDocument(
              id: 'draft',
              name: 'draft.lua',
              content: 'dirty',
              savedContent: '',
            ).toJson(),
          ],
          'activeDocumentId': 'draft',
        }),
      );
      final controller = OrionController(storageDirectory: storage);
      await controller.initialize();
      expect(controller.orionTheme.accent, OrionAccent.coral.color);
      expect(controller.orionTheme.themeMode, ThemeMode.light);
      expect(controller.accent, OrionAccent.coral);
      expect(controller.activeDocument.content, 'dirty');
      expect(controller.activeDocument.isDirty, true);
      controller.setAccent(OrionAccent.lime);
      controller.setThemeMode(ThemeMode.system);
      expect(controller.orionTheme.accent, OrionAccent.lime.color);
      expect(controller.orionTheme.themeMode, ThemeMode.system);
      await close(controller);
    },
  );

  test(
    'reset restores only the default theme and mode while preserving independent choices',
    () async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      controller.setCustomLogo(logo());
      final beforeLogo = controller.customLogoBytes;
      controller.setUiScale(1.2);
      controller.setOrionCompactMode(true);
      controller.setReducedMotion(true);
      controller.setEditorFontSize(19);
      controller.setInterfacePreference(
        InterfacePreset.synapseX,
        'themeName',
        'source',
      );
      controller.updateDocumentContent(
        controller.activeDocumentId,
        'unsaved source',
      );
      controller.setOrionTheme(
        OrionThemePreferences.builtInPresets.last.preferences.copyWith(
          themeMode: ThemeMode.light,
        ),
      );
      final saved = controller.saveOrionTheme('Keep saved');
      controller.resetOrionTheme();
      expect(controller.orionTheme, OrionThemePreferences.defaults);
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.accent, OrionAccent.blue);
      expect(identical(controller.customLogoBytes, beforeLogo), true);
      expect(controller.uiScale, 1.2);
      expect(controller.orionCompactMode, true);
      expect(controller.reducedMotion, true);
      expect(controller.editorFontSize, 19);
      expect(
        controller.getInterfacePreferences(
          InterfacePreset.synapseX,
        )['themeName'],
        'source',
      );
      expect(controller.activeDocument.content, 'unsaved source');
      expect(controller.savedOrionThemes.single.id, saved.id);
    },
  );

  test(
    'saved themes retain complete mode and values and can be applied and deleted',
    () async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      controller.setOrionTheme(
        OrionThemePreferences(
          gradientEnabled: true,
          themeMode: ThemeMode.light,
          accent: Colors.deepPurple,
        ),
      );
      final saved = controller.saveOrionTheme('  Dawn  ');
      controller.resetOrionTheme();
      controller.applySavedOrionTheme(saved.id);
      expect(controller.themeMode, ThemeMode.light);
      expect(
        controller.orionTheme.accent.toARGB32(),
        Colors.deepPurple.toARGB32(),
      );
      expect(controller.orionTheme.gradientEnabled, true);
      expect(saved.name, 'Dawn');
      controller.deleteSavedOrionTheme(saved.id);
      expect(controller.savedOrionThemes, isEmpty);
      expect(controller.orionTheme, saved.preferences);
      for (var i = 0; i < 40; i++) {
        controller.saveOrionTheme('Look $i');
      }
      expect(controller.savedOrionThemes, hasLength(32));
      expect(() => controller.savedOrionThemes.clear(), throwsUnsupportedError);
    },
  );

  test(
    'theme import is bounded and rejects malformed inputs without changing current look',
    () async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      controller.setOrionTheme(
        OrionThemePreferences.builtInPresets.last.preferences,
      );
      final before = controller.orionTheme;
      for (final source in [
        'not json',
        '[]',
        '{}',
        '{"unrelated":1}',
        ' ' * 65537,
      ]) {
        expect(controller.importOrionTheme(source), false);
        expect(controller.orionTheme, before);
      }
      final source = controller.exportOrionTheme();
      controller.resetOrionTheme();
      expect(controller.importOrionTheme(source), true);
      expect(controller.orionTheme, before);
    },
  );

  test(
    'custom logo has stable immutable bytes and malformed replacements leave it intact',
    () async {
      final controller = OrionController(persistChanges: false);
      addTearDown(controller.dispose);
      final input = logo();
      controller.setCustomLogo(input);
      final stable = controller.customLogoBytes!;
      input[0] = 0;
      expect(stable[0], 137);
      expect(identical(stable, controller.customLogoBytes), true);
      expect(() => stable[0] = 0, throwsUnsupportedError);
      expect(
        () => controller.setCustomLogo(Uint8List.fromList([1, 2, 3])),
        throwsArgumentError,
      );
      expect(identical(stable, controller.customLogoBytes), true);
      final oversized = Uint8List(OrionController.maxCustomLogoBytes + 1);
      expect(() => controller.setCustomLogo(oversized), throwsArgumentError);
      final hugePng = logo();
      ByteData.sublistView(hugePng).setUint32(16, 100000);
      expect(() => controller.setCustomLogo(hugePng), throwsArgumentError);
      controller.setCustomLogo(null);
      expect(controller.customLogoBytes, isNull);
    },
  );

  test(
    'malformed restored themes saved lists and logo cannot prevent workspace recovery',
    () async {
      final saved = SavedOrionTheme(
        id: 'duplicate',
        name: 'Saved',
        preferences: OrionThemePreferences.defaults,
      ).toJson();
      await File('${storage.path}/orion-workspace.json').writeAsString(
        jsonEncode({
          'appearanceVersion': 1,
          'orionTheme': {
            'accent': [],
            'gradientColors': 'bad',
            'overrides': [],
          },
          'savedOrionThemes': [
            saved,
            saved,
            {'id': 'invalid'},
            null,
          ],
          'customLogo': 'not base64',
          'documents': [
            const EditorDocument(
              id: 'draft',
              name: 'draft.lua',
              content: 'recovered',
              savedContent: '',
            ).toJson(),
          ],
          'activeDocumentId': 'draft',
        }),
      );
      final controller = OrionController(storageDirectory: storage);
      await controller.initialize();
      expect(controller.activeDocument.content, 'recovered');
      expect(controller.orionTheme, OrionThemePreferences.defaults);
      expect(controller.savedOrionThemes, hasLength(1));
      expect(controller.customLogoBytes, isNull);
      await close(controller);
    },
  );

  test(
    'canonical snapshots carry themes and retain owner branding without broadcasting image bytes',
    () {
      final owner = OrionController(persistChanges: false);
      final mirror = OrionController(persistChanges: false);
      addTearDown(owner.dispose);
      addTearDown(mirror.dispose);
      owner.setOrionTheme(OrionThemePreferences.builtInPresets[1].preferences);
      owner.saveOrionTheme('Original');
      owner.setCustomLogo(logo());
      final stableLogo = owner.customLogoBytes;
      final snapshot = owner.exportWindowState();
      expect(snapshot.containsKey('customLogo'), false);
      mirror.applyWindowState(snapshot);
      expect(mirror.orionTheme, owner.orionTheme);
      expect(mirror.customLogoBytes, isNull);
      expect(mirror.savedOrionThemes.single.name, 'Original');
      owner.applyWindowState(snapshot);
      expect(identical(owner.customLogoBytes, stableLogo), true);
      mirror.resetOrionTheme();
      mirror.setCustomLogo(null);
      expect(owner.orionTheme.presetId, 'original-orion');
      expect(owner.customLogoBytes, isNotNull);
    },
  );
  test(
    'Material Rain exports imports and recovery retain effects while reset clears them',
    () async {
      final owner = OrionController(storageDirectory: storage);
      await owner.initialize();
      final rain = OrionThemePreferences.builtInPresets[2].preferences;
      owner.setOrionTheme(rain);
      owner.saveOrionTheme('Material Rain saved');
      final exported = owner.exportOrionTheme();
      final mirror = OrionController(persistChanges: false);
      mirror.applyWindowState(owner.exportWindowState());
      expect(mirror.orionTheme, rain);
      expect(mirror.orionTheme.rainEnabled, true);
      expect(mirror.orionTheme.windowOpacity, .9);
      mirror.resetOrionTheme();
      expect(mirror.orionTheme.rainEnabled, false);
      expect(mirror.orionTheme.windowOpacity, 1);
      expect(mirror.importOrionTheme(exported), true);
      expect(mirror.orionTheme, rain);
      mirror.dispose();
      await close(owner);
      final restored = OrionController(storageDirectory: storage);
      await restored.initialize();
      expect(restored.orionTheme, rain);
      expect(restored.savedOrionThemes.single.preferences, rain);
      await close(restored);
    },
  );
}
