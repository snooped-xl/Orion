import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/widgets/native_desktop_glass.dart';
import 'package:orion/widgets/orion_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compositor changes only background alpha and retains editing', (
    tester,
  ) async {
    const channel = MethodChannel('orion/window');
    var backendActive = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => '{"ok":true,"active":$backendActive}',
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await tester.runAsync(OrionGlassScene.preload);
    final capture = GlobalKey();
    final focus = FocusNode();
    final text = TextEditingController(text: 'retained draft');
    addTearDown(focus.dispose);
    addTearDown(text.dispose);

    Widget app(double radius) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 260,
          height: 160,
          child: NativeDesktopGlassViewport(
            supported: true,
            enabled: true,
            opacity: .5,
            cornerRadius: radius,
            builder: (context, _) => RepaintBoundary(
              key: capture,
              child: OrionGlassScene(
                reducedMotion: true,
                backdrop: const ColoredBox(color: Color(0xffff0000)),
                child: OrionGlassSurface(
                  tint: Colors.transparent,
                  child: SizedBox.expand(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 20,
                            top: 20,
                            width: 160,
                            child: TextField(
                              controller: text,
                              focusNode: focus,
                            ),
                          ),
                          const Positioned(
                            right: 20,
                            bottom: 20,
                            width: 8,
                            height: 8,
                            child: ColoredBox(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(20));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    backendActive = true;
    await tester.pumpWidget(app(21));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, true);
    expect(text.text, 'retained draft');
    expect(
      NativeDesktopGlassScope.isActiveOf(tester.element(find.byKey(capture))),
      true,
    );

    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(capture))
          .toImage(pixelRatio: 1);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> at(int x, int y) => [
        for (var channel = 0; channel < 4; channel++)
          pixels.getUint8((y * 260 + x) * 4 + channel),
      ];
      // rawRgba stores premultiplied components: only the background fades.
      expect(at(200, 100), [128, 0, 0, 128]);
      expect(at(235, 135), [255, 255, 255, 255]);
      image.dispose();
    });
    backendActive = false;
    await tester.pumpWidget(app(22));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, true);
    expect(text.text, 'retained draft');
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(capture))
          .toImage(pixelRatio: 1);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(pixels.getUint8((100 * 260 + 200) * 4 + 3), 255);
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
