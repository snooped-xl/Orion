// Build this target on the desktop being tested. It exercises real native
// channels and child engines, which flutter_tester cannot provide.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:orion/main.dart' as launcher;
import 'package:orion/models/companion_window.dart';
import 'package:orion/models/interface_preset.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/services/native_window_service.dart';
import 'package:orion/services/orion_bridge_service.dart';
import 'package:orion/state/orion_controller.dart';
import 'package:orion/widgets/monaco_editor.dart';
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
  var success = false;
  String? failure;
  try {
    await report.parent.create(recursive: true);
    controller.completeIntro();
    await _until(() => _editor()?.ready == true, 'Monaco startup');
    var editor = _editor()!;
    _require(editor.error == null, 'Monaco reported ${editor.error}');
    await _until(() => editor.visible, 'Editor reveal');
    steps.add('native-monaco-ready');

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
    steps.add('native-edit-flush-undo-redo-capture');

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
    steps.add('workspace-files-and-bridge');

    await NativeWindowService.setAlwaysOnTop(true);
    _require(await windowManager.isAlwaysOnTop(), 'Native topmost');
    await NativeWindowService.setAlwaysOnTop(false);
    await NativeWindowService.setCornerRadius(24);
    final original = await windowManager.getBounds();
    await windowManager.setSize(
      Size(original.width + 20, original.height + 16),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final resized = await windowManager.getBounds();
    _require(resized.width > original.width + 10, 'Native window resize');
    await windowManager.setBounds(original);
    steps.add('native-window-sizing-topmost-corners');

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
    steps.add('companion-open-state-handshake-close');

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
      steps.add('interface-${preset.name}');
    }
    controller.setInterface(InterfacePreset.orion);
    for (final preset in OrionThemePreferences.builtInPresets) {
      controller.setOrionTheme(preset.preferences);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      steps.add('theme-${preset.id}');
    }
    await const MethodChannel('orion/rain').invokeMethod<void>('configure', {
      'enabled': true,
      'opacity': 1.0,
      'cornerRadius': 16.0,
      'reducedMotion': false,
    });
    await const MethodChannel('orion/rain').invokeMethod<void>('configure', {
      'enabled': false,
      'opacity': 1.0,
      'cornerRadius': 16.0,
    });
    steps.add('native-rain-shader-initialization');
    controller.resetOrionTheme();
    editor = _editor()!;
    await _until(() => editor.ready, 'Restored editor');
    await _bridge(controller);
    steps.add('real-loopback-bridge-client-execute-disconnect');
    await controller.flushPersistence();
    success = true;
  } catch (error, stack) {
    failure = '$error\n$stack';
    stderr.writeln(failure);
  } finally {
    await controller.companionWindows?.closeAll();
    await controller.closeBridge();
    await report.parent.create(recursive: true);
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'success': success,
        'platform': Platform.operatingSystem,
        'steps': steps,
        'failure': ?failure,
      }),
    );
    stdout.writeln('Desktop smoke: ${success ? "PASS" : "FAIL"}');
    exit(success ? 0 : 1);
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
