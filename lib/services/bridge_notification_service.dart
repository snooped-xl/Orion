import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/orion_controller.dart';
import '../models/bridge_notification_content.dart';

/// A monitor's usable area in logical desktop coordinates, obtained from GTK's
/// monitor for Orion's actual native surface, rather than the pointer monitor.
@immutable
class BridgeNotificationMonitor {
  const BridgeNotificationMonitor(
    this.workArea, {
    this.backend = 'x11',
    this.devicePixelRatio = 1,
  });
  final Rect workArea;
  final String backend;
  final double devicePixelRatio;

  factory BridgeNotificationMonitor.fromJson(Map<Object?, Object?> value) {
    double number(String key, double fallback) {
      final n = value[key];
      return n is num && n.toDouble().isFinite ? n.toDouble() : fallback;
    }

    return BridgeNotificationMonitor(
      Rect.fromLTWH(
        number('x', 0),
        number('y', 0),
        number('width', 1920).clamp(240, 16384),
        number('height', 1080).clamp(160, 16384),
      ),
      backend: switch (value['backend']) {
        'windows' => 'windows',
        'macos' => 'macos',
        'wayland' => 'wayland',
        _ => 'x11',
      },
      devicePixelRatio: number('scale', 1).clamp(.5, 8).toDouble(),
    );
  }

  /// Leave compositor panels and a little breathing space around the card.
  Rect bounds({Size preferredSize = const Size(396, 120)}) {
    final width = preferredSize.width
        .clamp(200, workArea.width - 24)
        .toDouble();
    final height = preferredSize.height
        .clamp(80, workArea.height - 24)
        .toDouble();
    return Rect.fromLTWH(
      workArea.right - width - 12,
      workArea.top + 12,
      width,
      height,
    );
  }
}

abstract interface class BridgeNotificationNative {
  Future<BridgeNotificationMonitor> monitor();
  Future<void> fallback(
    String username,
    Rect bounds, {
    String executorName = '',
  });
}

class _NativeBridgeNotification implements BridgeNotificationNative {
  static const channel = MethodChannel('orion/bridge_notification');
  @override
  Future<BridgeNotificationMonitor> monitor() async =>
      BridgeNotificationMonitor.fromJson(
        await channel.invokeMapMethod<Object?, Object?>('monitor') ?? const {},
      );

  @override
  Future<void> fallback(
    String username,
    Rect bounds, {
    String executorName = '',
  }) => channel.invokeMethod<void>('notify', {
    'username': username,
    'subject': bridgeNotificationSubject(executorName),
    'x': bounds.right.round(),
    'y': bounds.top.round(),
  });
}

abstract interface class BridgeNotificationProcess {
  Future<int> get exitCode;
  void stop();
}

class _NativeNotificationProcess implements BridgeNotificationProcess {
  _NativeNotificationProcess(this.process) {
    // Workers are deliberately quiet. Always drain both pipes so an unexpected
    // GTK warning cannot block a toast or the queued connection announcements.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
  }
  final Process process;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  void stop() => process.kill();
}

typedef BridgeNotificationLauncher =
    Future<BridgeNotificationProcess> Function(Map<String, Object?> definition);

Future<BridgeNotificationProcess> _launchNotification(
  Map<String, Object?> definition,
) async => _NativeNotificationProcess(
  await Process.start(
    Platform.resolvedExecutable,
    ['--bridge-notification', jsonEncode(definition)],
    // GNOME Wayland does not let ordinary application windows request global
    // positions. An isolated XWayland surface can use the host monitor workarea
    // without changing Orion's backend or requiring a shell extension.
    environment: Platform.isLinux ? const {'GDK_BACKEND': 'x11'} : null,
  ),
);

/// Serializes join announcements across every Orion interface. The canonical
/// primary controller owns this service; companion engines never emit toasts.
class BridgeNotificationService {
  BridgeNotificationService(
    this.controller, {
    BridgeNotificationNative? native,
    BridgeNotificationLauncher? launch,
    bool? canLaunchWindow,
    this.workerTimeout = const Duration(seconds: 90),
    this.onError,
  }) : _native = native ?? _NativeBridgeNotification(),
       _launch = launch ?? _launchNotification,
       _canLaunchWindow =
           canLaunchWindow ??
           (Platform.isWindows ||
               Platform.isMacOS ||
               (Platform.isLinux &&
                   ((Platform.environment['DISPLAY']?.isNotEmpty ?? false) ||
                       (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ??
                           false))));

  final OrionController controller;
  final BridgeNotificationNative _native;
  final BridgeNotificationLauncher _launch;
  final bool _canLaunchWindow;

  /// Includes headroom for startup and the widget's one-minute hover watchdog.
  /// The owner also bounds workers that stall before rendering their first frame.
  final Duration workerTimeout;
  final void Function(Object error)? onError;
  final _queue = Queue<({String id, String username, String executorName})>();
  BridgeNotificationProcess? _activeProcess;
  String? _activeClient;
  bool _initialized = false, _disposed = false, _running = false;
  Completer<void>? _idle;

  Future<void> initialize() async {
    if (_disposed) return;
    _initialized = true;
    unawaited(_drain());
  }

  /// Pass a connection/session id, so two clients sharing a username remain
  /// separate. Duplicate events while that same session is queued are ignored.
  void notify({
    required String clientId,
    required String username,
    String executorName = '',
  }) {
    if (_disposed || clientId.trim().isEmpty) return;
    final clean = username.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (clean.isEmpty) return;
    if (_activeClient == clientId || _queue.any((e) => e.id == clientId)) {
      return;
    }
    final detectedExecutor = executorName
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    // A local connection flood must not retain an unbounded process queue.
    if (_queue.length >= 128) return;
    _queue.add((
      id: clientId,
      executorName: detectedExecutor.substring(
        0,
        detectedExecutor.length.clamp(0, 64),
      ),
      username: clean.substring(0, clean.length.clamp(0, 80)),
    ));
    _idle ??= Completer<void>();
    unawaited(_drain());
  }

  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();

  Future<void> _drain() async {
    if (!_initialized || _disposed || _running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final entry = _queue.removeFirst();
        _activeClient = entry.id;
        try {
          final monitor = await _native.monitor();
          if (_disposed) break;
          final bounds = monitor.bounds();
          if (!_canLaunchWindow) {
            await _native.fallback(
              entry.username,
              bounds,
              executorName: entry.executorName,
            );
            continue;
          }
          BridgeNotificationProcess process;
          try {
            process = await _launch({
              'type': 'orion-bridge-notification',
              'username': entry.username,
              'displayName': entry.username,
              'executorName': entry.executorName,
              'bounds': {
                'x': bounds.left,
                'y': bounds.top,
                'width': bounds.width,
                'height': bounds.height,
                if (monitor.backend == 'windows')
                  'scale': monitor.devicePixelRatio,
              },
              'theme': controller.orionTheme.toJson(),
              'brightness': controller.themeMode.name,
              'reducedMotion': controller.reducedMotion,
              'durationMs': 4000,
            });
          } catch (_) {
            if (!_disposed) {
              await _native.fallback(
                entry.username,
                bounds,
                executorName: entry.executorName,
              );
            }
            continue;
          }
          if (_disposed) {
            process.stop();
            break;
          }
          _activeProcess = process;
          int status;
          try {
            status = await process.exitCode.timeout(workerTimeout);
          } on TimeoutException {
            // A stalled renderer cannot run the widget's own expiry timer.
            // Stop its native allocation, then continue the announcement queue.
            process.stop();
            status = -1;
          } finally {
            if (identical(_activeProcess, process)) _activeProcess = null;
          }
          if (status != 0 && !_disposed) {
            await _native.fallback(
              entry.username,
              bounds,
              executorName: entry.executorName,
            );
          }
        } catch (error) {
          if (!_disposed) onError?.call(error);
        } finally {
          _activeClient = null;
        }
      }
    } finally {
      _running = false;
      if (_queue.isEmpty || _disposed) {
        _idle?.complete();
        _idle = null;
      } else {
        unawaited(_drain());
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _activeProcess?.stop();
    _activeProcess = null;
    if (_idle != null && !_idle!.isCompleted) _idle!.complete();
    _idle = null;
  }
}
