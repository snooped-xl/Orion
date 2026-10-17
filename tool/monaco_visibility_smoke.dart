// Uses desktop pixels, rather than WebView's independent offscreen snapshots.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:orion/main.dart' as launcher;
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/desktop_close_service.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> arguments) async {
  final workspace = Platform.environment['ORION_WORKSPACE'];
  final helper = Platform.environment['ORION_MONACO_VISIBLE_HELPER'];
  final destination = Platform.environment['ORION_MONACO_VISIBLE_OUTPUT'];
  if (workspace == null || helper == null || destination == null) exit(2);
  final output = Directory(destination);
  await output.create(recursive: true);
  final report = File('${output.path}/report.json');
  await report.writeAsString('{"success":false}');
  final cases = <Map<String, Object?>>[];
  final controller = await launcher.runOrion(arguments);
  if (controller == null) return;
  var success = false;
  String? failure;
  try {
    // A cold-start check must run before clear/paste/focus actions can repair
    // the browser or change the native stacking that is under investigation.
    await _until(() => _editor()?.service.ready == true, 'editor startup');
    await _until(() => _editor()?.service.visible == true, 'editor reveal');
    Future<void> check(String name) async {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final element = _editorElement()!;
      final editor = element.widget as MonacoEditor;
      final box = element.findRenderObject()! as RenderBox;
      final local = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      final origin = await windowManager.getPosition();
      final ratio = View.of(element).devicePixelRatio;
      final rectangle = local.shift(origin);
      final path = '${output.path}/$name.${Platform.isWindows ? 'bmp' : 'png'}';
      final geometry = [
        (rectangle.left * ratio).round(),
        (rectangle.top * ratio).round(),
        (rectangle.width * ratio).round(),
        (rectangle.height * ratio).round(),
      ].map((value) => '$value').toList();
      Future<ProcessResult> probe() => Platform.isWindows
          ? Process.run(helper, ['$pid', path, ...geometry])
          : Process.run('/usr/bin/python3', [
              helper,
              '--pid',
              '$pid',
              '--output',
              path,
              '--x',
              geometry[0],
              '--y',
              geometry[1],
              '--width',
              geometry[2],
              '--height',
              geometry[3],
            ]);
      var result = await probe();
      for (var retry = 0; result.exitCode == 3 && retry < 2; retry++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        result = await probe();
      }
      final frame = editor.service.visualMirrorFrame.value?.clone();
      int? maximumAlpha;
      if (frame != null) {
        final bytes = await frame.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        var maximum = 0;
        if (bytes != null) {
          for (var offset = 3; offset < bytes.lengthInBytes; offset += 4) {
            final value = bytes.getUint8(offset);
            if (value > maximum) maximum = value;
          }
        }
        maximumAlpha = maximum;
        final png = await frame.toByteData(format: ui.ImageByteFormat.png);
        if (png != null) {
          await File('${output.path}/$name-mirror.png').writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
        }
        frame.dispose();
      }
      cases.add({
        'name': name,
        'mirror': editor.service.visualMirror,
        'mirrorMaximumAlpha': maximumAlpha,
        'bounds': geometry,
        'exitCode': result.exitCode,
        'stdout': '${result.stdout}',
        'stderr': '${result.stderr}',
      });
      stdout.writeln('$name: ${result.stdout}${result.stderr}');
      if (result.exitCode != 0) throw StateError('$name text is not visible');
    }

    await check('cold-expressive');
    for (final name in [
      'liquid-glass',
      'blue-glass',
      'material-rain',
      'expressive',
    ]) {
      final preset = OrionThemePreferences.builtInPresets.firstWhere(
        (preset) => preset.id == name,
      );
      controller.setOrionTheme(preset.preferences);
      await _until(() => _editor()?.service.visible == true, '$name reveal');
      await check(name);
    }
    final editor = _editor()!.service;
    await editor.freezeForOverlay(owner: 'visible-test');
    editor.setObscured(false, owner: 'visible-test');
    await check('after-overlay');
    await windowManager.minimize();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await windowManager.restore();
    await windowManager.show();
    await check('after-restore');
    success = true;
  } catch (error, stack) {
    failure = '$error\n$stack';
    stderr.writeln(failure);
  } finally {
    await report.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'success': success, 'cases': cases, 'failure': failure}),
    );
    await DesktopCloseService.closeApp(
      controller: controller,
      nativeWindow: true,
      flushEditor: () async => _editor()?.service.flush(),
    );
  }
}

Element? _editorElement() {
  Element? result;
  void visit(Element element) {
    if (element.widget case MonacoEditor(active: true)) result = element;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}

MonacoEditor? _editor() => _editorElement()?.widget as MonacoEditor?;

Future<void> _until(bool Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(description);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
