// Run over the native helper's controlled desktop in an isolated workspace.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:orion/main.dart' as launcher;
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> arguments) async {
  if (Platform.environment['ORION_WORKSPACE'] == null ||
      Platform.environment['ORION_GLASS_TEST_HELPER'] == null ||
      Platform.environment['ORION_GLASS_TEST_OUTPUT'] == null)
    exit(2);
  final output = Directory(Platform.environment['ORION_GLASS_TEST_OUTPUT']!);
  await output.create(recursive: true);
  final report = File('${output.path}/report.json');
  await report.writeAsString('{"success":false}');
  final cases = <Map<String, Object?>>[];
  final controller = await launcher.runOrion(arguments);
  if (controller == null) return;
  try {
    controller.completeIntro();
    await const MethodChannel(
      'orion/window',
    ).invokeMethod<String>('completeStartupPlacement');
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final theme in ['liquid-glass', 'blue-glass']) {
      final preset = OrionThemePreferences.builtInPresets.firstWhere(
        (p) => p.id == theme,
      );
      controller.setOrionTheme(preset.preferences);
      await Future<void>.delayed(const Duration(seconds: 3));
      final raw = await const MethodChannel('orion/window')
          .invokeMethod<String>('configureDesktopGlass', {
            'enabled': true,
            'cornerRadius': 24.0,
          });
      if (jsonDecode(raw!)['active'] != true) throw StateError(raw);
      final result = await Process.run(
        Platform.environment['ORION_GLASS_TEST_HELPER']!,
        ['--app', '$pid', '${output.path}/$theme.bmp'],
      );
      stdout.writeln(result.stdout);
      cases.add({
        'theme': theme,
        'exitCode': result.exitCode,
        'stdout': '${result.stdout}',
        'stderr': '${result.stderr}',
      });
      if (result.exitCode != 0) throw StateError('${result.stderr}');
    }
    await report.writeAsString(jsonEncode({'success': true, 'cases': cases}));
  } catch (error) {
    stderr.writeln(error);
    await report.writeAsString(
      jsonEncode({'success': false, 'error': '$error', 'cases': cases}),
    );
  }
  await windowManager.close();
}
