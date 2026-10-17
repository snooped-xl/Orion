import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_density.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in const [
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Regular.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Medium.ttf'),
      ('RobotoFlex', 'assets/fonts/RobotoFlex-Semibold.ttf'),
      ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });

  test(
    'compact preference survives recovery independently of other UIs',
    () async {
      final directory = Directory.systemTemp.createTempSync('orion-compact-');
      final original = OrionController(storageDirectory: directory);
      OrionController? restored;
      OrionController? reopened;
      try {
        await original.initialize();
        expect(original.orionCompactMode, isFalse);
        original.setUiScale(1.2);
        original.setEditorFontSize(18);
        original.setInterfacePreference(InterfacePreset.synapseBlue, 'theme', {
          'accent': 0xff2277ff,
        });
        original.setOrionCompactMode(true);
        original.updateDocumentContent(
          original.activeDocumentId,
          'print("draft")',
        );
        final activeId = original.activeDocumentId;
        original.newDocument(name: 'second.luau', content: 'print("second")');
        original.selectDocument(activeId);
        original.setInterface(InterfacePreset.synapseBlue);
        await original.flushPersistence();

        restored = OrionController(storageDirectory: directory);
        await restored.initialize();
        expect(restored.orionCompactMode, isTrue);
        expect(restored.selectedInterface, InterfacePreset.synapseBlue);
        expect(restored.uiScale, 1.2);
        expect(restored.editorFontSize, 18);
        expect(restored.documents, hasLength(2));
        expect(restored.activeDocumentId, activeId);
        expect(restored.activeDocument.content, 'print("draft")');
        expect(restored.activeDocument.isDirty, isTrue);
        expect(
          restored.getInterfacePreferences(
            InterfacePreset.synapseBlue,
          )['theme'],
          {'accent': 0xff2277ff},
        );
        expect(
          InterfaceWindowProfile.forInterface(
            restored,
            InterfacePreset.synapseBlue,
            coldStart: true,
          ).size,
          const Size(290, 355),
        );

        restored.setInterface(InterfacePreset.orion);
        expect(
          InterfaceWindowProfile.forInterface(
            restored,
            InterfacePreset.orion,
            coldStart: true,
          ).size,
          InterfaceWindowProfile.orionCompactSize,
        );
        restored.setOrionCompactMode(false);
        await restored.flushPersistence();
        reopened = OrionController(storageDirectory: directory);
        await reopened.initialize();
        expect(reopened.orionCompactMode, isFalse);
        expect(reopened.activeDocument.content, 'print("draft")');
        expect(reopened.uiScale, 1.2);
        expect(reopened.editorFontSize, 18);
      } finally {
        original.dispose();
        await original.flushPersistence();
        restored?.dispose();
        await restored?.flushPersistence();
        reopened?.dispose();
        await reopened?.flushPersistence();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'density changes only Orion window profiles, including cold starts',
    () async {
      final controller = _MemoryController();
      try {
        final legacy = InterfacePresetDetails.available.where(
          (preset) => preset != InterfacePreset.orion,
        );
        final profiles = {
          for (final preset in legacy)
            for (final coldStart in [false, true])
              (preset, coldStart): _profile(
                InterfaceWindowProfile.forInterface(
                  controller,
                  preset,
                  coldStart: coldStart,
                ),
              ),
        };
        for (final compact in [true, false, true]) {
          controller.setOrionCompactMode(compact);
          for (final coldStart in [false, true]) {
            final orion = InterfaceWindowProfile.forInterface(
              controller,
              InterfacePreset.orion,
              coldStart: coldStart,
            );
            expect(
              orion.size,
              compact ? const Size(740, 470) : const Size(822, 523),
            );
            expect(
              orion.minimumSize,
              compact ? const Size(680, 420) : const Size(720, 480),
            );
            expect(orion.resizable, isTrue);
            expect(orion.alwaysOnTop, isFalse);
            for (final preset in legacy) {
              expect(
                _profile(
                  InterfaceWindowProfile.forInterface(
                    controller,
                    preset,
                    coldStart: coldStart,
                  ),
                ),
                profiles[(preset, coldStart)],
                reason: '${preset.name}, cold start: $coldStart',
              );
            }
          }
        }
      } finally {
        controller.dispose();
      }
    },
  );

  test('custom windows compact proportionally within the compact minimum', () {
    for (final (normal, expected) in const [
      (Size(822, 523), Size(740, 470)),
      (Size(720, 480), Size(680, 431)),
      (Size(960, 640), Size(864, 575)),
    ]) {
      final compact = InterfaceWindowProfile.compactOrionSizeFor(normal);
      expect(compact, expected, reason: 'Normal window $normal');
      expect(compact.width, lessThan(normal.width));
      expect(compact.height, lessThan(normal.height));
      expect(
        compact.width,
        greaterThanOrEqualTo(
          InterfaceWindowProfile.orionCompactMinimumSize.width,
        ),
      );
      expect(
        compact.height,
        greaterThanOrEqualTo(
          InterfaceWindowProfile.orionCompactMinimumSize.height,
        ),
      );
    }
  });

  for (final scale in [.8, 1.0, 1.25]) {
    testWidgets(
      'Settings owns compact mode and retains drafts at GUI scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(822, 523);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _MemoryController()
          ..setReducedMotion(true)
          ..setUiScale(scale)
          ..setEditorFontSize(18)
          ..completeIntro();
        final draftId = controller.activeDocumentId;
        controller.renameDocument(draftId, 'draft.luau');
        controller.newDocument(name: 'second.luau', content: 'print("second")');
        controller.selectDocument(draftId);
        const draft = 'local retained = "compact mode"\nprint(retained)';
        final editor = find.byKey(const ValueKey('code-editor'));
        final settings = find.byTooltip('Settings');
        final compactLabel = find.text('Compact mode');
        try {
          await tester.pumpWidget(
            OrionApp(controller: controller, nativeWindow: false),
          );
          await _settle(tester);
          _expectNoHeaderCompactControl();
          await tester.enterText(editor, draft);
          await _settle(tester);
          await tester.tap(settings);
          await _settle(tester);
          await _showWindowControls(tester);
          await tester.ensureVisible(compactLabel);
          await _settle(tester);
          expect(tester.widget<Switch>(_compactSwitch()).value, isFalse);
          await tester.tap(compactLabel);
          await _settle(tester);
          expect(controller.orionCompactMode, isTrue);
          expect(tester.widget<Switch>(_compactSwitch()).value, isTrue);
          _expectNoHeaderCompactControl();

          // Native window bounds are exercised by the morph service tests. Match
          // its completed compact viewport here to check the full Flutter shell.
          tester.view.physicalSize = const Size(740, 470);
          await _settle(tester);
          expect(_density(tester, settings).amount, closeTo(1, .001));
          await _showWindowControls(tester);
          await tester.ensureVisible(compactLabel);
          await _settle(tester);
          await tester.tap(_compactSwitch());
          await _settle(tester);
          expect(controller.orionCompactMode, isFalse);
          expect(tester.widget<Switch>(_compactSwitch()).value, isFalse);
          expect(_density(tester, settings).amount, closeTo(0, .001));
          _expectNoHeaderCompactControl();

          tester.view.physicalSize = const Size(822, 523);
          await _settle(tester);
          for (final destination in ['Scripts', 'UI Selection', 'Editor']) {
            await tester.tap(find.byTooltip(destination));
            await _settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '$destination at $scale',
            );
          }
          expect(controller.documents, hasLength(2));
          expect(controller.activeDocumentId, draftId);
          expect(controller.activeDocument.isDirty, isTrue);
          expect(tester.widget<TextField>(editor).controller!.text, draft);
          expect(controller.uiScale, scale);
          expect(controller.editorFontSize, 18);

          await tester.tap(settings);
          await _settle(tester);
          await _showWindowControls(tester);
          await tester.ensureVisible(compactLabel);
          await _settle(tester);
          await tester.tap(_compactSwitch());
          await _settle(tester);
          await tester.tap(find.byTooltip('Editor'));
          await _settle(tester);
          await tester.tap(settings);
          await _settle(tester);
          await _showWindowControls(tester);
          await tester.ensureVisible(compactLabel);
          await _settle(tester);
          expect(tester.widget<Switch>(_compactSwitch()).value, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'rapid animated density changes preserve the editor and page state',
    (tester) async {
      tester.view.physicalSize = const Size(822, 523);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _MemoryController()..completeIntro();
      final editor = find.byKey(const ValueKey('code-editor'));
      final settings = find.byTooltip('Settings');
      const draft = 'print("survives interrupted animations")';
      try {
        await tester.pumpWidget(
          OrionApp(controller: controller, nativeWindow: false),
        );
        await _settle(tester);
        await tester.enterText(editor, draft);
        await _settle(tester);
        await tester.tap(settings);
        await _settle(tester);
        await _showWindowControls(tester);
        await tester.ensureVisible(find.text('Compact mode'));
        await _settle(tester);
        _expectNoHeaderCompactControl();
        await tester.tap(_compactSwitch());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(_density(tester, settings).amount, greaterThan(0));
        expect(_density(tester, settings).amount, lessThan(1));
        await tester.tap(_compactSwitch());
        await tester.pump(const Duration(milliseconds: 30));
        await tester.tap(_compactSwitch());
        await tester.pump(const Duration(milliseconds: 30));
        expect(controller.orionCompactMode, isTrue);
        await tester.tap(find.byTooltip('Editor'));
        await _settle(tester);
        expect(_density(tester, settings).amount, closeTo(1, .001));
        expect(tester.widget<TextField>(editor).controller!.text, draft);
        expect(controller.activeDocument.content, draft);
        expect(controller.activeDocument.isDirty, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}

(Size, Size, bool, bool) _profile(InterfaceWindowProfile profile) =>
    (profile.size, profile.minimumSize, profile.resizable, profile.alwaysOnTop);

OrionDensity _density(WidgetTester tester, Finder finder) =>
    OrionDensity.of(tester.element(finder));

Finder _compactSwitch() => find.descendant(
  of: find
      .ancestor(of: find.text('Compact mode'), matching: find.byType(Row))
      .first,
  matching: find.byType(Switch),
);

void _expectNoHeaderCompactControl() {
  expect(find.byKey(const ValueKey('orion-compact-toggle')), findsNothing);
  expect(find.byTooltip('Compact mode'), findsNothing);
  expect(find.byTooltip('Exit compact mode'), findsNothing);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

class _MemoryController extends OrionController {
  @override
  Future<void> flushPersistence() async {}
}

Future<void> _showWindowControls(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Compact mode'));
  await _settle(tester);
}
