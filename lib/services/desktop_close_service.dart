import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../state/orion_controller.dart';
import 'companion_window_service.dart';

/// Hides the desktop immediately, keeping its engine alive until edits are saved.
/// Repeated close requests share the same operation, including native WM_CLOSE.
class DesktopCloseService {
  DesktopCloseService({
    required this.hide,
    required this.persist,
    required this.destroy,
    required this.restore,
    this.flushEditor,
    this.closeCompanions,
    this.stopWindowChanges,
    this.closeBridge,
    this.cleanupTimeout = const Duration(seconds: 2),
    this.onCleanupError,
  });

  final Future<void> Function() hide, persist, destroy, restore;
  final Future<void> Function()? flushEditor, closeCompanions;
  final Future<void> Function()? stopWindowChanges, closeBridge;
  final Duration cleanupTimeout;
  final void Function(Object, StackTrace)? onCleanupError;
  Future<void>? _closing;

  static final _applications = Expando<DesktopCloseService>();

  static Future<void> closeApp({
    required OrionController controller,
    required bool nativeWindow,
    Future<void> Function()? flushEditor,
    Future<void> Function()? stopWindowChanges,
  }) {
    final companions = controller.companionWindows;
    final service = _applications[controller] ??= DesktopCloseService(
      hide: () async {
        if (nativeWindow) await windowManager.hide();
      },
      flushEditor: flushEditor,
      stopWindowChanges: stopWindowChanges,
      closeCompanions: () async {
        if (companions is CompanionWindowService && nativeWindow) {
          await companions.shutdown();
        } else {
          await companions?.closeAll();
        }
      },
      persist: () async {
        await controller.flushPersistence();
        final error = controller.persistenceError;
        if (error != null) throw StateError(error);
      },
      closeBridge: nativeWindow ? controller.closeBridge : null,
      destroy: () async {
        if (nativeWindow) await windowManager.destroy();
      },
      restore: () async {
        if (companions is CompanionWindowService) {
          await companions.cancelShutdown();
        }
        if (nativeWindow) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    return service.close().catchError((Object error, StackTrace stack) {
      if (identical(_applications[controller], service)) {
        _applications[controller] = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> close() {
    final pending = _closing;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closing = completion.future;
    unawaited(() async {
      try {
        await _close();
        completion.complete();
      } catch (error, stack) {
        _closing = null;
        completion.completeError(error, stack);
      }
    }());
    return completion.future;
  }

  Future<void> _bestEffort(Future<void> Function()? action) async {
    if (action == null) return;
    try {
      await action();
    } catch (error, stack) {
      if (onCleanupError != null) {
        onCleanupError!(error, stack);
      } else {
        debugPrint('Orion shutdown: $error');
      }
    }
  }

  Future<void> _close() async {
    // No animations, editor IPC or disk/network operations precede hiding.
    await _bestEffort(hide);
    try {
      await _bestEffort(
        stopWindowChanges == null
            ? null
            : () => stopWindowChanges!().timeout(cleanupTimeout),
      );
      await Future.wait<void>([
        // Monaco already bounds its acknowledgement wait. If its native host
        // has gone away, persist the latest edits received by the controller.
        _bestEffort(flushEditor),
        if (closeCompanions != null) closeCompanions!(),
      ]);
      await persist();
      // Disk persistence is complete. A stuck bridge must not hold the hidden
      // application alive indefinitely or retain its local listening socket.
      await _bestEffort(
        closeBridge == null
            ? null
            : () => closeBridge!().timeout(cleanupTimeout),
      );
      await destroy();
    } catch (_) {
      // A failed save leaves a usable window and allows the user to retry.
      await _bestEffort(restore);
      rethrow;
    }
  }
}
