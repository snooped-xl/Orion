import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';
import 'package:orion/widgets/desktop_frame.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  const plugin = MethodChannel('window_manager');
  const native = MethodChannel('orion/window');
  final calls = <MethodCall>[];
  final listenersAdded = <WindowListener>[];
  var maximized = false;
  var fullscreen = false;
  var platform = TargetPlatform.macOS;

  setUp(() {
    calls.clear();
    listenersAdded
      ..clear()
      ..addAll(windowManager.listeners);
    maximized = false;
    fullscreen = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isMaximized' => maximized,
        'isFullScreen' => fullscreen,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    for (final listener in windowManager.listeners.toList()) {
      if (!listenersAdded.contains(listener)) {
        windowManager.removeListener(listener);
      }
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });

  final nativeCornerPlatform = Platform.isLinux || Platform.isWindows;
  bool syncCorners = true;

  Widget frame({
    required Widget child,
    GlobalKey<NavigatorState>? navigatorKey,
    bool syncNativeCorners = true,
    bool glass = false,
  }) => MaterialApp(
    navigatorKey: navigatorKey,
    theme: orionTheme(
      Brightness.dark,
      Colors.blue,
      preferences: glass
          ? OrionThemePreferences.builtInPresets
                .singleWhere((preset) => preset.id == 'blue-glass')
                .preferences
          : null,
    ).copyWith(platform: platform),
    builder: (_, child) => DesktopFrame(
      enabled: true,
      reducedMotion: true,
      cornerRadius: 20,
      syncNativeCorners:
          syncNativeCorners &&
              (platform == TargetPlatform.linux ||
                  platform == TargetPlatform.windows)
          ? syncCorners
          : syncNativeCorners && nativeCornerPlatform,
      child: child!,
    ),
    home: child,
  );

  double radius(WidgetTester tester) {
    final widget = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(DesktopFrame),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    return ((widget.decoration! as BoxDecoration).borderRadius! as BorderRadius)
        .topLeft
        .x;
  }

  testWidgets('clips the page and every dialog at the same 20px window edge', (
    tester,
  ) async {
    syncCorners = nativeCornerPlatform;
    final navigator = GlobalKey<NavigatorState>();
    var pageTaps = 0;
    var dialogTaps = 0;
    await tester.pumpWidget(
      frame(
        navigatorKey: navigator,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => pageTaps++,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(radius(tester), 20);
    expect(
      calls
          .where((call) => call.method == 'setCornerRadius')
          .map((c) => (c.arguments as Map)['radius']),
      nativeCornerPlatform ? [20.0] : isEmpty,
    );
    await tester.tapAt(const Offset(1, 1));
    expect(pageTaps, 0);
    await tester.tapAt(const Offset(40, 40));
    expect(pageTaps, 1);
    await tester.pump(const Duration(milliseconds: 100));

    showGeneralDialog<void>(
      context: navigator.currentContext!,
      pageBuilder: (_, _, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => dialogTaps++,
        child: const ColoredBox(color: Colors.green),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1, 1));
    expect(dialogTaps, 0);
    await tester.tapAt(const Offset(40, 40));
    expect(dialogTaps, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the visible arc resizes diagonally without covering controls', (
    tester,
  ) async {
    platform = TargetPlatform.linux;
    syncCorners = true;
    var contentTaps = 0;
    await tester.pumpWidget(
      frame(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => contentTaps++,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // (10,3) is on the visible 20px arc, outside a square 5px handle.
    final pointer = await tester.startGesture(const Offset(10, 3));
    await pointer.moveBy(const Offset(24, 24));
    await tester.pump();
    await pointer.up();
    expect(
      calls.where((call) => call.method == 'startResizing').single.arguments,
      {
        'resizeEdge': 'topLeft',
        'top': true,
        'bottom': false,
        'right': false,
        'left': true,
      },
    );
    // The arc's inner area remains part of the content, not a resize handle.
    await tester.tapAt(const Offset(18, 18));
    expect(contentTaps, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('maximized and fullscreen edges are square until restored', (
    tester,
  ) async {
    platform = TargetPlatform.linux;
    syncCorners = true;
    calls.clear();
    final original = windowManager.listeners;
    maximized = true;
    await tester.pumpWidget(frame(child: const ColoredBox(color: Colors.red)));
    await tester.pumpAndSettle();
    await tester.pump();
    final listener = windowManager.listeners.singleWhere(
      (listener) => !original.contains(listener),
    );
    await tester.pump();
    expect(radius(tester), 0);
    expect(find.byType(DragToResizeArea), findsNothing);
    maximized = false;
    listener.onWindowUnmaximize();
    await tester.pumpAndSettle();
    expect(radius(tester), 20);
    await tester.pump();
    fullscreen = true;
    listener.onWindowEnterFullScreen();
    await tester.pumpAndSettle();
    expect(radius(tester), 0);
    await tester.pump();
    fullscreen = false;
    listener.onWindowLeaveFullScreen();
    await tester.pumpAndSettle();
    expect(radius(tester), 20);
    await tester.pump();
    expect(
      calls
          .where((call) => call.method == 'setCornerRadius')
          .map((c) => (c.arguments as Map)['radius']),
      nativeCornerPlatform ? [20.0] : isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Blue Glass has clipped native corners but no drawn outline', (
    tester,
  ) async {
    syncCorners = true;
    await tester.pumpWidget(
      frame(glass: true, child: const ColoredBox(color: Colors.red)),
    );
    await tester.pumpAndSettle();
    final frameContainer = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(DesktopFrame),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(frameContainer.foregroundDecoration, isNull);
    expect(
      calls
          .where((call) => call.method == 'setCornerRadius')
          .map((c) => (c.arguments as Map)['radius']),
      nativeCornerPlatform ? [20.0] : isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing frames do not acquire a native input shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(
        syncNativeCorners: false,
        child: const ColoredBox(color: Colors.red),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DragToResizeArea), findsOneWidget);
    expect(calls.where((call) => call.method == 'setCornerRadius'), isEmpty);
  });

  testWidgets('changing native glass corners preserves the editor and focus', (
    tester,
  ) async {
    const editor = Scaffold(body: TextField());
    await tester.pumpWidget(frame(syncNativeCorners: false, child: editor));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'print("glass")');
    final state = tester.state(find.byType(TextField));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, true);
    for (final sync in [true, false, true]) {
      await tester.pumpWidget(frame(syncNativeCorners: sync, child: editor));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(state));
      expect(editable.controller.text, 'print("glass")');
      expect(editable.focusNode.hasFocus, true);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native curved frame antialiases the composed scene once at every pixel scale',
    (tester) async {
      final boundaryKey = GlobalKey();
      Widget scene(bool sync) => MaterialApp(
        theme: orionTheme(Brightness.dark, Colors.blue),
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 96,
              height: 96,
              child: DesktopFrame(
                enabled: true,
                syncNativeCorners: sync,
                reducedMotion: true,
                cornerRadius: 24,
                borderColor: Colors.transparent,
                child: Stack(
                  fit: StackFit.expand,
                  children: const [
                    ColoredBox(color: Color(0xffff0000)),
                    ColoredBox(color: Color(0xff0000ff)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(true));
      await tester.pumpAndSettle();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      for (final scale in [1.0, 1.25, 2.0]) {
        final image = await tester.runAsync(
          () => boundary.toImage(pixelRatio: scale),
        );
        final pixels = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        var partial = 0;
        for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4) {
          final alpha = pixels.getUint8(offset + 3);
          if (alpha > 0 && alpha < 255) partial++;
          expect(
            pixels.getUint8(offset),
            lessThanOrEqualTo(1),
            reason:
                'covered red draw must not bleed beyond 8-bit rounding into the final blue edge at $scale',
          );
        }
        expect(
          partial,
          greaterThan(10),
          reason: 'edge coverage remains per-pixel antialiased at $scale',
        );
        expect(
          pixels.getUint8(3),
          0,
          reason: 'outside corner stays transparent',
        );
        image!.dispose();
      }
      // A control with the unchanged source-frame AA path reproduces the
      // overlap fringe, proving the regression actually exercises it.
      await tester.pumpWidget(scene(false));
      await tester.pumpAndSettle();
      final control = await tester.runAsync(() => boundary.toImage());
      final controlPixels = await tester.runAsync(
        () => control!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      var fringe = 0;
      for (var offset = 0; offset < controlPixels!.lengthInBytes; offset += 4) {
        if (controlPixels.getUint8(offset) > fringe) {
          fringe = controlPixels.getUint8(offset);
        }
      }
      expect(fringe, greaterThan(10));
      control!.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
