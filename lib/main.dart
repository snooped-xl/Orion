import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'bridge_notification_app.dart';
import 'companion_app.dart';
import 'models/interface_preset.dart';
import 'models/interface_window_profile.dart';
import 'services/bridge_notification_service.dart';
import 'services/companion_window_service.dart';
import 'services/crash_reporter.dart';
import 'services/native_window_service.dart';
import 'state/orion_controller.dart';

final _crashReporter = CrashReporter();

Future<void> main(List<String> arguments) async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (_crashReporter.supported) {
        FlutterError.onError = (details) {
          FlutterError.presentError(details);
          unawaited(
            _crashReporter.capture(
              details.exception,
              details.stack ?? StackTrace.current,
            ),
          );
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          unawaited(_crashReporter.capture(error, stack));
          return false;
        };
      }
      await runOrion(arguments);
    },
    (error, stack) {
      unawaited(_crashReporter.capture(error, stack));
      debugPrint('Uncaught Orion startup/runtime error: $error\n$stack');
    },
  );
}

Future<bool> _initializeWithRecovery(OrionController controller) async {
  try {
    await controller.initialize();
    return true;
  } on Object catch (error, stack) {
    unawaited(_crashReporter.capture(error, stack));
    final retry = await _showStartupRecovery(error);
    if (!retry) return false;
    try {
      await controller.initialize();
      return true;
    } on Object catch (retryError, retryStack) {
      unawaited(_crashReporter.capture(retryError, retryStack));
      await _showStartupRecovery(retryError);
      return false;
    }
  }
}

Future<bool> _showStartupRecovery(Object error) async {
  final result = Completer<bool>();
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      result.complete(false);
      return;
    }
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Orion didn’t set up correctly'),
        content: Text(
          'Startup failed: $error\n\nContinue will exit Orion. Fix retries initialization once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Fix'),
          ),
        ],
      ),
    );
    if (!result.isCompleted) result.complete(choice ?? false);
  });
  return result.future;
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
  final initialized = await _initializeWithRecovery(controller);
  if (!initialized) return null;
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
