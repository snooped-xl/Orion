import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_models.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

void main() {
  late Directory storage;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('orion-appearance-');
  });

  tearDown(() async {
    await storage.delete(recursive: true);
  });

  Future<OrionController> restore(Map<String, Object?> state) async {
    await File(
      '${storage.path}/orion-workspace.json',
    ).writeAsString(jsonEncode(state));
    final controller = OrionController(storageDirectory: storage);
    await controller.initialize();
    return controller;
  }

  Future<void> close(OrionController controller) async {
    controller.dispose();
    await controller.flushPersistence();
  }

  test('a fresh workspace defaults to the new dark blue appearance', () async {
    final controller = OrionController(storageDirectory: storage);
    await controller.initialize();
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.accent, OrionAccent.blue);
    expect(controller.accentColor, const Color(0xFF88B5FF));
    await close(controller);
  });

  test('the old lime default migrates once without losing documents', () async {
    final controller = await restore({
      'version': 2,
      'accent': 'lime',
      'documents': [
        const EditorDocument(
          id: 'kept',
          name: 'saved.luau',
          content: 'print("unsaved")',
          savedContent: 'print("saved")',
        ).toJson(),
      ],
      'activeDocumentId': 'kept',
    });
    expect(controller.accent, OrionAccent.blue);
    expect(controller.activeDocument.content, 'print("unsaved")');
    expect(controller.activeDocument.isDirty, isTrue);
    await controller.flushPersistence();
    final state =
        jsonDecode(
              await File('${storage.path}/orion-workspace.json').readAsString(),
            )
            as Map<String, dynamic>;
    expect(state['appearanceVersion'], 1);
    expect(state['accent'], 'blue');

    controller.setAccent(OrionAccent.lime);
    await close(controller);
    final restored = OrionController(storageDirectory: storage);
    await restored.initialize();
    expect(restored.accent, OrionAccent.lime);
    expect(restored.activeDocument.id, 'kept');
    await close(restored);
  });

  for (final accent in [OrionAccent.lavender, OrionAccent.coral]) {
    test(
      'preserves a saved ${accent.name} preference during migration',
      () async {
        final controller = await restore({'accent': accent.name});
        expect(controller.accent, accent);
        await close(controller);
      },
    );
  }

  test('unknown saved accent falls back to blue', () async {
    final controller = await restore({'accent': 'retired-color'});
    expect(controller.accent, OrionAccent.blue);
    await close(controller);
  });

  test('dark surfaces stay distinct and filled actions have blue ink', () {
    final theme = orionTheme(Brightness.dark, OrionAccent.blue.color);
    final colors = theme.extension<OrionColors>()!;
    expect(colors.background, const Color(0xFF11151B));
    expect(colors.panel, const Color(0xFF181E27));
    expect(colors.elevated, const Color(0xFF222B37));
    expect(colors.background, isNot(Colors.black));
    expect(
      colors.background.computeLuminance(),
      lessThan(colors.panel.computeLuminance()),
    );
    expect(
      colors.panel.computeLuminance(),
      lessThan(colors.elevated.computeLuminance()),
    );
    expect(theme.colorScheme.onPrimary, const Color(0xFF092C57));
    expect(
      theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
      const Color(0xFF092C57),
    );
  });

  test('every accent keeps readable actions and text in both themes', () {
    for (final brightness in Brightness.values) {
      for (final accent in OrionAccent.values) {
        final theme = orionTheme(brightness, accent.color);
        final colors = theme.extension<OrionColors>()!;
        expect(
          _contrast(colors.accent, colors.onAccent),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} ${accent.name} filled action',
        );
        expect(
          _contrast(colors.panel, colors.readableAccent),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} ${accent.name} accent text',
        );
        expect(
          _contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} ${accent.name} primary scheme',
        );
        expect(
          _contrast(colors.panel, colors.muted),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} secondary text',
        );
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}
