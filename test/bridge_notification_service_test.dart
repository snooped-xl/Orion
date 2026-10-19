import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/services/bridge_notification_service.dart';
import 'package:orion/state/orion_controller.dart';

class _Native implements BridgeNotificationNative {
  _Native({this.backend = 'wayland', this.scale = 1});
  final String backend;
  final double scale;
  final List<({String username, Rect bounds})> fallbacks = [];
  final List<Rect> areas = [];
  final List<String> fallbackExecutors = [];
  int monitorCalls = 0;
  Completer<BridgeNotificationMonitor>? pending;
  @override
  Future<BridgeNotificationMonitor> monitor() async {
    final i = monitorCalls++;
    if (pending != null) return pending!.future;
    return BridgeNotificationMonitor(
      areas.isEmpty
          ? const Rect.fromLTWH(1920, 32, 2560, 1408)
          : areas[i.clamp(0, areas.length - 1)],
      backend: backend,
      devicePixelRatio: scale,
    );
  }

  @override
  Future<void> fallback(
    String username,
    Rect bounds, {
    String executorName = '',
  }) async {
    fallbacks.add((username: username, bounds: bounds));
    fallbackExecutors.add(executorName);
  }
}

class _Process implements BridgeNotificationProcess {
  final completed = Completer<int>();
  bool stopped = false;
  @override
  Future<int> get exitCode => completed.future;
  @override
  void stop() {
    stopped = true;
    if (!completed.isCompleted) completed.complete(-15);
  }
}

class _StuckProcess implements BridgeNotificationProcess {
  final completed = Completer<int>();
  bool stopped = false;
  @override
  Future<int> get exitCode => completed.future;
  @override
  void stop() => stopped = true;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('top right uses actual monitor workarea including negative origins', () {
    final monitor = BridgeNotificationMonitor.fromJson({
      'x': -2560,
      'y': 48,
      'width': 2560,
      'height': 1392,
      'backend': 'wayland',
    });
    expect(monitor.bounds(), const Rect.fromLTWH(-408, 60, 396, 120));
    expect(monitor.backend, 'wayland');
    final macosMonitor = BridgeNotificationMonitor.fromJson({
      'x': 0,
      'y': 25,
      'width': 1512,
      'height': 957,
      'backend': 'macos',
      'scale': 2,
    });
    expect(macosMonitor.backend, 'macos');
    expect(macosMonitor.devicePixelRatio, 2);
    expect(macosMonitor.bounds(), const Rect.fromLTWH(1104, 37, 396, 120));
    final small = const BridgeNotificationMonitor(
      Rect.fromLTWH(0, 0, 240, 160),
    );
    expect(small.bounds(), const Rect.fromLTWH(12, 12, 216, 120));
  });

  test('Windows target monitor keeps its scale for the separate worker', () {
    final monitor = BridgeNotificationMonitor.fromJson({
      'x': -1280,
      'y': 0,
      'width': 1280,
      'height': 720,
      'backend': 'windows',
      'scale': 1.5,
    });
    expect(monitor.backend, 'windows');
    expect(monitor.devicePixelRatio, 1.5);
    expect(monitor.bounds(), const Rect.fromLTWH(-408, 12, 396, 120));
    expect(
      BridgeNotificationMonitor.fromJson({
        'scale': double.nan,
      }).devicePixelRatio,
      1,
    );
  });

  test(
    'Windows worker receives target monitor DPI independently of its own',
    () async {
      final c = OrionController(persistChanges: false);
      final process = _Process();
      Map<String, Object?>? definition;
      final service = BridgeNotificationService(
        c,
        native: _Native(backend: 'windows', scale: 1.5),
        canLaunchWindow: true,
        launch: (value) async {
          definition = value;
          return process;
        },
      );
      await service.initialize();
      service.notify(clientId: 'dpi', username: 'Player');
      await _flush();
      expect((definition!['bounds'] as Map)['scale'], 1.5);
      process.completed.complete(0);
      await service.whenIdle;
      service.dispose();
      c.dispose();
    },
  );

  test('malformed monitor input falls back to finite usable geometry', () {
    final monitor = BridgeNotificationMonitor.fromJson({
      'x': double.nan,
      'y': double.infinity,
      'width': -50,
      'height': 'invalid',
    });
    expect(monitor.workArea, const Rect.fromLTWH(0, 0, 240, 1080));
    expect(monitor.bounds().right, 228);
  });

  test(
    'joins wait for initialization and each gets a separate queued toast',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final definitions = <Map<String, Object?>>[];
      final processes = <_Process>[];
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: true,
        launch: (definition) async {
          definitions.add(definition);
          final process = _Process();
          processes.add(process);
          return process;
        },
      );
      service.notify(
        clientId: 'a',
        username: 'First',
        executorName: '  LiveExecutor  ',
      );
      service.notify(clientId: 'b', username: 'Second');
      expect(definitions, isEmpty);
      await service.initialize();
      await _flush();
      expect(definitions.map((d) => d['username']), ['First']);
      expect(definitions.first['executorName'], 'LiveExecutor');
      expect(definitions.first.containsKey('executorVersion'), false);
      expect(definitions.first['bounds'], {
        'x': 4072.0,
        'y': 44.0,
        'width': 396.0,
        'height': 120.0,
      });
      processes.first.completed.complete(0);
      await _flush();
      expect(definitions.map((d) => d['username']), ['First', 'Second']);
      processes.last.completed.complete(0);
      await service.whenIdle;
      service.dispose();
      c.dispose();
    },
  );

  test(
    'same username on separate sessions is announced, duplicate queued session is not',
    () async {
      final c = OrionController(persistChanges: false);
      final processes = <_Process>[];
      final service = BridgeNotificationService(
        c,
        native: _Native(),
        canLaunchWindow: true,
        launch: (_) async {
          final process = _Process();
          processes.add(process);
          return process;
        },
      );
      await service.initialize();
      service.notify(clientId: 'first', username: 'Player');
      service.notify(clientId: 'first', username: 'Player');
      service.notify(clientId: 'second', username: 'Player');
      await _flush();
      expect(processes, hasLength(1));
      processes.first.completed.complete(0);
      await _flush();
      expect(processes, hasLength(2));
      processes.last.completed.complete(0);
      await service.whenIdle;
      service.notify(clientId: 'first', username: 'Player');
      await _flush();
      expect(processes, hasLength(3));
      processes.last.completed.complete(0);
      await service.whenIdle;
      service.dispose();
      c.dispose();
    },
  );

  test(
    'queued joins pick up moved monitor and latest theme preferences',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native()
        ..areas.addAll([
          const Rect.fromLTWH(0, 32, 1920, 1048),
          const Rect.fromLTWH(-1920, 0, 1920, 1080),
        ]);
      final definitions = <Map<String, Object?>>[];
      final processes = <_Process>[];
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: true,
        launch: (definition) async {
          definitions.add(definition);
          final process = _Process();
          processes.add(process);
          return process;
        },
      );
      await service.initialize();
      service.notify(clientId: 'a', username: 'One');
      service.notify(clientId: 'b', username: 'Two');
      await _flush();
      c.setOrionTheme(OrionThemePreferences(accent: Colors.orange));
      c.setReducedMotion(true);
      processes.first.completed.complete(0);
      await _flush();
      expect(definitions.last['bounds'], {
        'x': -408.0,
        'y': 12.0,
        'width': 396.0,
        'height': 120.0,
      });
      expect(definitions.last['theme'], c.orionTheme.toJson());
      expect(definitions.last['reducedMotion'], true);
      processes.last.completed.complete(0);
      await service.whenIdle;
      service.dispose();
      c.dispose();
    },
  );

  test(
    'desktop fallback preserves the executor subject and player display name',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: false,
      );
      await service.initialize();
      service.notify(
        clientId: 'display-name-session',
        username: 'Galactic Friend',
        executorName: 'LiveExecutor',
      );
      await service.whenIdle;
      expect(native.fallbacks.single.username, 'Galactic Friend');
      expect(native.fallbackExecutors.single, 'LiveExecutor');
      service.dispose();
      c.dispose();
    },
  );

  test(
    'native fallback channel carries the formatted subject and display name',
    () async {
      const channel = MethodChannel('orion/bridge_notification');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'monitor') {
              return {'x': 0, 'y': 0, 'width': 1920, 'height': 1080};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final c = OrionController(persistChanges: false);
      final service = BridgeNotificationService(c, canLaunchWindow: false);
      await service.initialize();
      service.notify(
        clientId: 'native-display-session',
        username: 'Galactic Friend',
        executorName: 'LiveExecutor',
      );
      await service.whenIdle;
      final notification =
          calls.singleWhere((call) => call.method == 'notify').arguments as Map;
      expect(notification['username'], 'Galactic Friend');
      expect(notification['subject'], 'Executor Connected! (LiveExecutor)');
      expect(notification.containsKey('executorVersion'), false);
      service.dispose();
      c.dispose();
    },
  );

  test(
    'compositors without XWayland use passive freedesktop notification',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: false,
        launch: (_) => throw StateError('must not spawn'),
      );
      await service.initialize();
      service.notify(clientId: 'a', username: 'No XWayland');
      await service.whenIdle;
      expect(native.fallbacks.single.username, 'No XWayland');
      service.dispose();
      c.dispose();
    },
  );

  test('failed worker falls back and next join still appears', () async {
    final c = OrionController(persistChanges: false);
    final native = _Native();
    final service = BridgeNotificationService(
      c,
      native: native,
      canLaunchWindow: true,
      launch: (_) async {
        final process = _Process()..completed.complete(1);
        return process;
      },
    );
    await service.initialize();
    service.notify(clientId: 'a', username: 'One');
    service.notify(clientId: 'b', username: 'Two');
    await service.whenIdle;
    expect(native.fallbacks.map((f) => f.username), ['One', 'Two']);
    service.dispose();
    c.dispose();
  });

  test('worker launch failure falls back without breaking the queue', () async {
    final c = OrionController(persistChanges: false);
    final native = _Native();
    final service = BridgeNotificationService(
      c,
      native: native,
      canLaunchWindow: true,
      launch: (_) async => throw StateError('No X server'),
    );
    await service.initialize();
    service.notify(clientId: 'a', username: 'One');
    service.notify(clientId: 'b', username: 'Two');
    await service.whenIdle;
    expect(native.fallbacks.map((f) => f.username), ['One', 'Two']);
    service.dispose();
    c.dispose();
  });

  test(
    'stalled worker is stopped, falls back, and releases queued joins',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final stuck = _StuckProcess();
      var launches = 0;
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: true,
        workerTimeout: const Duration(milliseconds: 20),
        launch: (_) async {
          launches++;
          if (launches == 1) return stuck;
          return _Process()..completed.complete(0);
        },
      );
      await service.initialize();
      service.notify(clientId: 'a', username: 'Stalled');
      service.notify(clientId: 'b', username: 'Next');
      await service.whenIdle.timeout(const Duration(seconds: 1));
      expect(stuck.stopped, true);
      expect(native.fallbacks.map((f) => f.username), ['Stalled']);
      expect(launches, 2);
      service.dispose();
      c.dispose();
    },
  );

  test(
    'dispose suppresses fallback even when a stopped worker never exits',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final stuck = _StuckProcess();
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: true,
        workerTimeout: const Duration(milliseconds: 20),
        launch: (_) async => stuck,
      );
      await service.initialize();
      service.notify(clientId: 'a', username: 'Stalled');
      await _flush();
      service.dispose();
      await service.whenIdle;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(stuck.stopped, true);
      expect(native.fallbacks, isEmpty);
      c.dispose();
    },
  );

  test('empty names ignored and username control characters removed', () async {
    final c = OrionController(persistChanges: false);
    final native = _Native();
    final service = BridgeNotificationService(
      c,
      native: native,
      canLaunchWindow: false,
    );
    await service.initialize();
    service.notify(clientId: '', username: 'Someone');
    service.notify(clientId: 'a', username: '\t\n');
    service.notify(clientId: 'b', username: ' Player\nName\t ');
    await service.whenIdle;
    expect(native.fallbacks.single.username, 'PlayerName');
    service.dispose();
    c.dispose();
  });

  test(
    'dispose cancels worker and pending queue without fallback or late launch',
    () async {
      final c = OrionController(persistChanges: false);
      final native = _Native();
      final process = _Process();
      int launches = 0;
      final service = BridgeNotificationService(
        c,
        native: native,
        canLaunchWindow: true,
        launch: (_) async {
          launches++;
          return process;
        },
      );
      await service.initialize();
      service.notify(clientId: 'a', username: 'One');
      service.notify(clientId: 'b', username: 'Two');
      await _flush();
      service.dispose();
      await service.whenIdle;
      await _flush();
      expect(process.stopped, true);
      expect(launches, 1);
      expect(native.fallbacks, isEmpty);
      service.notify(clientId: 'c', username: 'Three');
      await service.initialize();
      await _flush();
      expect(launches, 1);
      c.dispose();
    },
  );

  test('dispose while waiting for monitor never launches worker', () async {
    final c = OrionController(persistChanges: false);
    final native = _Native()..pending = Completer<BridgeNotificationMonitor>();
    int launches = 0;
    final service = BridgeNotificationService(
      c,
      native: native,
      canLaunchWindow: true,
      launch: (_) async {
        launches++;
        return _Process();
      },
    );
    await service.initialize();
    service.notify(clientId: 'a', username: 'One');
    service.dispose();
    native.pending!.complete(
      const BridgeNotificationMonitor(Rect.fromLTWH(0, 0, 1920, 1080)),
    );
    await _flush();
    expect(launches, 0);
    c.dispose();
  });
}
