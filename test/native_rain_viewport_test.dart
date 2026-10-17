import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/native_rain_viewport.dart';
import 'package:orion/services/monaco_editor_service.dart';
import 'package:orion/effects/orion_rain_simulation.dart';
import 'package:orion/widgets/ui_scale_viewport.dart';
import 'package:window_manager/window_manager.dart';

class _RainEditor extends MonacoEditorService {
  _RainEditor() : super(onChange: (_, _) {}, onShortcut: (_) {});
  int captures = 0, visibilityChanges = 0;
  Completer<Map<String, Object?>?>? gate;
  @override
  Future<Map<String, Object?>?> captureRainTexture() async {
    captures++;
    if (gate != null) return gate!.future;
    return {
      'editorPng': Uint8List.fromList([1, 2, 3]),
      'editorX': 94.0,
      'editorY': 131.0,
      'editorWidth': 640.0,
      'editorHeight': 260.0,
    };
  }

  @override
  void setObscured(bool value, {String owner = 'route'}) {
    visibilityChanges++;
  }
}

Widget _rain({
  bool enabled = true,
  bool reduced = false,
  Widget? child,
  MonacoEditorService? editor,
  double scale = 1,
  double opacity = .9,
}) => MaterialApp(
  builder: (context, navigator) => NativeRainViewport(
    supported: true,
    rainEnabled: enabled,
    windowOpacity: opacity,
    reducedMotion: reduced,
    cornerRadius: 16,
    editorService: editor,
    child: UiScaleViewport(scale: scale, child: navigator!),
  ),
  home: Scaffold(body: child ?? const SizedBox.expand()),
);

Future<void> _rainFrames(WidgetTester tester, [int count = 8]) async {
  for (var n = 0; n < count; n++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 8)),
    );
    await tester.pump();
  }
}

Map _args(MethodCall call) => call.arguments as Map;
List<double> _packet(MethodCall call) =>
    List<double>.from(_args(call)['data'] as List);

void main() {
  const channel = MethodChannel('orion/rain');
  const windowChannel = MethodChannel('window_manager');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
            return false;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  testWidgets(
    'native opacity updates and restores without intercepting input',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return {'nativeRain': true};
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      var taps = 0;
      Widget app(double opacity, {bool supported = true}) => MaterialApp(
        home: NativeRainViewport(
          supported: supported,
          rainEnabled: false,
          windowOpacity: opacity,
          reducedMotion: true,
          cornerRadius: 16,
          child: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(.9));
      expect((calls.last.arguments as Map)['opacity'], .9);
      await tester.tap(find.text('Open'));
      expect(taps, 1);
      await tester.pumpWidget(app(1));
      expect((calls.last.arguments as Map)['opacity'], 1);
      await tester.pumpWidget(app(.9, supported: false));
      expect((calls.last.arguments as Map)['enabled'], false);
      expect((calls.last.arguments as Map)['opacity'], 1);
      final countAfterDisable = calls.length;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(calls.length, countAfterDisable);
      expect((calls.last.arguments as Map)['enabled'], false);
      expect((calls.last.arguments as Map)['opacity'], 1);
    },
  );

  testWidgets('non-native previews never configure desktop effects', (
    tester,
  ) async {
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls++;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await tester.pumpWidget(
      const NativeRainViewport(
        supported: false,
        rainEnabled: true,
        windowOpacity: .9,
        reducedMotion: false,
        cornerRadius: 16,
        child: SizedBox(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, 0);
  });
  testWidgets(
    'idle rain keeps sampling the native editor without scheduling Flutter frames',
    (tester) async {
      final frames = <Uint8List>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'frame') {
          frames.add(_args(call)['png'] as Uint8List);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final editor = _RainEditor();
      await tester.pumpWidget(_rain(editor: editor));
      await _rainFrames(tester, 12);
      final initialSamples = frames.length;
      final initialEditorSamples = editor.captures;
      var flutterFrames = 0;
      var trackFrames = true;
      void track(Duration _) {
        flutterFrames++;
        if (trackFrames) tester.binding.addPostFrameCallback(track);
      }

      tester.binding.addPostFrameCallback(track);
      await _rainFrames(tester, 30);
      trackFrames = false;
      expect(frames.length - initialSamples, greaterThanOrEqualTo(9));
      expect(editor.captures - initialEditorSamples, greaterThanOrEqualTo(9));
      expect(
        flutterFrames,
        0,
        reason:
            'native rain physics and snapshots must not redraw idle Flutter',
      );
      for (final frame in frames.skip(initialSamples)) {
        expect(frame, orderedEquals(frames[initialSamples - 1]));
      }
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      editor.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rain captures independently repainting descendants and composed transforms',
    (tester) async {
      final frames = <Uint8List>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'frame') {
          frames.add(_args(call)['png'] as Uint8List);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final color = ValueNotifier(Colors.blue);
      final offset = ValueNotifier(Offset.zero);
      await tester.pumpWidget(
        _rain(
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: offset,
              builder: (context, offset, child) =>
                  Transform.translate(offset: offset, child: child),
              child: RepaintBoundary(
                child: ValueListenableBuilder(
                  valueListenable: color,
                  builder: (context, color, child) => SizedBox.square(
                    dimension: 80,
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _rainFrames(tester, 10);
      final initial = frames.last;
      color.value = Colors.red;
      await _rainFrames(tester, 10);
      final repainted = frames.last;
      expect(repainted, isNot(orderedEquals(initial)));
      offset.value = const Offset(32, 12);
      await _rainFrames(tester, 10);
      final transformed = frames.last;
      expect(transformed, isNot(orderedEquals(repainted)));
      await _rainFrames(tester, 6);
      expect(frames.last, orderedEquals(transformed));
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      color.dispose();
      offset.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active rain sends evolving bounded physics packets and samples the editor without obscuring it',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final editor = _RainEditor();
      await tester.pumpWidget(_rain(editor: editor));
      await _rainFrames(tester, 12);
      final drops = calls.where((call) => call.method == 'drops').toList();
      expect(drops.length, greaterThan(3));
      final first = _packet(drops.first), last = _packet(drops.last);
      expect(first, isNotEmpty);
      expect(first.length % OrionRainSimulation.stride, 0);
      expect(first.every((value) => value.isFinite), true);
      expect(first, isNot(orderedEquals(last)));
      expect(_args(drops.last)['width'], 800);
      expect(_args(drops.last)['height'], 600);
      final frames = calls.where((call) => call.method == 'frame').toList();
      expect(frames, isNotEmpty);
      expect((_args(frames.last)['png'] as Uint8List).take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      expect(_args(frames.last)['editorX'], 94);
      expect(_args(frames.last)['editorY'], 131);
      expect(_args(frames.last)['editorWidth'], 640);
      expect(_args(frames.last)['editorHeight'], 260);
      expect(editor.captures, greaterThan(0));
      expect(editor.visibilityChanges, 0);
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
      editor.dispose();
    },
  );

  testWidgets(
    'reduced motion keeps seeded drops fixed while refreshing their live texture',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain(reduced: true));
      await _rainFrames(tester, 26);
      final drops = calls.where((call) => call.method == 'drops').toList();
      expect(drops.length, greaterThanOrEqualTo(2));
      expect(_packet(drops.first), isNotEmpty);
      for (final call in drops.skip(1)) {
        expect(_packet(call), orderedEquals(_packet(drops.first)));
      }
      expect(
        calls.where((call) => call.method == 'frame').length,
        greaterThanOrEqualTo(2),
      );
      expect(_args(calls.first)['reducedMotion'], true);
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disable and dispose stop physics and texture callbacks even with a pending drops response',
    (tester) async {
      final calls = <MethodCall>[];
      final dropGate = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'drops' && !dropGate.isCompleted) {
          await dropGate.future;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 6);
      expect(
        calls.where((call) => call.method == 'drops').length,
        1,
        reason: 'one in-flight packet prevents native channel backlog',
      );
      await tester.pumpWidget(_rain(enabled: false));
      final disabledAt = calls.length;
      dropGate.complete();
      await _rainFrames(tester, 16);
      expect(calls.length, disabledAt);
      expect(_args(calls.last)['enabled'], false);
      await tester.pumpWidget(const SizedBox());
      final disposedAt = calls.length;
      await _rainFrames(tester, 4);
      expect(calls.length, disposedAt);
      expect(_args(calls.last)['opacity'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late configure completion cannot restart rain after the theme is disabled',
    (tester) async {
      final calls = <MethodCall>[];
      final firstConfigure = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (calls.length == 1) await firstConfigure.future;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await tester.pumpWidget(_rain(enabled: false));
      firstConfigure.complete();
      await _rainFrames(tester, 12);
      expect(calls.map((call) => call.method), ['configure', 'configure']);
      expect(_args(calls.last)['enabled'], false);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a captured editor texture is discarded when rain is turned off during capture',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final editor = _RainEditor()..gate = Completer<Map<String, Object?>?>();
      await tester.pumpWidget(_rain(reduced: true, editor: editor));
      await _rainFrames(tester, 8);
      expect(editor.captures, 1);
      await tester.pumpWidget(
        _rain(enabled: false, reduced: true, editor: editor),
      );
      final count = calls.length;
      editor.gate!.complete({
        'editorPng': Uint8List.fromList([4, 5, 6]),
      });
      await _rainFrames(tester, 8);
      expect(calls.length, count);
      expect(calls.where((call) => call.method == 'frame'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
      editor.dispose();
    },
  );

  testWidgets(
    'resize uses the painted viewport coordinates independently of GUI scale',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1644, 1046);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_rain(scale: 1.25));
      await _rainFrames(tester);
      var packet = calls.lastWhere((call) => call.method == 'drops');
      expect(_args(packet)['width'], 822);
      expect(_args(packet)['height'], 523);
      tester.view.physicalSize = const Size(1480, 940);
      await _rainFrames(tester);
      packet = calls.lastWhere((call) => call.method == 'drops');
      expect(_args(packet)['width'], 740);
      expect(_args(packet)['height'], 470);
      final data = _packet(packet);
      expect(data.length % OrionRainSimulation.stride, 0);
      for (var n = 0; n < data.length; n += OrionRainSimulation.stride) {
        expect(data[n], inInclusiveRange(-40, 780));
        expect(data[n + 1], inInclusiveRange(-100, 570));
      }
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native window minimize pauses callbacks and restore restarts without leaking listeners',
    (tester) async {
      final calls = <MethodCall>[];
      final originalListeners = Set.of(windowManager.listeners);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 4);
      final listener = windowManager.listeners
          .where((listener) => !originalListeners.contains(listener))
          .single;
      listener.onWindowMinimize();
      await tester.pump();
      final count = calls.length;
      await _rainFrames(tester, 8);
      expect(calls.length, count);
      expect(_args(calls.last)['enabled'], false);
      listener.onWindowRestore();
      await _rainFrames(tester, 4);
      expect(
        calls.where((call) => call.method == 'drops').length,
        greaterThan(2),
      );
      listener.onWindowMaximize();
      await tester.pump();
      expect(
        _args(
          calls.lastWhere((call) => call.method == 'configure'),
        )['cornerRadius'],
        0,
      );
      listener.onWindowUnmaximize();
      await tester.pump();
      expect(
        _args(
          calls.lastWhere((call) => call.method == 'configure'),
        )['cornerRadius'],
        16,
      );
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(Set.of(windowManager.listeners), originalListeners);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('active glass preserves text input and menu interaction', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final input = TextEditingController();
    Widget contents() => Column(
      children: [
        TextField(key: const ValueKey('rain-text'), controller: input),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Menu'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Open menu'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(_rain(child: contents()));
    await _rainFrames(tester, 3);
    final cleanFrame = Uint8List.fromList(
      _args(calls.lastWhere((call) => call.method == 'frame'))['png']
          as Uint8List,
    );
    await tester.enterText(
      find.byKey(const ValueKey('rain-text')),
      'print("still editable")',
    );
    await tester.tap(find.text('Open menu'));
    await _rainFrames(tester, 7);
    expect(find.text('Menu'), findsOneWidget);
    expect(
      _args(calls.lastWhere((call) => call.method == 'frame'))['png'],
      isNot(orderedEquals(cleanFrame)),
      reason: 'the sampled boundary includes Navigator dialog content',
    );
    expect(input.text, 'print("still editable")');
    expect(calls.where((call) => call.method == 'drops'), isNotEmpty);
    await tester.tap(find.text('Close'));
    await _rainFrames(tester, 7);
    expect(find.text('Menu'), findsNothing);
    expect(input.text, 'print("still editable")');
    await tester.pumpWidget(const SizedBox());
    await _rainFrames(tester, 2);
    input.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'temporary GL configuration errors retry twice and recover boundedly',
    (tester) async {
      final calls = <MethodCall>[];
      var configureAttempts = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'configure' && ++configureAttempts < 3) {
          throw PlatformException(code: 'gl_not_ready');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 25);
      expect(configureAttempts, 3);
      expect(calls.where((call) => call.method == 'drops'), isNotEmpty);
      await _rainFrames(tester, 10);
      expect(configureAttempts, 3);
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration retries are cancelled by disabling and by disposal',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'configure' && _args(call)['enabled'] == true) {
          throw PlatformException(code: 'gl_not_ready');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(_rain(enabled: false));
      final disabled = calls.length;
      await _rainFrames(tester, 20);
      expect(calls.length, disabled);
      await tester.pumpWidget(_rain());
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(const SizedBox());
      final disposed = calls.length;
      await _rainFrames(tester, 20);
      expect(calls.length, disposed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing native drops support stops animation instead of repeatedly failing',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'drops') {
          throw MissingPluginException('optional GL effect unavailable');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 6);
      final stoppedAt = calls.length;
      await _rainFrames(tester, 15);
      expect(calls.length, stoppedAt);
      expect(calls.where((call) => call.method == 'drops').length, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an initially maximized native window starts with square glass corners',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        (call) async => call.method == 'isMaximized',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain(enabled: false, reduced: true));
      await tester.pump();
      expect(
        _args(
          calls.lastWhere((call) => call.method == 'configure'),
        )['cornerRadius'],
        0,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late window shape queries cannot overwrite a newer maximize event',
    (tester) async {
      final calls = <MethodCall>[];
      final originalListeners = Set.of(windowManager.listeners);
      final initialMaximized = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        (call) async {
          if (call.method == 'isMaximized') return initialMaximized.future;
          return false;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain(enabled: false, reduced: true));
      final listener = windowManager.listeners
          .where((listener) => !originalListeners.contains(listener))
          .single;
      listener.onWindowMaximize();
      await tester.pump();
      initialMaximized.complete(false);
      await tester.pump();
      expect(
        _args(
          calls.lastWhere((call) => call.method == 'configure'),
        )['cornerRadius'],
        0,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing reduced motion freezes the current drops then resumes their motion',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 8);
      await tester.pumpWidget(_rain(reduced: true));
      final freezeStarted = calls.length;
      await _rainFrames(tester, 26);
      final frozen = calls
          .skip(freezeStarted)
          .where((call) => call.method == 'drops')
          .toList();
      expect(frozen.length, greaterThanOrEqualTo(2));
      for (final packet in frozen.skip(1)) {
        expect(_packet(packet), orderedEquals(_packet(frozen.first)));
      }
      await tester.pumpWidget(_rain());
      await _rainFrames(tester, 8);
      final moving = calls.lastWhere((call) => call.method == 'drops');
      expect(_packet(moving), isNot(orderedEquals(_packet(frozen.last))));
      await tester.pumpWidget(const SizedBox());
      await _rainFrames(tester, 2);
      expect(tester.takeException(), isNull);
    },
  );
  for (final failingMethod in ['configure', 'drops', 'frame']) {
    testWidgets(
      'fatal shader failure during $failingMethod stops packets and still restores the next theme opacity',
      (tester) async {
        final calls = <MethodCall>[];
        var failed = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            if (!failed && call.method == failingMethod) {
              failed = true;
              throw PlatformException(code: 'rain_shader_unavailable');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(_rain());
        await _rainFrames(tester, 8);
        expect(failed, true);
        final stoppedAt = calls.length;
        final fallback = _args(
          calls.lastWhere((call) => call.method == 'configure'),
        );
        expect(fallback['enabled'], false);
        expect(fallback['opacity'], .9);
        await _rainFrames(tester, 18);
        expect(
          calls.length,
          stoppedAt,
          reason:
              'a permanent GL failure stops physics, texture captures and retries',
        );
        await tester.pumpWidget(_rain(enabled: false, opacity: 1));
        await _rainFrames(tester, 2);
        final reset = _args(
          calls.lastWhere((call) => call.method == 'configure'),
        );
        expect(reset['enabled'], false);
        expect(reset['opacity'], 1);
        final resetAt = calls.length;
        await _rainFrames(tester, 8);
        expect(calls.length, resetAt);
        await tester.pumpWidget(const SizedBox());
        await _rainFrames(tester, 2);
        expect(_args(calls.last)['opacity'], 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
