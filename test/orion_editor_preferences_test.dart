import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/app.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/services/companion_commands.dart';
import 'package:orion/services/companion_controller.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/theme/orion_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'main editor preferences survive disk recovery and stay scoped to Orion',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orion-main-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final c = OrionController(storageDirectory: directory);
      await c.initialize();
      addTearDown(() async {
        c.dispose();
        await c.flushPersistence();
      });
      expect(c.alwaysOnTop, isFalse);
      expect(c.showMinimap, isFalse);
      expect(c.autocomplete, isTrue);
      expect(c.bracketPairColorization, isTrue);
      expect(c.renderWhitespace, isFalse);
      c.setInterfacePreference(InterfacePreset.synapseX, 'minimap', false);
      c.setAlwaysOnTop(true);
      c.setShowMinimap(true);
      c.setAutocomplete(false);
      c.setBracketPairColorization(false);
      c.setRenderWhitespace(true);
      await c.flushPersistence();
      final recovered = OrionController(storageDirectory: directory);
      await recovered.initialize();
      addTearDown(() async {
        recovered.dispose();
        await recovered.flushPersistence();
      });
      expect(
        InterfaceWindowProfile.forInterface(
          recovered,
          InterfacePreset.orion,
          coldStart: true,
        ).alwaysOnTop,
        isTrue,
      );
      expect(recovered.showMinimap, isTrue);
      expect(recovered.autocomplete, isFalse);
      expect(recovered.bracketPairColorization, isFalse);
      expect(recovered.renderWhitespace, isTrue);
      expect(
        InterfaceWindowProfile.forInterface(
          recovered,
          InterfacePreset.synapseX,
        ).alwaysOnTop,
        isFalse,
      );
      expect(recovered.getInterfacePreferences(InterfacePreset.synapseX), {
        'minimap': false,
      });
      recovered.resetInterfacePreferences(InterfacePreset.orion);
      expect(recovered.alwaysOnTop, isFalse);
      expect(recovered.showMinimap, isFalse);
      expect(recovered.autocomplete, isTrue);
      expect(recovered.bracketPairColorization, isTrue);
      expect(recovered.renderWhitespace, isFalse);
    },
  );

  test(
    'new settings use the existing ordered companion preference transport',
    () async {
      final owner = OrionController(persistChanges: false);
      final gateway = CompanionCommands(owner);
      final operations = <String>[];
      var revision = 0;
      final child = CompanionController(
        initialState: owner.exportWindowState(),
        sendCommand: (operation, payload, sequence) async {
          operations.add(operation);
          await gateway.apply(operation, payload);
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
      final source = owner.activeDocument.content;
      child.setAlwaysOnTop(true);
      child.setShowMinimap(true);
      child.setAutocomplete(false);
      child.setBracketPairColorization(false);
      child.setRenderWhitespace(true);
      await child.flushCommands();
      expect(operations, List.filled(5, 'setInterfacePreference'));
      expect(owner.alwaysOnTop, isTrue);
      expect(owner.showMinimap, isTrue);
      expect(owner.autocomplete, isFalse);
      expect(owner.bracketPairColorization, isFalse);
      expect(owner.renderWhitespace, isTrue);
      expect(child.pendingCommandCount, 0);
      expect(owner.activeDocument.content, source);
      expect(
        child.getInterfacePreferences(InterfacePreset.orion),
        owner.getInterfacePreferences(InterfacePreset.orion),
      );
    },
  );

  testWidgets(
    'topmost applies to the native window immediately and stops at shell exit',
    (tester) async {
      const channel = MethodChannel('window_manager');
      const native = MethodChannel('orion/window');
      final calls = <bool>[];
      final nativeCalls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setAlwaysOnTop') {
          calls.add((call.arguments as Map)['isAlwaysOnTop'] as bool);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'setAlwaysOnTop') {
          final enabled = (call.arguments as Map)['enabled'] as bool;
          nativeCalls.add(enabled);
          return '{"ok":true,"above":$enabled,"active":$enabled}';
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(() => messenger.setMockMethodCallHandler(native, null));
      final c = OrionController(persistChanges: false)..setReducedMotion(true);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 700);
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
      c.setAlwaysOnTop(true);
      await tester.pumpAndSettle();
      c.setAlwaysOnTop(false);
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(nativeCalls, Platform.isLinux ? [true, false] : isEmpty);
      c.setInterface(InterfacePreset.synapseX);
      c.setAlwaysOnTop(true);
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(nativeCalls, Platform.isLinux ? [true, false] : isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      c.setAlwaysOnTop(false);
      await tester.pumpAndSettle();
      expect(calls, [true, false]);
      expect(nativeCalls, Platform.isLinux ? [true, false] : isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
