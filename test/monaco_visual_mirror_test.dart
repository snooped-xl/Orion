import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _MirrorAssets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');
  @override
  Future<void> close() async {}
}

class _MirrorChannel extends MethodChannel {
  _MirrorChannel() : super('orion/mirror-test');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  Uint8List? png;
  Completer<Uint8List?>? gate;
  Completer<void>? captureResponse;
  Uint8List? lastResponse;
  int inFlight = 0, maximumInFlight = 0;

  int get captures => calls.where((c) => c.method == 'capturePreview').length;
  Iterable<MethodCall> get mirrorCalls =>
      calls.where((c) => c.method == 'setVisualMirror');

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  Future<void> message(Map<String, Object?> value) async {
    await handler?.call(MethodCall('message', jsonEncode(value)));
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(MethodCall(method, arguments));
    if (method == 'create') await message({'type': 'ready'});
    if (method == 'capturePreview') {
      final response = captureResponse = Completer<void>();
      inFlight++;
      if (inFlight > maximumInFlight) maximumInFlight = inFlight;
      try {
        final result = gate == null ? png : await gate!.future;
        lastResponse = result;
        return result as T?;
      } finally {
        inFlight--;
        response.complete();
      }
    }
    return null;
  }
}

MonacoEditorService _service(_MirrorChannel channel) => MonacoEditorService(
  channel: channel,
  server: _MirrorAssets(),
  onChange: (_, _) {},
  onShortcut: (_) {},
);

Future<void> _sync(
  MonacoEditorService service, {
  bool glass = true,
  double scale = 1,
}) => service.synchronize({
  'documents': [
    {'id': 'source', 'name': 'source.luau', 'content': 'print("native")'},
  ],
  'activeId': 'source',
  'options': {'compositorGlass': glass, 'uiScale': scale},
});

Widget _fixture(
  MonacoEditorService service, {
  double scale = 1,
  bool ticking = true,
}) => MaterialApp(
  builder: (_, child) => UiScaleViewport(scale: scale, child: child!),
  home: TickerMode(
    enabled: ticking,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20.3, 30.7, 40.1, 10.2),
      child: MonacoEditor(
        key: const ValueKey('editor'),
        service: service,
        active: true,
        backgroundColor: Colors.transparent,
      ),
    ),
  ),
);

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(1, 0, 1, 1), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 2);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _decode(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
}

Future<void> _awaitMirrorFrame(
  WidgetTester tester,
  MonacoEditorService service,
  ui.Image? previous,
) async {
  await tester.runAsync(() async {
    if (!identical(service.visualMirrorFrame.value, previous)) return;
    final complete = Completer<void>();
    void changed() {
      if (!identical(service.visualMirrorFrame.value, previous) &&
          !complete.isCompleted) {
        complete.complete();
      }
    }

    service.visualMirrorFrame.addListener(changed);
    try {
      await complete.future.timeout(const Duration(seconds: 5));
    } finally {
      service.visualMirrorFrame.removeListener(changed);
    }
  });
}

Future<void> _start(
  WidgetTester tester,
  MonacoEditorService service, {
  double scale = 1,
}) async {
  await _sync(service, scale: scale);
  await tester.pumpWidget(_fixture(service, scale: scale));
  await tester.pump();
  await tester.pump();
}

Future<void> _awaitCaptureResponse(
  WidgetTester tester,
  _MirrorChannel channel,
) async {
  await tester.runAsync(() async {
    await channel.captureResponse?.future;
    // Native bytes can be unchanged; their decode is deliberately skipped.
    // Allow a new/changed PNG's asynchronous codec to finish without requiring
    // ValueNotifier to publish a different image for identical pixels.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}

Future<void> _frame(
  WidgetTester tester,
  _MirrorChannel channel, {
  bool expectFrame = true,
}) async {
  final service = tester
      .widget<MonacoEditor>(find.byType(MonacoEditor))
      .service;
  final previous = service.visualMirrorFrame.value;
  final previousPng = channel.lastResponse;
  final before = channel.captures;
  await tester.pump(const Duration(milliseconds: 50));
  if (channel.captures == before && channel.inFlight == 0) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await _awaitCaptureResponse(tester, channel);
  if (expectFrame) {
    if (previous == null || !listEquals(previousPng, channel.lastResponse)) {
      await _awaitMirrorFrame(tester, service, previous);
    }
    expect(service.visualMirrorFrame.value, isNotNull);
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'first alpha frame paints before native suppression and refreshes independently',
    (tester) async {
      final red = await tester.runAsync(() => _png(Colors.red));
      final blue = await tester.runAsync(() => _png(Colors.blue));
      final channel = _MirrorChannel()..png = red;
      final service = _service(channel);
      try {
        await _start(tester, service);
        expect(channel.mirrorCalls, isEmpty);
        await tester.pump(const Duration(milliseconds: 50));
        await _awaitMirrorFrame(tester, service, null);
        final first = service.visualMirrorFrame.value!;
        // Publishing a decoded frame does not suppress native painting yet.
        expect(channel.mirrorCalls, isEmpty);
        final pixels = await tester.runAsync(() => first.toByteData());
        expect(pixels!.getUint8(3), 0);
        expect(pixels.getUint8(7), 255);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('monaco-visual-mirror')),
          findsOneWidget,
        );
        expect(channel.mirrorCalls.single.arguments, true);
        var workspaceNotifications = 0;
        service.addListener(() => workspaceNotifications++);
        final focusCount = channel.calls
            .where((c) => c.method == 'focus')
            .length;
        final syncCount = channel.calls.where((c) => c.method == 'send').length;
        channel.png = blue;
        await channel.message({'type': 'focus', 'focused': true});
        await _frame(tester, channel);
        expect(identical(service.visualMirrorFrame.value, first), false);
        expect(first.debugDisposed, true);
        expect(workspaceNotifications, 0);
        expect(service.frozenPreview, isNull);
        expect(
          channel.calls.where((c) => c.method == 'focus'),
          hasLength(focusCount),
        );
        expect(
          channel.calls.where((c) => c.method == 'send'),
          hasLength(syncCount),
        );
        expect(channel.maximumInFlight, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'identical PNG bytes retain the decoded image without notifications',
    (tester) async {
      final channel = _MirrorChannel()
        ..png = await tester.runAsync(() => _png(Colors.red));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel);
        final original = service.visualMirrorFrame.value!;
        var imageNotifications = 0;
        var workspaceNotifications = 0;
        service.visualMirrorFrame.addListener(() => imageNotifications++);
        service.addListener(() => workspaceNotifications++);

        // A platform-channel response is a new byte buffer, even when the
        // underlying full-resolution screenshot is exactly unchanged.
        channel.png = Uint8List.fromList(channel.png!);
        final before = channel.captures;
        await channel.message({'type': 'focus', 'focused': true});
        await _frame(tester, channel);
        expect(channel.captures, greaterThan(before));
        expect(service.visualMirrorFrame.value, same(original));
        expect(original.debugDisposed, false);
        expect(imageNotifications, 0);
        expect(workspaceNotifications, 0);

        channel.png = await tester.runAsync(() => _png(Colors.blue));
        await _frame(tester, channel);
        final changed = service.visualMirrorFrame.value!;
        expect(changed, isNot(same(original)));
        expect(original.debugDisposed, true);
        expect(imageNotifications, 1);
        expect(workspaceNotifications, 0);
        expect(changed.width, 4);
        expect(changed.height, 2);
        final pixels = await tester.runAsync(() => changed.toByteData());
        expect(pixels!.getUint8(3), 0);
        expect(
          pixels.buffer.asUint8List(pixels.offsetInBytes + 4, 4),
          orderedEquals([33, 150, 243, 255]),
        );
        expect(channel.maximumInFlight, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'mirror pauses for overlays, hidden windows, ticker mode and unmount',
    (tester) async {
      final channel = _MirrorChannel()
        ..png = await tester.runAsync(() => _png(Colors.red));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel);
        await service.freezeForOverlay(owner: 'menu');
        await tester.pump();
        var captures = channel.captures;
        await tester.pump(const Duration(seconds: 2));
        expect(channel.captures, captures);
        expect(service.frozenPreview, isNotNull);
        service.setObscured(false, owner: 'menu');
        await _frame(tester, channel);
        expect(channel.captures, greaterThan(captures));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        captures = channel.captures;
        await tester.pump(const Duration(seconds: 2));
        expect(channel.captures, captures);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _frame(tester, channel);
        expect(channel.captures, greaterThan(captures));
        await tester.pumpWidget(_fixture(service, ticking: false));
        captures = channel.captures;
        await tester.pump(const Duration(seconds: 2));
        expect(channel.captures, captures);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        expect(channel.captures, captures);
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(1));
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'rain uses the painted Flutter mirror once and restores native textures after glass',
    (tester) async {
      final channel = _MirrorChannel()
        ..png = await tester.runAsync(() => _png(Colors.red));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel);
        expect(channel.mirrorCalls.last.arguments, true);
        final captures = channel.captures;
        expect(await service.captureRainTexture(), isNull);
        expect(channel.captures, captures);
        await _sync(service, glass: false);
        expect(channel.mirrorCalls.last.arguments, false);
        final texture = await service.captureRainTexture();
        expect(texture?['editorPng'], channel.png);
        expect(channel.captures, captures + 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'caller timeouts and rain/overlay requests never overlap a native snapshot',
    (tester) async {
      final channel = _MirrorChannel()..gate = Completer<Uint8List?>();
      final service = _service(channel);
      try {
        await _start(tester, service);
        await tester.pump(const Duration(milliseconds: 50));
        final rain = service.captureRainTexture();
        final freeze = service.freezeForOverlay(owner: 'menu');
        await tester.pump(const Duration(seconds: 1));
        expect(await rain, isNull);
        await freeze;
        expect(channel.captures, 1);
        expect(channel.maximumInFlight, 1);
        service.setObscured(false, owner: 'menu');
        await tester.pump(const Duration(seconds: 3));
        expect(channel.captures, 1);
        final png = await tester.runAsync(() => _png(Colors.blue));
        channel.gate!.complete(png);
        channel.gate = null;
        channel.png = png;
        await tester.pump();
        await _frame(tester, channel);
        expect(service.visualMirrorFrame.value, isNotNull);
        expect(channel.maximumInFlight, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'mode disable rejects late frames and restores the unchanged direct native path',
    (tester) async {
      final channel = _MirrorChannel()
        ..png = await tester.runAsync(() => _png(Colors.red));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel);
        expect(channel.mirrorCalls.last.arguments, true);
        final image = service.visualMirrorFrame.value!;
        channel.gate = Completer<Uint8List?>();
        await tester.pump(const Duration(milliseconds: 50));
        await _sync(service, glass: false);
        expect(service.visualMirrorFrame.value, isNull);
        expect(image.debugDisposed, true);
        expect(channel.mirrorCalls.last.arguments, false);
        channel.gate!.complete(channel.png);
        await _decode(tester);
        await tester.pump();
        final captures = channel.captures;
        await tester.pump(const Duration(seconds: 2));
        expect(channel.captures, captures);
        expect(service.visualMirrorFrame.value, isNull);
        expect(
          find.byKey(const ValueKey('monaco-visual-mirror')),
          findsNothing,
        );
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(1));
        expect(channel.maximumInFlight, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'active frames use 16 ms, a steady caret uses 50 ms and idle uses 250 ms',
    (tester) async {
      final channel = _MirrorChannel()
        ..png = await tester.runAsync(() => _png(Colors.red));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel);
        await _awaitMirrorFrame(tester, service, null);
        await tester.pump();
        await channel.message({'type': 'focus', 'focused': true});
        for (var index = 0; index < 3; index++) {
          final before = channel.captures;
          await tester.pump(const Duration(milliseconds: 15));
          expect(channel.captures, before);
          await tester.pump(const Duration(milliseconds: 1));
          await _awaitCaptureResponse(tester, channel);
          await tester.pump();
          expect(channel.captures, before + 1);
        }
        final caretGate = channel.gate = Completer<Uint8List?>();
        await tester.pump(const Duration(milliseconds: 600));
        expect(channel.inFlight, 1);
        channel.gate = null;
        caretGate.complete(channel.png);
        await _awaitCaptureResponse(tester, channel);
        await tester.pump();
        final caretBefore = channel.captures;
        await tester.pump(const Duration(milliseconds: 49));
        expect(channel.captures, caretBefore);
        await tester.pump(const Duration(milliseconds: 1));
        await _awaitCaptureResponse(tester, channel);
        await tester.pump();
        expect(channel.captures, caretBefore + 1);
        // Finish the last active capture after its activity window expires,
        // anchoring the first idle interval to this exact completion time.
        final idleGate = channel.gate = Completer<Uint8List?>();
        await channel.message({'type': 'focus', 'focused': false});
        await tester.pump(const Duration(milliseconds: 600));
        expect(channel.inFlight, 1);
        channel.gate = null;
        idleGate.complete(channel.png);
        await _awaitCaptureResponse(tester, channel);
        await tester.pump();
        final before = channel.captures;
        await tester.pump(const Duration(milliseconds: 249));
        expect(channel.captures, before);
        await tester.pump(const Duration(milliseconds: 1));
        await _awaitCaptureResponse(tester, channel);
        await tester.pump();
        expect(channel.captures, before + 1);
        expect(channel.maximumInFlight, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'invalid snapshots keep native painting and recover without recreating Monaco',
    (tester) async {
      final channel = _MirrorChannel()..png = Uint8List.fromList([1, 2, 3]);
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester, channel, expectFrame: false);
        expect(service.visualMirrorFrame.value, isNull);
        expect(channel.mirrorCalls, isEmpty);
        channel.png = await tester.runAsync(() => _png(Colors.blue));
        await _frame(tester, channel);
        expect(service.visualMirrorFrame.value, isNotNull);
        expect(channel.mirrorCalls.last.arguments, true);
        channel.png = null;
        for (var index = 0; index < 3; index++) {
          await _frame(tester, channel, expectFrame: false);
        }
        expect(service.visualMirrorFrame.value, isNull);
        expect(channel.mirrorCalls.last.arguments, false);
        channel.png = await tester.runAsync(() => _png(Colors.red));
        await _frame(tester, channel);
        expect(service.visualMirrorFrame.value, isNotNull);
        expect(channel.mirrorCalls.last.arguments, true);
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets(
    'late snapshots from a stopped renderer cannot populate its replacement',
    (tester) async {
      final oldCapture = Completer<Uint8List?>();
      final channel = _MirrorChannel()..gate = oldCapture;
      final service = _service(channel);
      try {
        await _start(tester, service);
        await tester.pump(const Duration(milliseconds: 50));
        final oldPreview = service.capturePreview();
        await channel.message({
          'type': 'hostError',
          'message': 'Renderer stopped',
        });
        final png = await tester.runAsync(() => _png(Colors.red));
        channel.gate = null;
        channel.png = png;
        await service.initialize();
        oldCapture.complete(png);
        expect(await oldPreview, isNull);
        await tester.pump();
        await _decode(tester);
        expect(service.frozenPreview, isNull);
        expect(service.visualMirrorFrame.value, isNull);
        await _frame(tester, channel);
        expect(service.visualMirrorFrame.value, isNotNull);
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(2));
        expect(channel.mirrorCalls.last.arguments, true);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );

  testWidgets('unmounted and disposed mirrors reject delayed native results', (
    tester,
  ) async {
    final channel = _MirrorChannel()..gate = Completer<Uint8List?>();
    final service = _service(channel);
    await _start(tester, service);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    final calls = channel.calls.length;
    channel.gate!.complete(await tester.runAsync(() => _png(Colors.red)));
    await _decode(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(channel.calls, hasLength(calls));
    expect(channel.mirrorCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final ratio in [1.0, 2.0]) {
    for (final scale in [1.0, 1.25]) {
      testWidgets(
        'mirror aligns with GTK allocation at GUI $scale and DPR $ratio',
        (tester) async {
          tester.view.devicePixelRatio = ratio;
          tester.view.physicalSize = Size(822 * ratio, 523 * ratio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final channel = _MirrorChannel()
            ..png = await tester.runAsync(() => _png(Colors.red));
          final service = _service(channel);
          try {
            await _start(tester, service, scale: scale);
            await _frame(tester, channel);
            final bounds =
                channel.calls
                        .lastWhere((c) => c.method == 'setBounds')
                        .arguments
                    as Map;
            final painted = tester.getRect(
              find.byKey(const ValueKey('monaco-visual-mirror')),
            );
            expect(
              painted.left,
              closeTo((bounds['x'] as double).floorToDouble(), .001),
            );
            expect(
              painted.top,
              closeTo((bounds['y'] as double).floorToDouble(), .001),
            );
            expect(
              painted.width,
              closeTo((bounds['width'] as double).ceilToDouble(), .001),
            );
            expect(
              painted.height,
              closeTo((bounds['height'] as double).ceilToDouble(), .001),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            service.dispose();
          }
        },
      );
    }
  }
}
