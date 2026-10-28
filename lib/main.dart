import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'state/orion_controller.dart';
import 'models/interface_window_profile.dart';
import 'models/interface_preset.dart';
import 'services/native_window_service.dart';
import 'services/companion_window_service.dart';
import 'dart:convert';
import 'companion_app.dart';
import 'bridge_notification_app.dart';
import 'services/bridge_notification_service.dart';
import 'app.dart';

Future<void> main(List<String> arguments) async {
  await runOrion(arguments);
}

/// Launch the normal application, or bootstrap its companion engine.
/// Separate developer targets can retain the primary controller after launch.
Future<OrionController?> runOrion(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.length >= 2 && arguments.first == '--bridge-notification') {
    await runBridgeNotificationWindow(
      Map<String, Object?>.from(jsonDecode(arguments[1]) as Map),
    );
    return null;
  }
  final window = (Platform.isLinux || Platform.isWindows)
      ? await WindowController.fromCurrentEngine()
      : null;
  if (window != null && window.arguments.isNotEmpty) {
    final definition = jsonDecode(window.arguments);
    if (definition is Map && definition['type'] == 'orion-companion') {
      await runCompanionWindow(window, Map<String, Object?>.from(definition));
      return null;
    }
  }
  // Snapshot the monitor under the pointer before asynchronous startup work.
  // Auxiliary engines and bridge notifications retain their own placement.
  if (Platform.isLinux || Platform.isWindows) {
    await NativeWindowService.prepareStartupPlacement();
  }
  final controller = OrionController();
  await controller.initialize();
  // macOS desktop widgets query window state as soon as OrionApp mounts. The
  // native window_manager plugin needs its NSWindow before those first queries.
  if (Platform.isMacOS) await windowManager.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows) {
    await windowManager.ensureInitialized();
    await CompanionWindowService(controller, window!).initialize();
    final icon = File(
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/branding/orion-icon.png',
    );
    if (Platform.isLinux && await icon.exists()) {
      await windowManager.setIcon(icon.path);
    }
    final profile = InterfaceWindowProfile.forInterface(
      controller,
      controller.selectedInterface,
      coldStart: true,
    );
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: profile.size,
        minimumSize: profile.minimumSize,
        center: false,
        backgroundColor: Colors.transparent,
        title: 'Orion',
        titleBarStyle: TitleBarStyle.hidden,
      ),
    );
    await NativeWindowService.setMinimumSize(profile.minimumSize);
    await NativeWindowService.setAlwaysOnTop(profile.alwaysOnTop);
    await NativeWindowService.setResizable(
      profile.resizable,
      size: profile.size,
    );
    await NativeWindowService.applyStartupPlacement(
      followInitialResize: const {
        InterfacePreset.synapseBlue,
        InterfacePreset.synapseX,
        InterfacePreset.synapse2017,
      }.contains(controller.selectedInterface),
    );
    await windowManager.show();
    await windowManager.focus();
  }
  runApp(
    OrionApp(
      controller: controller,
      showcase: arguments.contains('--showcase'),
      allowStartupUpdateCheck: !arguments.contains('--report'),
    ),
  );
  final notifications = BridgeNotificationService(controller);
  await notifications.initialize();
  final joins = controller.bridgeClientConnected.listen((client) {
    notifications.notify(
      clientId: client.sessionId,
      username: client.displayName,
      executorName: client.executorName,
    );
  });
  controller.bridgeShutdownHook = () async {
    await joins.cancel();
    notifications.dispose();
  };
  unawaited(controller.initializeBridge());
  unawaited(controller.searchRemoteScripts());
  return controller;
}
