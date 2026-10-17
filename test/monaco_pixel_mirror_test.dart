import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/widgets/monaco_editor.dart';

class _Assets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');
  @override
  Future<void> close() async {}
}

class _Pixels extends MethodChannel {
  _Pixels() : super('orion/pixel-mirror-test');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  int frame = 1, active = 0, maximumActive = 0, transferredFrames = 0;
  Uint8List bytes = Uint8List.fromList([0, 0, 0, 0, 64, 32, 16, 128]);
  Uint8List? png;
  Object? invalid;
  Completer<void>? pixelGate;
  bool gateUsed = false;

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) =>
      handler = callback;

  Future<void> message(Map<String, Object?> value) async =>
      handler?.call(MethodCall('message', jsonEncode(value)));

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(MethodCall(method, arguments));
    if (method == 'create') {
      await message({'type': 'ready'});
      return {'pixelPreview': true} as T;
    }
    if (method == 'capturePreview' || method == 'capturePreviewPixels') {
      active++;
      maximumActive = maximumActive < active ? active : maximumActive;
      try {
        if (method == 'capturePreview') return png as T?;
        final response =
            invalid ??
            <String, Object?>{
              'frame': frame,
              'width': 2,
              'height': 1,
              if ((arguments as Map)['frame'] != frame) 'pixels': bytes,
            };
        if (response is Map && response['pixels'] != null) transferredFrames++;
        if (pixelGate != null && !gateUsed) {
          gateUsed = true;
          await pixelGate!.future;
        }
        return response as T;
      } finally {
        active--;
      }
    }
    return null;
  }
}

MonacoEditorService _service(_Pixels channel) => MonacoEditorService(
  channel: channel,
  server: _Assets(),
  onChange: (_, _) {},
  onShortcut: (_) {},
);

Future<void> _start(WidgetTester tester, MonacoEditorService service) async {
  await service.synchronize({
    'documents': [
      {'id': 'source', 'name': 'source.lua', 'content': ''},
    ],
    'activeId': 'source',
    'options': {'compositorGlass': true},
  });
  await tester.pumpWidget(
    MaterialApp(
      home: MonacoEditor(
        service: service,
        active: true,
        backgroundColor: Colors.transparent,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _frame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

Future<Uint8List> _png(Uint8List pixels) async {
  final complete = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    2,
    1,
    ui.PixelFormat.rgba8888,
    complete.complete,
  );
  final image = await complete.future;
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> _dispose(WidgetTester tester, MonacoEditorService service) async {
  await tester.pumpWidget(const SizedBox.shrink());
  service.dispose();
}

void main() {
  testWidgets(
    'raw decode and lossless PNG decode preserve every alpha value exactly',
    (tester) async {
      await tester.runAsync(() async {
        final pixels = Uint8List(256 * 256 * 4);
        for (int a = 0; a < 256; a++) {
          for (int c = 0; c < 256; c++) {
            final offset = (a * 256 + c) * 4;
            pixels[offset] = c * (a + 1) ~/ 256;
            pixels[offset + 1] = (255 - c) * (a + 1) ~/ 256;
            pixels[offset + 2] = ((c * 73) % 256) * (a + 1) ~/ 256;
            pixels[offset + 3] = a;
          }
        }
        final complete = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          256,
          256,
          ui.PixelFormat.rgba8888,
          complete.complete,
        );
        final raw = await complete.future;
        ui.Codec? codec;
        ui.Image? decoded;
        try {
          final png = (await raw.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          codec = await ui.instantiateImageCodec(png);
          decoded = (await codec.getNextFrame()).image;
          final actual = (await decoded.toByteData())!.buffer.asUint8List();
          expect(actual, pixels);
        } finally {
          raw.dispose();
          decoded?.dispose();
          codec?.dispose();
        }
      });
    },
  );

  testWidgets(
    'raw mirror preserves premultiplied alpha and only hides native after painting',
    (tester) async {
      final channel = _Pixels();
      final service = _service(channel);
      try {
        await _start(tester, service);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        final image = service.visualMirrorFrame.value!;
        expect(
          channel.calls.where((c) => c.method == 'setVisualMirror'),
          isEmpty,
        );
        final pixels = await tester.runAsync(() => image.toByteData());
        expect(pixels!.buffer.asUint8List(), channel.bytes);
        await tester.pump();
        expect(
          channel.calls
              .lastWhere((c) => c.method == 'setVisualMirror')
              .arguments,
          true,
        );
        expect(
          channel.calls.where((c) => c.method == 'capturePreview'),
          isEmpty,
        );
      } finally {
        await _dispose(tester, service);
      }
    },
  );

  testWidgets(
    'unchanged frame IDs retain exact image without retransferring pixels',
    (tester) async {
      final channel = _Pixels();
      final service = _service(channel);
      try {
        await _start(tester, service);
        await _frame(tester);
        final image = service.visualMirrorFrame.value!;
        var imageChanges = 0, workspaceChanges = 0;
        service.visualMirrorFrame.addListener(() => imageChanges++);
        service.addListener(() => workspaceChanges++);
        await channel.message({'type': 'focus', 'focused': true});
        for (int n = 0; n < 5; n++) {
          await _frame(tester);
        }
        expect(identical(image, service.visualMirrorFrame.value), true);
        expect(imageChanges, 0);
        expect(workspaceChanges, 0);
        expect(channel.transferredFrames, 1);
        expect(channel.maximumActive, 1);

        channel.frame++;
        channel.bytes = Uint8List.fromList([20, 30, 40, 255, 4, 8, 12, 64]);
        await channel.message({'type': 'interaction'});
        await _frame(tester);
        final replacement = service.visualMirrorFrame.value!;
        expect(identical(image, replacement), false);
        expect(image.debugDisposed, true);
        expect(channel.transferredFrames, 2);
        final pixels = await tester.runAsync(() => replacement.toByteData());
        expect(pixels!.buffer.asUint8List(), channel.bytes);
        expect(workspaceChanges, 0);
      } finally {
        await _dispose(tester, service);
      }
    },
  );

  testWidgets(
    'PNG overlay snapshot waits for live pixels and remains lossless PNG',
    (tester) async {
      final channel = _Pixels()..pixelGate = Completer<void>();
      channel.png = await tester.runAsync(() => _png(channel.bytes));
      final service = _service(channel);
      try {
        await _start(tester, service);
        await tester.pump(const Duration(milliseconds: 20));
        expect(channel.active, 1);
        final overlay = service.freezeForOverlay();
        await tester.pump();
        expect(
          channel.calls.where((c) => c.method == 'capturePreview'),
          isEmpty,
        );
        channel.pixelGate!.complete();
        await tester.pump();
        await overlay;
        expect(channel.maximumActive, 1);
        expect(service.frozenPreview, channel.png);
        expect(service.visible, false);
        expect(service.visualMirrorFrame.value, isNull);
      } finally {
        await _dispose(tester, service);
      }
    },
  );

  testWidgets('malformed pixel frame falls back to original PNG safely', (
    tester,
  ) async {
    final channel = _Pixels()
      ..invalid = {
        'frame': 1,
        'width': 900000,
        'height': 1,
        'pixels': Uint8List(0),
      };
    channel.png = await tester.runAsync(() => _png(channel.bytes));
    final service = _service(channel);
    try {
      await _start(tester, service);
      await _frame(tester);
      expect(service.visualMirrorFrame.value, isNotNull);
      expect(
        channel.calls.where((c) => c.method == 'capturePreview'),
        isNotEmpty,
      );
      expect(channel.maximumActive, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, service);
    }
  });

  testWidgets('late pixel frame cannot outlive its editor service', (
    tester,
  ) async {
    final channel = _Pixels()..pixelGate = Completer<void>();
    final service = _service(channel);
    await _start(tester, service);
    await tester.pump(const Duration(milliseconds: 20));
    expect(channel.active, 1);
    await _dispose(tester, service);
    channel.pixelGate!.complete();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(channel.active, 0);
    expect(channel.calls.where((c) => c.method == 'setVisualMirror'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renderer replacement rejects old raw pixels and resets its frame ID',
    (tester) async {
      final channel = _Pixels()..pixelGate = Completer<void>();
      final service = _service(channel);
      try {
        await _start(tester, service);
        await tester.pump(const Duration(milliseconds: 20));
        expect(channel.active, 1);
        await channel.message({
          'type': 'hostError',
          'message': 'Owned renderer restart',
        });
        channel.bytes = Uint8List.fromList([30, 70, 160, 255, 10, 20, 30, 64]);
        await service.initialize();
        channel.pixelGate!.complete();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        expect(service.visualMirrorFrame.value, isNull);
        await _frame(tester);
        final pixels = await tester.runAsync(
          () => service.visualMirrorFrame.value!.toByteData(),
        );
        expect(pixels!.buffer.asUint8List(), channel.bytes);
        expect(channel.calls.where((c) => c.method == 'create'), hasLength(2));
        final captures = channel.calls.where(
          (c) => c.method == 'capturePreviewPixels',
        );
        expect((captures.last.arguments as Map)['frame'], 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, service);
      }
    },
  );
}
