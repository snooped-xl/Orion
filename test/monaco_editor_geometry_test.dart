import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/monaco_editor.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';

class _GeometryAssets extends EditorAssetServer {
  @override
  Future<Uri> start() async =>
      Uri.parse('http://127.0.0.1:9999/editor/index.html');
  @override
  Future<void> close() async {}
}

class _GeometryChannel extends MethodChannel {
  _GeometryChannel() : super('orion/geometry-test');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <MethodCall>[];
  Uint8List? preview;

  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? callback) {
    handler = callback;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(MethodCall(method, arguments));
    if (method == 'capturePreview') return preview as T?;
    if (method == 'create') {
      await handler?.call(MethodCall('message', jsonEncode({'type': 'ready'})));
    }
    return null;
  }

  Map get bounds =>
      calls.lastWhere((call) => call.method == 'setBounds').arguments as Map;
}

Widget fixture(
  MonacoEditorService service,
  double scale, {
  bool active = true,
}) => MaterialApp(
  theme: orionTheme(Brightness.dark, const Color(0xFF88B5FF)),
  builder: (context, child) => UiScaleViewport(scale: scale, child: child!),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 40, 10),
      child: MonacoEditor(
        key: const ValueKey('native-editor'),
        service: service,
        active: active,
      ),
    ),
  ),
);

void _expectBounds(_GeometryChannel channel, double scale) {
  expect(channel.bounds['x'], closeTo(20 * scale, .001));
  expect(channel.bounds['y'], closeTo(30 * scale, .001));
  expect(channel.bounds['width'], closeTo(822 - 60 * scale, .001));
  expect(channel.bounds['height'], closeTo(523 - 40 * scale, .001));
  expect(channel.bounds['uiScale'], scale);
}

void main() {
  for (final ratio in [1.0, 2.0]) {
    for (final scale in [.8, 1.0, 1.25]) {
      testWidgets(
        'native rectangle follows viewport scale $scale at DPR $ratio',
        (tester) async {
          tester.view.devicePixelRatio = ratio;
          tester.view.physicalSize = Size(822 * ratio, 523 * ratio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final channel = _GeometryChannel();
          final service = MonacoEditorService(
            channel: channel,
            server: _GeometryAssets(),
            onChange: (_, _) {},
            onShortcut: (_) {},
          );
          await service.synchronize({
            'options': {'uiScale': scale},
          });
          try {
            await tester.pumpWidget(fixture(service, scale));
            await tester.pumpAndSettle();
            _expectBounds(channel, scale);
            expect(channel.bounds['visible'], true);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            service.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'scale changes reuse the native editor and preserve visibility guards',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(822, 523);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final channel = _GeometryChannel();
      final service = MonacoEditorService(
        channel: channel,
        server: _GeometryAssets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await service.synchronize({
          'options': {'uiScale': .8},
        });
        await tester.pumpWidget(fixture(service, .8));
        await tester.pumpAndSettle();
        service.setObscured(true);
        await service.synchronize({
          'options': {'uiScale': 1.25},
        });
        await tester.pumpWidget(fixture(service, 1.25));
        await tester.pumpAndSettle();
        _expectBounds(channel, 1.25);
        expect(channel.bounds['visible'], false);
        expect(
          channel.calls.where((call) => call.method == 'create'),
          hasLength(1),
        );
        service.setObscured(false);
        await tester.pumpAndSettle();
        expect(channel.bounds['visible'], true);
        await tester.pumpWidget(fixture(service, 1.25, active: false));
        await tester.pumpAndSettle();
        expect(channel.bounds['visible'], false);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );
  testWidgets(
    'hidden native editor paints its captured PNG frame then removes it when revealed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(822, 523);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final frame = (await rootBundle.load(
        'assets/original_xeno/open.png',
      )).buffer.asUint8List();
      final channel = _GeometryChannel()..preview = frame;
      final service = MonacoEditorService(
        channel: channel,
        server: _GeometryAssets(),
        onChange: (_, _) {},
        onShortcut: (_) {},
      );
      try {
        await tester.pumpWidget(fixture(service, 1));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(
          find.byKey(const ValueKey('native-editor')),
        );
        expect(
          find.byKey(const ValueKey('monaco-frozen-preview')),
          findsNothing,
        );
        await service.freezeForOverlay(owner: 'context-menu');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pumpAndSettle();
        final frozen = find.byKey(const ValueKey('monaco-frozen-preview'));
        expect(frozen, findsOneWidget);
        final image = tester.widget<Image>(frozen);
        expect((image.image as MemoryImage).bytes, orderedEquals(frame));
        expect(image.fit, BoxFit.fill);
        expect(tester.getRect(frozen), bounds);
        expect(channel.bounds['visible'], false);
        service.setObscured(false, owner: 'context-menu');
        await tester.pumpAndSettle();
        expect(frozen, findsNothing);
        expect(channel.bounds['visible'], true);
        expect(
          channel.calls.where((call) => call.method == 'create'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
    },
  );
}
