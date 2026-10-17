// Build this target on the desktop being tested. It exercises real native
// channels and child engines, which flutter_tester cannot provide.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:orion/main.dart' as launcher;
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/native_window_service.dart';
import 'package:orion/services/orion_bridge_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/orion_glass.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> arguments) async {
  if (Platform.environment['ORION_WORKSPACE']?.trim().isNotEmpty != true) {
    stderr.writeln('Desktop smoke requires an isolated ORION_WORKSPACE.');
    exit(2);
  }
  final controller = await launcher.runOrion(arguments);
  // Child engines and notification workers use their normal production paths.
  if (controller == null) return;
  final reportIndex = arguments.indexOf('--report');
  final report = File(
    reportIndex >= 0 && reportIndex + 1 < arguments.length
        ? arguments[reportIndex + 1]
        : '${controller.workspaceDirectory.path}/desktop-smoke.json',
  );
  final steps = <String>[];
  final frameworkErrors = <String>[];
  var success = false;
  String? failure;
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    frameworkErrors.add(details.toString());
    previousFlutterError?.call(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    frameworkErrors.add('$error\n$stack');
    stderr.writeln('$error\n$stack');
    return true;
  };
  Future<void> writeReport() async {
    await report.parent.create(recursive: true);
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'success': success,
        'platform': Platform.operatingSystem,
        'steps': steps,
        'frameworkErrors': frameworkErrors,
        'failure': ?failure,
      }),
      flush: true,
    );
  }

  Future<void> step(String name) async {
    _require(frameworkErrors.isEmpty, frameworkErrors.join('\n'));
    steps.add(name);
    stdout.writeln('Desktop smoke: $name');
    await writeReport();
  }

  try {
    await writeReport();
    controller.completeIntro();
    await _until(() => _editor()?.ready == true, 'Monaco startup');
    var editor = _editor()!;
    _require(editor.error == null, 'Monaco reported ${editor.error}');
    await _until(() => editor.visible, 'Editor reveal');
    await step('native-monaco-ready');

    const source = 'print("Orion desktop smoke")';
    await editor.action('clear');
    await editor.action('paste', text: source);
    await editor.flush();
    _require(controller.activeDocument.content == source, 'Native edit/flush');
    await editor.action('selectAll');
    await editor.action('undo');
    await editor.action('redo');
    await editor.flush();
    _require(controller.activeDocument.content == source, 'Native undo/redo');
    final preview = await editor.capturePreview();
    _require(preview != null && preview.length > 256, 'Native editor capture');
    await File('${report.parent.path}/monaco-smoke.png').writeAsBytes(preview!);
    await step('native-edit-flush-undo-redo-capture');

    await controller.saveDocumentToPath(
      controller.activeDocumentId,
      '${controller.scriptsDirectory.path}/Smoke.lua',
    );
    _require(
      await File(
            '${controller.scriptsDirectory.path}/Smoke.lua',
          ).readAsString() ==
          source,
      'Writable scripts folder',
    );
    _require(
      await File(
        '${controller.scriptsDirectory.path}/Special/Orion Bridge.lua',
      ).exists(),
      'Bundled bridge provisioning',
    );
    await step('workspace-files-and-bridge');

    controller.setAlwaysOnTop(true);
    await _until(
      () => windowManager.isAlwaysOnTop(),
      'Native topmost preference',
    );
    controller.setAlwaysOnTop(false);
    await _until(
      () async => !await windowManager.isAlwaysOnTop(),
      'Native topmost reset',
    );
    await NativeWindowService.setCornerRadius(24);
    final original = await windowManager.getBounds();
    await windowManager.setSize(
      Size(original.width + 20, original.height + 16),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final resized = await windowManager.getBounds();
    _require(resized.width > original.width + 10, 'Native window resize');
    await windowManager.setBounds(original);
    await step('native-window-sizing-topmost-corners');

    final windowsBefore = (await WindowController.getAll()).length;
    await controller.companionWindows!.open(
      CompanionWindowKind.synapseXOptions,
    );
    _require(
      (await WindowController.getAll()).length > windowsBefore,
      'Independent options engine',
    );
    await controller.companionWindows!.closeAll();
    await _until(
      () async => (await WindowController.getAll()).length == windowsBefore,
      'Companion destruction',
    );
    await step('companion-open-state-handshake-close');

    for (final preset in InterfacePresetDetails.available) {
      controller.setInterface(preset);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // Several historical interfaces intentionally start at a local login or
      // home view. Their shared native editor remains initialized while hidden.
      _require(
        editor.ready && editor.error == null,
        '${preset.label} native host',
      );
      _require(await windowManager.isVisible(), '${preset.label} window');
      await step('interface-${preset.name}');
    }
    controller.setInterface(InterfacePreset.orion);
    for (final preset in OrionThemePreferences.builtInPresets) {
      controller.setOrionTheme(preset.preferences);
      await _themeFrame(controller, report.parent, 'theme-${preset.id}');
      await step('theme-${preset.id}');
    }
    final glass = OrionThemePreferences.builtInPresets
        .firstWhere((preset) => preset.id == 'liquid-glass')
        .preferences;
    final blueGlass = OrionThemePreferences.builtInPresets
        .firstWhere((preset) => preset.id == 'blue-glass')
        .preferences;
    // Repeat the transition that changes the layered HWND, Flutter shaders,
    // native editor presentation and rain resources while frames are active.
    for (var cycle = 0; cycle < 3; cycle++) {
      controller.setOrionTheme(glass.copyWith(windowOpacity: .5));
      await _themeFrame(controller, report.parent, 'glass-low-$cycle');
      controller.setOrionTheme(
        blueGlass.copyWith(windowOpacity: 1, rainEnabled: true),
      );
      await _themeFrame(controller, report.parent, 'glass-rain-$cycle');
      await windowManager.setSize(
        Size(original.width + 24, original.height + 20),
      );
      await _themeFrame(controller, report.parent, 'glass-resized-$cycle');
      await windowManager.setBounds(original);
      controller.resetOrionTheme();
      await _themeFrame(controller, report.parent, 'opaque-restored-$cycle');
      await step('glass-opacity-rain-resize-opaque-cycle-$cycle');
    }
    await const MethodChannel('orion/rain').invokeMethod<void>('configure', {
      'enabled': true,
      'opacity': 1.0,
      'cornerRadius': 16.0,
      'reducedMotion': false,
    });
    if (Platform.isWindows) {
      var rejected = false;
      try {
        await const MethodChannel('orion/rain').invokeMethod<void>('frame', {
          'png': Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        });
      } on PlatformException catch (error) {
        rejected = error.code == 'invalid_frame';
      }
      _require(rejected, 'Malformed native rain frame rejected safely');
      await step('native-rain-rejects-truncated-png');
    }
    await const MethodChannel('orion/rain').invokeMethod<void>('configure', {
      'enabled': false,
      'opacity': 1.0,
      'cornerRadius': 16.0,
    });
    await step('native-rain-shader-initialization');
    controller.resetOrionTheme();
    editor = _editor()!;
    await _until(() => editor.ready, 'Restored editor');
    await _bridge(controller);
    await step('real-loopback-bridge-client-execute-disconnect');
    // Keep graphics resources and a child engine alive at close. Calling exit()
    // here used to skip the native teardown that crashed the shipped build.
    controller.setOrionTheme(blueGlass.copyWith(rainEnabled: true));
    await _themeFrame(controller, report.parent, 'glass-before-close');
    await controller.companionWindows!.open(
      CompanionWindowKind.synapseXOptions,
    );
    await controller.flushPersistence();
    await step('production-close-requested-with-glass-and-companion');
    success = true;
  } catch (error, stack) {
    failure = '$error\n$stack';
    stderr.writeln(failure);
  } finally {
    await writeReport();
    stdout.writeln(
      'Desktop smoke: ${success ? "checks passed; closing" : "FAIL"}',
    );
    Timer(const Duration(seconds: 15), () async {
      success = false;
      failure =
          '${failure ?? ""}\nProduction close did not terminate in 15 seconds.';
      await writeReport();
      exit(1);
    });
    // Use the same close listener, persistence and native destruction as the
    // titlebar/WM_CLOSE. The external runner must also observe a clean exit.
    await windowManager.close();
  }
}

Future<void> _themeFrame(
  OrionController controller,
  Directory output,
  String name,
) async {
  if (controller.orionTheme.liquidGlassEnabled) {
    await OrionGlassScene.preload().timeout(const Duration(seconds: 25));
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  await _until(() => _editor()?.ready == true, '$name editor ready');
  final editor = _editor()!;
  _require(editor.error == null, '$name native editor: ${editor.error}');
  await _until(() => editor.visible, '$name editor visible');
  _require(await windowManager.isVisible(), '$name visible window');
  if (editor.visualMirror) {
    await _until(
      () => editor.visualMirrorFrame.value != null,
      '$name native editor mirror',
    );
  }
  final preview = await editor.capturePreview();
  _require(
    preview != null && preview.length > 256,
    '$name native editor frame',
  );
  await editor.flush();
  _require(
    controller.activeDocument.content.isNotEmpty,
    '$name editor content',
  );
  await WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 15));
  RenderRepaintBoundary? largest;
  void visit(RenderObject object) {
    if (object is RenderRepaintBoundary &&
        object.hasSize &&
        (largest == null ||
            object.size.width * object.size.height >
                largest!.size.width * largest!.size.height)) {
      largest = object;
    }
    object.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  _require(largest != null, '$name Flutter capture boundary');
  // Read back an actual rasterized frame, so a UI-isolate delay alone cannot
  // mark a stalled shader/render thread as a passing theme transition.
  final image = await largest!
      .toImage(pixelRatio: .5)
      .timeout(const Duration(seconds: 15));
  try {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    _require(pixels != null, '$name Flutter pixels');
    final colors = <int>{};
    for (var offset = 0; offset + 4 <= pixels!.lengthInBytes; offset += 404) {
      colors.add(pixels.getUint32(offset));
      if (colors.length > 8) break;
    }
    _require(colors.length > 8, '$name Flutter frame is not blank');
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    _require(png != null && png.lengthInBytes > 256, '$name Flutter frame');
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

MonacoEditorService? _editor() {
  MonacoEditorService? service;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is MonacoEditor && (service == null || widget.active)) {
      service = widget.service;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return service;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _until(
  FutureOr<bool> Function() condition,
  String operation,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(operation);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _bridge(OrionController controller) async {
  await _until(() => controller.bridgeListening, 'Bridge listener');
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  Future<Map<String, dynamic>> request(String path, {Object? body}) async {
    final uri = Uri.http('127.0.0.1:${controller.bridgePort}', path, {
      'protocol': OrionBridgeService.protocolToken,
      'session_id': 'desktop-smoke',
    });
    final request = await client.openUrl(body == null ? 'GET' : 'POST', uri);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    _require(
      response.statusCode == 200,
      '$path returned ${response.statusCode}',
    );
    return jsonDecode(text) as Map<String, dynamic>;
  }

  try {
    await request(
      '/port_bridge/hello',
      body: {
        'session_id': 'desktop-smoke',
        'display_name': 'Desktop Smoke',
        'username': 'desktop_smoke_code_name',
        'executor_name': 'Smoke Fixture',
        'client': 'release-smoke',
      },
    );
    _require(
      controller.bridgeClients.single.displayName == 'Desktop Smoke',
      'Display name identification',
    );
    controller.execute();
    final next = await request('/port_bridge/next');
    _require(next['exec'] is Map, 'Bridge execution dispatch');
    controller.disconnectBridgeClient(
      controller.bridgeClients.single.identifier,
    );
    _require(controller.bridgeClients.isEmpty, 'Bridge disconnect');
  } finally {
    client.close(force: true);
  }
}
