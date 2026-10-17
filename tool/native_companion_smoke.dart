import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:orion/main.dart' as application;
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/services/companion_window_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:window_manager/window_manager.dart';

/// Native integration target, run by developers with a disposable XDG_DATA_HOME.
/// Build this target separately; the shipping entry point has no smoke flags.
Future<void> main(List<String> arguments) async {
  _requireDisposableDataHome();
  final controller = await application.runOrion(arguments);
  // Every child engine enters this same target. Its normal bootstrap owns it.
  if (controller == null) return;
  final smoke = _NativeCompanionSmoke(controller);
  try {
    await smoke.run();
    await smoke.service.closeAll();
    await smoke.waitForKinds(const {});
    await controller.flushPersistence();
    stdout.writeln(jsonEncode(smoke.result));
    await stdout.flush();
  } catch (error, stack) {
    exitCode = 1;
    stderr.writeln(
      jsonEncode({
        'nativeCompanionSmoke': 'FAIL',
        'stage': smoke.stage,
        'error': error.toString(),
      }),
    );
    stderr.writeln(stack);
    await stderr.flush();
    try {
      await smoke.service.closeAll();
      await smoke.waitForKinds(const {});
      await controller.flushPersistence();
    } catch (error) {
      exitCode = 1;
      stderr.writeln('Smoke cleanup failed: $error');
      await stderr.flush();
    }
  } finally {
    await windowManager.destroy();
  }
}

void _requireDisposableDataHome() {
  final data = Platform.environment['XDG_DATA_HOME'];
  final workspace = Platform.environment['ORION_WORKSPACE'];
  final home = Platform.environment['HOME'];
  final defaultData = home == null ? null : Directory('$home/.local/share').uri;
  if (data == null ||
      data.trim().isEmpty ||
      Directory(data).uri == defaultData ||
      workspace == null ||
      workspace.trim().isEmpty ||
      !Directory(workspace).isAbsolute ||
      (home != null &&
          Directory(workspace).uri == Directory('$home/orion').uri)) {
    throw StateError(
      'Run the native smoke target with XDG_DATA_HOME and ORION_WORKSPACE '
      'set to absolute disposable fixture directories, outside the normal '
      'application data directory and ~/orion.',
    );
  }
}

class _NativeCompanionSmoke {
  _NativeCompanionSmoke(this.controller)
    : service = controller.companionWindows! as CompanionWindowService;

  final OrionController controller;
  final CompanionWindowService service;
  final checks = <String>[];
  final rootBounds = <String, Map<String, double>>{};
  final clock = Stopwatch()..start();
  String stage = 'launch';

  Map<String, Object?> get result => {
    'nativeCompanionSmoke': 'PASS',
    'backend': Platform.environment['GDK_BACKEND'] ?? 'default',
    'checks': checks,
    'rootBounds': rootBounds,
    'elapsedMs': clock.elapsedMilliseconds,
  };

  Future<void> run() async {
    await WidgetsBinding.instance.endOfFrame;
    controller.setReducedMotion(true);
    controller.completeIntro();
    await _settle();
    _expect(
      service.onSelectInterface != null,
      'Primary switch callback missing',
    );

    await _krnlCycles();
    await _synapseWindows(InterfacePreset.synapseX, const {
      CompanionWindowKind.synapseXOptions,
      CompanionWindowKind.synapseXHub,
      CompanionWindowKind.synapseXConsole,
    });
    await _synapseWindows(InterfacePreset.synapse2017, const {
      CompanionWindowKind.synapseOgSettings,
      CompanionWindowKind.synapseOgHub,
      CompanionWindowKind.synapseOgConsole,
    });
    await _xenoWindows();
    await _undockedEditor();

    stage = 'back-to-orion';
    await service.returnToOrion();
    await _settle();
    _expect(
      controller.selectedInterface == InterfacePreset.orion,
      'Back to Orion did not select the main interface',
    );
    await waitForKinds(const {});
    _expect(await windowManager.isVisible(), 'Primary is hidden after return');
    await controller.flushPersistence();
    checks.add('Back to Orion closes all companions and preserves recovery');
    stage = 'complete';
  }

  Future<void> _krnlCycles() async {
    final baseline = await _switch(InterfacePreset.krnl);
    for (var cycle = 1; cycle <= 6; cycle++) {
      stage = 'krnl-options-$cycle';
      await service.open(CompanionWindowKind.krnlOptions);
      await waitForKinds(const {CompanionWindowKind.krnlOptions});
      await _settle(milliseconds: 350);
      await _expectBounds(baseline);
      await service.closeAll();
      await waitForKinds(const {});
      await _expectBounds(baseline);
    }
    checks.add(
      'KRNL options: 6 native open/close cycles; owner bounds retained',
    );
  }

  Future<void> _synapseWindows(
    InterfacePreset preset,
    Set<CompanionWindowKind> kinds,
  ) async {
    final baseline = await _switch(preset);
    final expected = <CompanionWindowKind>{};
    for (final kind in kinds) {
      stage = '${preset.name}-${kind.name}';
      await service.open(kind);
      expected.add(kind);
      await waitForKinds(expected);
      await _settle(milliseconds: 350);
      await _expectBounds(baseline);
    }
    _expect(
      (await _children()).map((window) => window.windowId).toSet().length == 3,
      '${preset.label} did not keep three independent companions alive',
    );
    await service.closeAll();
    await waitForKinds(const {});
    await _expectBounds(baseline);
    checks.add(
      '${preset.label}: 3 simultaneous native windows; owner bounds retained',
    );
  }

  Future<void> _xenoWindows() async {
    final baseline = await _switch(InterfacePreset.xeno);
    stage = 'xeno-settings-hide-owner';
    await service.open(CompanionWindowKind.xenoSettings);
    await waitForKinds(const {CompanionWindowKind.xenoSettings});
    await _settle(milliseconds: 350);
    _expect(
      !await windowManager.isVisible(),
      'Xeno Settings did not hide owner',
    );
    await service.closeAll();
    await waitForKinds(const {});
    _expect(
      await windowManager.isVisible(),
      'Xeno Settings did not restore owner',
    );
    await _expectBounds(baseline);

    stage = 'xeno-scripts-toggle';
    await service.open(CompanionWindowKind.xenoScripts);
    await waitForKinds(const {CompanionWindowKind.xenoScripts});
    await _settle(milliseconds: 350);
    final firstScripts = (await _children()).single.windowId;
    await service.open(CompanionWindowKind.xenoScripts);
    await waitForKinds(const {});
    await service.open(CompanionWindowKind.xenoScripts);
    await waitForKinds(const {CompanionWindowKind.xenoScripts});
    _expect(
      (await _children()).single.windowId != firstScripts,
      'Xeno Scripts toggle did not destroy and recreate its source window',
    );
    await service.closeAll();
    await waitForKinds(const {});

    stage = 'xeno-clients-hide-reopen';
    await service.open(CompanionWindowKind.xenoClients);
    await waitForKinds(const {CompanionWindowKind.xenoClients});
    await _settle(milliseconds: 350);
    final clients = (await _children()).single.windowId;
    await service.open(CompanionWindowKind.xenoClients);
    await waitForKinds(const {CompanionWindowKind.xenoClients});
    _expect(
      (await _children()).single.windowId == clients,
      'Hiding Xeno Clients destroyed its retained source window',
    );
    await service.open(CompanionWindowKind.xenoClients);
    await waitForKinds(const {CompanionWindowKind.xenoClients});
    _expect(
      (await _children()).single.windowId == clients,
      'Reopening Xeno Clients created a duplicate native window',
    );
    await _expectBounds(baseline);
    await service.closeAll();
    await waitForKinds(const {});
    checks.add(
      'Xeno: Settings hides/restores owner; Scripts toggles lifetime; Clients retains identity',
    );
  }

  Future<void> _undockedEditor() async {
    final baseline = await _switch(InterfacePreset.synapseV3);
    stage = 'v3-native-editor-preview';
    final preview = await const MethodChannel('orion/monaco')
        .invokeMethod<Uint8List>('capturePreview')
        .timeout(const Duration(seconds: 3));
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    _expect(
      preview != null &&
          preview.length > 24 &&
          List.generate(8, (index) => preview[index]).join(',') ==
              signature.join(','),
      'Native editor capture did not return a PNG',
    );
    checks.add('Real Monaco preview returns PNG for Flutter overlays');
    final id = controller.documents.first.id;
    const before = 'print("native undock smoke")';
    const canonical = 'print("canonical dirty draft survives redock")';
    controller.selectDocument(id);
    controller.updateDocumentContent(id, before);
    await _settle();

    stage = 'v3-undock';
    await service.open(CompanionWindowKind.synapseV3Editor, documentId: id);
    await waitForKinds(const {CompanionWindowKind.synapseV3Editor});
    await _settle();
    _expect(
      controller.detachedDocumentIds.contains(id),
      'V3 did not detach tab',
    );
    _expect(
      controller.activeDocumentId != id,
      'V3 kept detached main tab active',
    );
    final child = (await _children()).single;
    _expect(
      _definition(child)['documentId'] == id,
      'V3 child has wrong document',
    );
    await _expectBounds(baseline);

    stage = 'v3-canonical-edit-and-redock';
    controller.updateDocumentContent(id, canonical);
    await _settle(milliseconds: 1200);
    await child.invokeMethod<void>('closeFromOwner');
    await waitForKinds(const {});
    _expect(
      !controller.detachedDocumentIds.contains(id),
      'V3 tab stayed detached',
    );
    _expect(
      controller.activeDocumentId == id,
      'V3 redock did not select its tab',
    );
    final document = controller.documents.singleWhere(
      (document) => document.id == id,
    );
    _expect(
      document.content == canonical,
      'Native flush overwrote canonical draft',
    );
    _expect(document.isDirty, 'V3 lost the unsaved dirty-document state');
    await _expectBounds(baseline);
    checks.add(
      'V3: independent document engine, canonical edit, native redock, dirty draft retained',
    );
  }

  Future<Rect> _switch(InterfacePreset preset) async {
    stage = 'switch-${preset.name}';
    await service.onSelectInterface!(preset);
    _expect(
      controller.selectedInterface == preset,
      'Interface switch was ignored',
    );
    // OG's source loader deliberately keeps its 2.5 s hold, and V3 keeps 2 s,
    // even when motion is reduced. Let their final source geometry settle.
    await _settle(
      milliseconds: switch (preset) {
        InterfacePreset.synapse2017 => 3500,
        InterfacePreset.synapseV3 => 3200,
        _ => 1000,
      },
    );
    await waitForKinds(const {});
    final bounds = await windowManager.getBounds();
    rootBounds[preset.name] = {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    };
    return bounds;
  }

  Future<List<WindowController>> _children() async => [
    for (final window in await WindowController.getAll())
      if (window.windowId != service.window.windowId) window,
  ];

  Map<String, Object?> _definition(WindowController window) {
    final definition = jsonDecode(window.arguments);
    _expect(
      definition is Map && definition['type'] == 'orion-companion',
      'Unexpected native engine ${window.windowId}: ${window.arguments}',
    );
    return Map<String, Object?>.from(definition as Map);
  }

  Future<void> waitForKinds(Set<CompanionWindowKind> expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (true) {
      final windows = await WindowController.getAll();
      _expect(
        windows.any((window) => window.windowId == service.window.windowId),
        'Primary native engine disappeared',
      );
      final children = windows.where(
        (window) => window.windowId != service.window.windowId,
      );
      final actual = children
          .map((window) => _definition(window)['kind'])
          .toList();
      final names = expected.map((kind) => kind.name).toSet();
      if (actual.length == names.length && actual.toSet().containsAll(names)) {
        return;
      }
      _expect(
        DateTime.now().isBefore(deadline),
        'Native window set did not settle: expected $names, found $actual',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _expectBounds(Rect expected) async {
    final actual = await windowManager.getBounds();
    const tolerance = 1.5;
    _expect(
      (expected.left - actual.left).abs() <= tolerance &&
          (expected.top - actual.top).abs() <= tolerance &&
          (expected.width - actual.width).abs() <= tolerance &&
          (expected.height - actual.height).abs() <= tolerance,
      'Companion changed primary bounds: expected $expected, found $actual',
    );
  }

  Future<void> _settle({int milliseconds = 1000}) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    // Xeno Settings deliberately hides the primary; hidden Wayland surfaces
    // receive no frame callbacks until the owner is shown again.
    if (await windowManager.isVisible()) {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
  }

  void _expect(bool condition, String message) {
    if (!condition) throw StateError('$stage: $message');
  }
}
