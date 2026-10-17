import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:orion/main.dart' as application;
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/interface_window_profile.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/models/synapse_studio_theme.dart';
import 'package:orion/screens/synapse_theme_studio.dart';
import 'package:orion/services/companion_window_service.dart';
import 'package:orion/services/synapse_theme_catalog.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/synapse_og/synapse_og_shell.dart';
import 'package:orion/synapse_v3/v3_undocked_editor.dart';
import 'package:orion/synapse_x/synapse_x_shell.dart';
import 'package:window_manager/window_manager.dart';

/// Developer-only native integration target. Every child uses the ordinary
/// production bootstrap plus an independent, read-only geometry inspector.
/// Build separately and run with an empty disposable XDG_DATA_HOME.
Future<void> main(List<String> arguments) async {
  _requireDisposableDataHome();
  final controller = await application.runOrion(arguments);
  if (controller == null) {
    await _installInspector();
    return;
  }
  final smoke = _StudioSmoke(controller);
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
        'nativeSynapseStudioSmoke': 'FAIL',
        'stage': smoke.stage,
        'error': error.toString(),
        'checks': smoke.checks,
      }),
    );
    stderr.writeln(stack);
    await stderr.flush();
    try {
      await smoke.service.closeAll();
      await smoke.waitForKinds(const {});
      await controller.flushPersistence();
    } catch (cleanup) {
      stderr.writeln('Smoke cleanup failed: $cleanup');
    }
  } finally {
    await controller.closeBridge();
    await windowManager.destroy();
  }
}

void _requireDisposableDataHome() {
  final data = Platform.environment['XDG_DATA_HOME'];
  final workspace = Platform.environment['ORION_WORKSPACE'];
  final home = Platform.environment['HOME'];
  if (data == null ||
      data.trim().isEmpty ||
      workspace == null ||
      workspace.trim().isEmpty ||
      !Directory(workspace).isAbsolute ||
      (home != null &&
          Directory(workspace).uri == Directory('$home/orion').uri) ||
      (home != null &&
          Directory(data).uri == Directory('$home/.local/share').uri)) {
    throw StateError(
      'Set XDG_DATA_HOME and ORION_WORKSPACE to absolute disposable fixture '
      'directories, outside the normal application data directory and ~/orion.',
    );
  }
}

String _inspectorName(String id) => 'orion/native-synapse-studio-smoke/$id';

Future<void> _installInspector() async {
  final window = await WindowController.fromCurrentEngine();
  if (window.arguments.isEmpty) return;
  final definition = jsonDecode(window.arguments);
  if (definition is! Map || definition['type'] != 'orion-companion') return;
  await WindowMethodChannel(
    _inspectorName(window.windowId),
    mode: ChannelMode.unidirectional,
  ).setMethodCallHandler((call) async {
    if (call.method != 'inspect') throw MissingPluginException(call.method);
    OrionController? owner;
    String? renderedStudio;
    var genericStudioTitle = false;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is SynapseThemeStudioScreen) {
        owner = widget.controller;
        renderedStudio = widget.preset.name;
        return; // Preview controllers are intentionally draft-only.
      } else if (widget is SynapseXShell) {
        owner = widget.controller;
      } else if (widget is SynapseOgShell) {
        owner = widget.controller;
      } else if (widget is V3UndockedEditor) {
        owner = widget.controller;
      }
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    void visitLabels(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data == 'Theme Studio') {
        genericStudioTitle = true;
      }
      element.visitChildElements(visitLabels);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visitLabels);
    final bounds = await windowManager.getBounds();
    return <String, Object?>{
      'windowId': window.windowId,
      'kind': definition['kind'],
      'bounds': _bounds(bounds),
      'visible': await windowManager.isVisible(),
      'resizable': await windowManager.isResizable(),
      'renderedStudio': renderedStudio,
      'genericStudioTitle': genericStudioTitle,
      'controllerReady': owner != null,
      'orionTheme': owner?.orionTheme.toJson(),
      'orionCompactMode': owner?.orionCompactMode,
      'themes': {
        if (owner != null)
          for (final preset in SynapseThemeCatalog.supported)
            preset.name: {
              'name': SynapseThemeCatalog.current(owner!, preset).name,
              'windows': {
                for (final entry in SynapseThemeCatalog.current(
                  owner!,
                  preset,
                ).windows.entries)
                  entry.key: {
                    'width': entry.value.width,
                    'height': entry.value.height,
                  },
              },
            },
      },
    };
  });
}

Map<String, double> _bounds(Rect rect) => {
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

class _StudioSmoke {
  _StudioSmoke(this.controller)
    : service = controller.companionWindows! as CompanionWindowService;
  final OrionController controller;
  final CompanionWindowService service;
  final checks = <String>[];
  final geometry = <String, Object?>{};
  final clock = Stopwatch()..start();
  String _stage = 'launch';
  String get stage => _stage;
  set stage(String value) {
    _stage = value;
    stdout.writeln(jsonEncode({'stage': value}));
  }

  String? documentId;
  static const _script = 'print("native Theme Studio smoke")';
  Map<String, Object?> get result => {
    'nativeSynapseStudioSmoke': 'PASS',
    'backend': Platform.environment['GDK_BACKEND'] ?? 'default',
    'checks': checks,
    'geometry': geometry,
    'elapsedMs': clock.elapsedMilliseconds,
  };

  Future<void> run() async {
    controller.setReducedMotion(true);
    controller.completeIntro();
    documentId = controller.activeDocumentId;
    controller.updateDocumentContent(documentId!, _script);
    await _settle(800);
    _expect(
      service.onSelectInterface != null,
      'Main source switch callback missing',
    );
    await _exerciseOrion();
    for (final preset in SynapseThemeCatalog.synapsePresets) {
      await _exercise(preset);
    }
    stage = 'return-to-orion';
    await service.returnToOrion();
    await waitForKinds(const {});
    await _settle(600);
    _expect(
      controller.selectedInterface == InterfacePreset.orion,
      'Source return failed',
    );
    _expect(await windowManager.isVisible(), 'Main Orion was left hidden');
    _expect(
      controller.documents.singleWhere((d) => d.id == documentId).content ==
          _script,
      'Source changes or native closes altered the dirty script',
    );
    checks.add(
      'All five native studios close cleanly; return to Orion preserves the unsaved script',
    );
    stage = 'complete';
  }

  Future<void> _exerciseOrion() async {
    const preset = InterfacePreset.orion;
    const studioKind = CompanionWindowKind.orionThemeStudio;
    controller.setOrionCompactMode(false);
    await _settle(500);
    final before = await windowManager.getBounds();
    geometry['orion.original'] = _bounds(before);
    stage = 'orion-open-studio';
    await service.open(studioKind);
    await waitForKinds({studioKind});
    var studio = (await _children()).single;
    final initial = await _inspect(studio);
    _expect(initial['renderedStudio'] == preset.name, 'Wrong Orion Studio');
    _expect(
      initial['genericStudioTitle'] == true,
      'Generic Studio title missing',
    );
    _expect(initial['resizable'] == true, 'Orion Studio is not resizable');
    _expectSize(_readBounds(initial), const Size(1180, 760), 'Orion Studio');
    await _expectMainSize(before.size);
    await service.open(studioKind);
    await waitForKinds({studioKind});
    _expect(
      (await _children()).single.windowId == studio.windowId,
      'Orion Studio repeat open duplicated its engine',
    );
    checks.add(
      'Orion: standalone generic Theme Studio opens at 1180×760 and reuses its engine without resizing the source',
    );

    stage = 'orion-atomic-palette-document-apply';
    final palette = OrionThemePreferences.defaults.copyWith(
      presetId: 'native-smoke',
      accent: const Color(0xff78d6bb),
      gradientEnabled: true,
      gradientColors: const [Color(0xff111b25), Color(0xff202638)],
      overrides: const {'editor': Color(0xff101c28)},
    );
    var customSize = Size(before.width + 96, before.height + 64);
    var document = SynapseThemeCatalog.defaults(preset)
        .copyWith(
          name: 'Native Orion',
          colors: SynapseThemeCatalog.orionPalette(palette),
          orionTheme: palette,
        )
        .withWindow(
          'main',
          SynapseStudioWindow(
            width: customSize.width,
            height: customSize.height,
            elements: {
              'executeButton': SynapseStudioElement(
                fill: 0xff244b75,
                foreground: 0xffeef6ff,
                x: 3,
                radius: 9,
              ),
            },
          ),
        );
    controller.applyThemeStudioState(
      preset,
      document: document.toJson(),
      draft: null,
      orionTheme: palette,
    );
    await controller.flushPersistence();
    await _waitMainSize(customSize);
    var inspection = await _waitTheme(studio, preset, document.name);
    _expect(
      jsonEncode(inspection['orionTheme']) == jsonEncode(palette.toJson()),
      'Orion palette did not accompany its Studio document',
    );
    geometry['orion.custom'] = _bounds(await windowManager.getBounds());
    checks.add(
      'Orion: atomic palette and advanced document apply resize the live source and synchronize the standalone Studio',
    );

    stage = 'orion-compact-custom-size-composition';
    controller.setOrionCompactMode(true);
    await _waitMainSize(InterfaceWindowProfile.compactOrionSizeFor(customSize));
    geometry['orion.compact'] = _bounds(await windowManager.getBounds());
    customSize = Size(customSize.width + 32, customSize.height + 16);
    document = document.withWindow(
      'main',
      document
          .window('main')
          .copyWith(width: customSize.width, height: customSize.height),
    );
    controller.applyThemeStudioState(
      preset,
      document: document.toJson(),
      draft: null,
      orionTheme: palette,
    );
    await controller.flushPersistence();
    await _waitMainSize(InterfaceWindowProfile.compactOrionSizeFor(customSize));
    geometry['orion.compactEdited'] = _bounds(await windowManager.getBounds());
    controller.setOrionCompactMode(false);
    await _waitMainSize(customSize);
    geometry['orion.restoredCustom'] = _bounds(await windowManager.getBounds());
    checks.add(
      'Orion: compact mode scales custom Studio dimensions and restores the edited normal dimensions',
    );

    stage = 'orion-close-reopen-and-reset';
    await studio.invokeMethod<void>('closeFromOwner');
    await waitForKinds(const {});
    await _expectMainSize(customSize);
    await service.open(studioKind);
    await waitForKinds({studioKind});
    studio = (await _children()).single;
    inspection = await _waitTheme(studio, preset, document.name);
    _expect(
      jsonEncode(inspection['orionTheme']) == jsonEncode(palette.toJson()),
      'Orion palette did not persist across Studio close/reopen',
    );
    final original = SynapseThemeCatalog.defaults(preset);
    controller.applyThemeStudioState(
      preset,
      document: original.toJson(),
      draft: null,
      orionTheme: OrionThemePreferences.defaults,
    );
    await controller.flushPersistence();
    await _waitMainSize(InterfaceWindowProfile.orionSize);
    inspection = await _waitTheme(studio, preset, original.name);
    _expect(
      jsonEncode(inspection['orionTheme']) ==
          jsonEncode(OrionThemePreferences.defaults.toJson()),
      'Orion reset did not restore the default palette',
    );
    await service.closeAll();
    await waitForKinds(const {});
    await _expectMainSize(InterfaceWindowProfile.orionSize);
    checks.add(
      'Orion: close/reopen retains its advanced theme; reset restores the default palette and normal window size',
    );
  }

  Future<void> _exercise(InterfacePreset preset) async {
    stage = 'switch-${preset.name}';
    await service.onSelectInterface!(preset);
    await _settle(switch (preset) {
      InterfacePreset.synapseBlue => 8200,
      InterfacePreset.synapse2017 => 3500,
      InterfacePreset.synapseV3 => 3200,
      _ => 1200,
    });
    await waitForKinds(const {});
    final before = await windowManager.getBounds();
    geometry['${preset.name}.original'] = _bounds(before);
    final studioKind = CompanionThemeStudioKind.forPreset(preset);
    stage = '${preset.name}-open-studio';
    await service.open(studioKind);
    await waitForKinds({studioKind});
    var studio = (await _children()).single;
    var inspection = await _inspect(studio);
    _expect(
      inspection['renderedStudio'] == preset.name,
      'Wrong or missing Material Studio shell',
    );
    _expect(inspection['resizable'] == true, 'Studio is not resizable');
    _expectSize(
      _readBounds(inspection),
      const Size(1180, 760),
      'Studio initial dimensions',
    );
    await _expectMainSize(before.size);
    await service.open(studioKind);
    await waitForKinds({studioKind});
    _expect(
      (await _children()).single.windowId == studio.windowId,
      'Opening Studio twice duplicated its engine',
    );
    checks.add(
      '${preset.label}: standalone 1180×760 Material editor opens without resizing its source; repeat open focuses the same engine',
    );

    stage = '${preset.name}-apply-main-size';
    final customSize = Size(before.width + 80, before.height + 40);
    var document = SynapseThemeCatalog.defaults(preset)
        .copyWith(name: 'Native ${preset.name}')
        .withWindow(
          'main',
          SynapseStudioWindow(
            width: customSize.width,
            height: customSize.height,
            elements: {
              'executeButton': SynapseStudioElement(
                fill: 0xff244b75,
                foreground: 0xffeef6ff,
                x: 3,
                radius: 9,
              ),
            },
          ),
        );
    controller.setInterfacePreference(preset, 'themeStudio', document.toJson());
    await controller.flushPersistence();
    await _waitMainSize(customSize);
    inspection = await _waitTheme(studio, preset, document.name);
    geometry['${preset.name}.custom'] = _bounds(
      await windowManager.getBounds(),
    );
    _expect(
      (inspection['themes'] as Map)[preset.name]['windows']['main']['width'] ==
          customSize.width,
      'Applied theme did not propagate into the Studio controller',
    );
    checks.add(
      '${preset.label}: applying a document resizes its live main window and broadcasts the applied theme to the Studio engine',
    );

    final auxiliary = switch (preset) {
      InterfacePreset.synapseX => <CompanionWindowKind, String>{
        CompanionWindowKind.synapseXOptions: 'settings',
        CompanionWindowKind.synapseXHub: 'scriptHub',
        CompanionWindowKind.synapseXConsole: 'console',
      },
      InterfacePreset.synapse2017 => <CompanionWindowKind, String>{
        CompanionWindowKind.synapseOgSettings: 'settings',
        CompanionWindowKind.synapseOgHub: 'scriptHub',
        CompanionWindowKind.synapseOgConsole: 'console',
      },
      _ => <CompanionWindowKind, String>{},
    };
    if (auxiliary.isNotEmpty) {
      stage = '${preset.name}-auxiliary-windows';
      final expected = {studioKind};
      for (final kind in auxiliary.keys) {
        await service.open(kind);
        expected.add(kind);
        await waitForKinds(expected);
      }
      final children = await _children();
      _expect(
        children.length == 4,
        'Expected Studio plus three independent source windows',
      );
      final targetSizes = <String, Size>{};
      for (final child in children) {
        final kind = _kind(child);
        final id = auxiliary[kind];
        if (id == null) continue;
        final current = _readBounds(await _inspect(child));
        final target = Size(current.width + 48, current.height + 36);
        targetSizes[id] = target;
        document = document.withWindow(
          id,
          SynapseStudioWindow(width: target.width, height: target.height),
        );
      }
      controller.setInterfacePreference(
        preset,
        'themeStudio',
        document.toJson(),
      );
      await controller.flushPersistence();
      for (final child in children) {
        final id = auxiliary[_kind(child)];
        if (id == null) continue;
        final inspect = await _waitChildSize(child, targetSizes[id]!);
        await _waitTheme(child, preset, document.name);
        geometry['${preset.name}.$id'] = inspect['bounds'];
      }
      await _expectMainSize(customSize);
      checks.add(
        '${preset.label}: Options, Script Hub and Console resize independently while open beside Studio; main bounds stay fixed',
      );
    }
    stage = '${preset.name}-close-and-reopen';
    await studio.invokeMethod<void>('closeFromOwner');
    await waitForKinds(auxiliary.keys.toSet());
    await _expectMainSize(customSize);
    await service.open(studioKind);
    await waitForKinds({studioKind, ...auxiliary.keys});
    studio = (await _children()).singleWhere((w) => _kind(w) == studioKind);
    await _waitTheme(studio, preset, document.name);
    await service.closeAll();
    await waitForKinds(const {});
    await _expectMainSize(customSize);
    checks.add(
      '${preset.label}: close/reopen retains the theme; closing all companion engines leaves the resized source functional',
    );
  }

  CompanionWindowKind _kind(WindowController window) => CompanionWindowKind
      .values
      .byName((jsonDecode(window.arguments) as Map)['kind'] as String);
  Future<List<WindowController>> _children() async => [
    for (final window in await WindowController.getAll())
      if (window.windowId != service.window.windowId) window,
  ];
  Future<void> waitForKinds(Set<CompanionWindowKind> expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      final children = await _children();
      final actual = children.map(_kind).toList();
      if (actual.length == expected.length &&
          actual.toSet().containsAll(expected)) {
        return;
      }
      _expect(
        DateTime.now().isBefore(deadline),
        'Expected $expected, found $actual',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, Object?>> _inspect(WindowController child) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (true) {
      try {
        final raw = await WindowMethodChannel(
          _inspectorName(child.windowId),
          mode: ChannelMode.unidirectional,
        ).invokeMethod<Map>('inspect').timeout(const Duration(seconds: 2));
        final value = Map<String, Object?>.from(raw!);
        if (value['controllerReady'] == true) return value;
      } on Object {
        if (!DateTime.now().isBefore(deadline)) rethrow;
      }
      _expect(
        DateTime.now().isBefore(deadline),
        'Native child inspector not ready',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Rect _readBounds(Map<String, Object?> inspection) {
    final b = inspection['bounds']! as Map;
    return Rect.fromLTWH(
      (b['x'] as num).toDouble(),
      (b['y'] as num).toDouble(),
      (b['width'] as num).toDouble(),
      (b['height'] as num).toDouble(),
    );
  }

  Future<Map<String, Object?>> _waitTheme(
    WindowController child,
    InterfacePreset preset,
    String name,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (true) {
      final inspection = await _inspect(child);
      if ((inspection['themes'] as Map)[preset.name]['name'] == name) {
        return inspection;
      }
      _expect(
        DateTime.now().isBefore(deadline),
        'Theme snapshot did not reach child',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, Object?>> _waitChildSize(
    WindowController child,
    Size size,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (true) {
      final inspection = await _inspect(child);
      final bounds = _readBounds(inspection);
      if (_sameSize(bounds.size, size)) return inspection;
      _expect(
        DateTime.now().isBefore(deadline),
        'Child size expected $size, found ${bounds.size}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _waitMainSize(Size size) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (true) {
      final bounds = await windowManager.getBounds();
      if (_sameSize(bounds.size, size)) return;
      _expect(
        DateTime.now().isBefore(deadline),
        'Main size expected $size, found ${bounds.size}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _sameSize(Size a, Size b) =>
      (a.width - b.width).abs() <= 2 && (a.height - b.height).abs() <= 2;
  void _expectSize(Rect actual, Size expected, String label) => _expect(
    _sameSize(actual.size, expected),
    '$label expected $expected, found ${actual.size}',
  );
  Future<void> _expectMainSize(Size size) async =>
      _expectSize(await windowManager.getBounds(), size, 'Main dimensions');
  Future<void> _settle(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  void _expect(bool condition, String message) {
    if (!condition) throw StateError('$stage: $message');
  }
}
