import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/services/companion_commands.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_density.dart';
import 'package:orion/theme/orion_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'size modes are exclusive in one notification, including generic IPC',
    () {
      final c = OrionController(persistChanges: false);
      addTearDown(c.dispose);
      final changes = <(bool, bool)>[];
      c.addListener(
        () => changes.add((c.orionCompactMode, c.orionEnlargedMode)),
      );
      expect((c.orionCompactMode, c.orionEnlargedMode), (false, false));
      c.setOrionCompactMode(true);
      c.setOrionEnlargedMode(true);
      c.setOrionEnlargedMode(true);
      c.setInterfacePreference(InterfacePreset.orion, 'compactMode', true);
      c.setInterfacePreference(InterfacePreset.orion, 'enlargedMode', true);
      c.setOrionEnlargedMode(false);
      expect(changes, [
        (true, false),
        (false, true),
        (true, false),
        (false, true),
        (false, false),
      ]);
    },
  );

  test(
    'enlarged mode survives recovery and returns to normal on disable',
    () async {
      final folder = await Directory.systemTemp.createTemp('orion-enlarged-');
      final first = OrionController(storageDirectory: folder);
      OrionController? restored;
      try {
        await first.initialize();
        expect(first.orionEnlargedMode, isFalse);
        first.setUiScale(1.2);
        first.setOrionCompactMode(true);
        first.setOrionEnlargedMode(true);
        first.updateDocumentContent(
          first.activeDocumentId,
          'print("retained")',
        );
        first.setInterface(InterfacePreset.synapseBlue);
        await first.flushPersistence();
        restored = OrionController(storageDirectory: folder);
        await restored.initialize();
        expect(restored.orionEnlargedMode, isTrue);
        expect(restored.orionCompactMode, isFalse);
        expect(restored.uiScale, 1.2);
        expect(restored.activeDocument.content, 'print("retained")');
        expect(restored.selectedInterface, InterfacePreset.synapseBlue);
        restored.setInterface(InterfacePreset.orion);
        for (final cold in [false, true]) {
          expect(
            InterfaceWindowProfile.forInterface(
              restored,
              InterfacePreset.orion,
              coldStart: cold,
            ).size,
            InterfaceWindowProfile.orionEnlargedSize,
          );
        }
        restored.setOrionEnlargedMode(false);
        expect(
          InterfaceWindowProfile.forInterface(
            restored,
            InterfacePreset.orion,
          ).size,
          InterfaceWindowProfile.orionSize,
        );
      } finally {
        first.dispose();
        await first.flushPersistence();
        restored?.dispose();
        await restored?.flushPersistence();
        await folder.delete(recursive: true);
      }
    },
  );

  test(
    'enlarged mode leaves source profiles and normal Studio size intact',
    () {
      final c = OrionController(persistChanges: false);
      addTearDown(c.dispose);
      final sourceProfiles = {
        for (final preset in InterfacePreset.values)
          if (preset != InterfacePreset.orion)
            for (final cold in [false, true])
              (preset, cold): InterfaceWindowProfile.forInterface(
                c,
                preset,
                coldStart: cold,
              ).size,
      };
      c.applyThemeStudioState(
        InterfacePreset.orion,
        document: SynapseThemeCatalog.defaults(InterfacePreset.orion)
            .withWindow('main', SynapseStudioWindow(width: 1000, height: 700))
            .toJson(),
      );
      c.setOrionEnlargedMode(true);
      for (final scale in [.8, 1, 1.25]) {
        c.setUiScale(scale.toDouble());
        final profile = InterfaceWindowProfile.forInterface(
          c,
          InterfacePreset.orion,
        );
        expect(profile.size, const Size(1045, 648));
        expect(profile.minimumSize, const Size(720, 480));
        expect(profile.resizable, isTrue);
        expect(profile.alwaysOnTop, isFalse);
        for (final entry in sourceProfiles.entries) {
          expect(
            InterfaceWindowProfile.forInterface(
              c,
              entry.key.$1,
              coldStart: entry.key.$2,
            ).size,
            entry.value,
          );
        }
      }
      c.setOrionCompactMode(true);
      expect(c.orionEnlargedMode, isFalse);
      expect(
        InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
        InterfaceWindowProfile.compactOrionSizeFor(const Size(1000, 700)),
      );
      c.setOrionEnlargedMode(true);
      c.setOrionEnlargedMode(false);
      expect(
        InterfaceWindowProfile.forInterface(c, InterfacePreset.orion).size,
        const Size(1000, 700),
      );
    },
  );

  test(
    'companion size switches use the existing ordered preference transport',
    () async {
      final owner = OrionController(persistChanges: false);
      final commands = CompanionCommands(owner);
      final operations = <String>[];
      var revision = 0;
      final child = CompanionController(
        initialState: owner.exportWindowState(),
        sendCommand: (operation, payload, sequence) async {
          operations.add(operation);
          await commands.apply(operation, payload);
          return {
            'envelope': {
              'state': owner.exportWindowState(),
              'ack': sequence,
              'revision': ++revision,
            },
          };
        },
      );
      addTearDown(() {
        child.dispose();
        owner.dispose();
      });
      final ownerModes = <(bool, bool)>[];
      owner.addListener(
        () => ownerModes.add((owner.orionCompactMode, owner.orionEnlargedMode)),
      );
      child.setOrionCompactMode(true);
      child.setOrionEnlargedMode(true);
      child.setOrionCompactMode(true);
      await child.flushCommands();
      expect(operations, List.filled(3, 'setInterfacePreference'));
      expect(ownerModes, [(true, false), (false, true), (true, false)]);
      expect(child.orionEnlargedMode, isFalse);
      expect(child.orionCompactMode, isTrue);
      expect(
        child.getInterfacePreferences(InterfacePreset.orion),
        owner.getInterfacePreferences(InterfacePreset.orion),
      );
      expect(child.pendingCommandCount, 0);
    },
  );

  testWidgets(
    'Settings places both size switches together without changing editor density',
    (tester) async {
      tester.view.physicalSize = const Size(1045, 648);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = OrionController(persistChanges: false)
        ..completeIntro()
        ..setReducedMotion(true);
      addTearDown(c.dispose);
      await tester.pumpWidget(OrionApp(controller: c, nativeWindow: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final compact = find.byKey(const ValueKey('settings-compact-mode'));
      final enlarged = find.byKey(const ValueKey('settings-enlarged-mode'));
      expect(compact, findsOneWidget);
      expect(enlarged, findsOneWidget);
      expect(
        tester.getCenter(enlarged).dy,
        greaterThan(tester.getCenter(compact).dy),
      );
      expect(
        tester.getCenter(enlarged).dy - tester.getCenter(compact).dy,
        lessThan(75),
      );
      await tester.tap(enlarged);
      await tester.pumpAndSettle();
      expect(c.orionEnlargedMode, isTrue);
      expect(c.orionCompactMode, isFalse);
      expect(OrionDensity.of(tester.element(enlarged)).amount, 0);
      await tester.tap(compact);
      await tester.pumpAndSettle();
      expect(c.orionCompactMode, isTrue);
      expect(c.orionEnlargedMode, isFalse);
      expect(tester.widget<Switch>(enlarged).value, isFalse);
      await tester.tap(find.byTooltip('Theme Control'));
      await tester.pumpAndSettle();
      expect(find.text('Compact mode'), findsNothing);
      expect(find.text('Enlarged mode'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (startMode, startBounds, reduced) in [
    ('normal', const Rect.fromLTWH(25, 37, 960, 640), true),
    ('enlarged', const Rect.fromLTWH(25, 37, 1045, 648), true),
    ('compact', const Rect.fromLTWH(25, 37, 740, 470), true),
    ('normal', const Rect.fromLTWH(25, 37, 822, 523), false),
  ]) {
    testWidgets(
      'native $startMode morphs compact/enlarged/normal at exact bounds (reduced=$reduced)',
      (tester) async {
        final native = _NativeBounds(tester, startBounds);
        native.install();
        addTearDown(native.uninstall);
        final c = OrionController(persistChanges: false)
          ..completeIntro()
          ..setReducedMotion(reduced);
        if (startMode == 'enlarged') c.setOrionEnlargedMode(true);
        if (startMode == 'compact') c.setOrionCompactMode(true);
        addTearDown(c.dispose);
        tester.view.physicalSize = const Size(1045, 648);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: orionTheme(Brightness.dark, c.accentColor),
            home: OrionShell(
              controller: c,
              nativeWindow: true,
              previewPage: 'settings',
              onSwitchInterface: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final normal = startMode == 'normal'
            ? startBounds.size
            : const Size(822, 523);
        c.setOrionCompactMode(true);
        await _settleMorph(tester);
        expect(
          native.bounds.size,
          InterfaceWindowProfile.compactOrionSizeFor(normal),
        );
        c.setOrionEnlargedMode(true);
        await _settleMorph(tester);
        expect(native.bounds.size, const Size(1045, 648));
        expect(c.orionCompactMode, isFalse);
        c.setOrionEnlargedMode(false);
        await _settleMorph(tester);
        expect(native.bounds.size, normal);
        if (startMode == 'normal') expect(native.bounds, startBounds);
        expect(native.minimumSizes.last, const Size(720, 480));
        expect(native.maximumConcurrentWrites, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'rapid native mode retargeting lands only the final enlarged size',
    (tester) async {
      final native = _NativeBounds(
        tester,
        const Rect.fromLTWH(25, 37, 822, 523),
      );
      native.install();
      addTearDown(native.uninstall);
      final c = OrionController(persistChanges: false)..completeIntro();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1045, 648);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: orionTheme(Brightness.dark, c.accentColor),
          home: OrionShell(
            controller: c,
            nativeWindow: true,
            previewPage: 'settings',
            onSwitchInterface: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.setOrionCompactMode(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      c.setOrionEnlargedMode(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      c.setOrionEnlargedMode(false);
      c.setOrionCompactMode(true);
      c.setOrionEnlargedMode(true);
      await _settleMorph(tester);
      expect(native.bounds.size, const Size(1045, 648));
      expect(c.orionCompactMode, isFalse);
      expect(c.orionEnlargedMode, isTrue);
      expect(native.maximumConcurrentWrites, 1);
      c.setOrionEnlargedMode(false);
      await _settleMorph(tester);
      expect(native.bounds, const Rect.fromLTWH(25, 37, 822, 523));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _settleMorph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

class _NativeBounds {
  _NativeBounds(this.tester, this.bounds);
  final WidgetTester tester;
  Rect bounds;
  final minimumSizes = <Size>[];
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const window = MethodChannel('window_manager');
  static const native = MethodChannel('orion/window');

  void install() {
    messenger.setMockMethodCallHandler(window, (call) async {
      switch (call.method) {
        case 'isFullScreen':
        case 'isMaximized':
          return false;
        case 'getBounds':
          return {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          };
        case 'setBounds':
          final p = call.arguments as Map;
          _activeWrites++;
          if (_activeWrites > maximumConcurrentWrites) {
            maximumConcurrentWrites = _activeWrites;
          }
          bounds = Rect.fromLTWH(
            (p['x'] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['width'] as num).toDouble(),
            (p['height'] as num).toDouble(),
          );
          await Future<void>.value();
          _activeWrites--;
          return null;
        case 'setMinimumSize':
          final p = call.arguments as Map;
          minimumSizes.add(
            Size(
              (p['width'] as num).toDouble(),
              (p['height'] as num).toDouble(),
            ),
          );
          return null;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(native, (call) async => null);
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(native, null);
  }
}
